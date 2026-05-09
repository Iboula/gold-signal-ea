using GoldSignal.Ai.Api.Data;
using GoldSignal.Ai.Api.Hubs;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddHttpClient();
builder.Services.AddSignalR();

var connectionString = builder.Configuration.GetConnectionString("TradingDb");

if (!string.IsNullOrWhiteSpace(connectionString))
{
    builder.Services.AddDbContext<TradingDbContext>(options =>
        options.UseNpgsql(connectionString));
}

var app = builder.Build();

if (!string.IsNullOrWhiteSpace(connectionString))
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<TradingDbContext>();
    await db.Database.MigrateAsync();
}

app.UseSwagger();
app.UseSwaggerUI();

app.MapGet("/health", () => Results.Ok(new
{
    status = "ok",
    service = "GoldSignal.Ai.Api"
}));

app.MapGet("/api/signals/recent", async (TradingDbContext db, int take = 50) =>
{
    take = Math.Clamp(take, 1, 200);

    var signals = await db.TradingSignals
        .OrderByDescending(x => x.CreatedAtUtc)
        .Take(take)
        .ToListAsync();

    return Results.Ok(signals);
});

app.MapPost("/api/signals/analyze", async (
    SignalRequest request,
    IHttpClientFactory httpClientFactory,
    IConfiguration configuration,
    ILoggerFactory loggerFactory,
    IServiceProvider serviceProvider,
    IHubContext<SignalsHub> hubContext) =>
{
    var logger = loggerFactory.CreateLogger("SignalAnalyzer");
    var apiKey = configuration["ANTHROPIC_API_KEY"];

    if (string.IsNullOrWhiteSpace(apiKey))
    {
        return Results.BadRequest(new SignalValidationResponse(
            Approved: false,
            Score: 0,
            Comment: "ANTHROPIC_API_KEY missing"));
    }

    var prompt = BuildPrompt(request);
    var systemPrompt = BuildSystemPrompt();

    var payload = new
    {
        model = configuration["Anthropic:Model"] ?? "claude-haiku-4-5-20251001",
        max_tokens = int.TryParse(configuration["Anthropic:MaxTokens"], out var mt) ? mt : 512,
        temperature = 0.1,
        system = systemPrompt,
        messages = new object[]
        {
            new { role = "user", content = prompt }
        }
    };

    var client = httpClientFactory.CreateClient();
    client.DefaultRequestHeaders.Add("x-api-key", apiKey);
    client.DefaultRequestHeaders.Add("anthropic-version", configuration["Anthropic:Version"] ?? "2023-06-01");

    HttpResponseMessage response;
    try
    {
        response = await client.PostAsJsonAsync("https://api.anthropic.com/v1/messages", payload);
    }
    catch (Exception ex)
    {
        logger.LogWarning(ex, "Anthropic call threw");
        return Results.Ok(new SignalValidationResponse(false, 0, "AI validation unavailable (network)"));
    }

    var content = await response.Content.ReadAsStringAsync();

    SignalValidationResponse validation;

    if (!response.IsSuccessStatusCode)
    {
        logger.LogWarning("Anthropic call failed: {StatusCode} {Content}", response.StatusCode, content);
        validation = new SignalValidationResponse(false, 0, "AI validation unavailable");
    }
    else
    {
        var assistantText = ExtractAssistantContent(content);
        validation = ParseValidation(assistantText);
    }

    var savedSignal = await PersistSignalIfConfiguredAsync(serviceProvider, request, validation, logger);

    if (savedSignal is not null)
    {
        await hubContext.Clients.All.SendAsync("signal-received", savedSignal);
    }

    logger.LogInformation(
        "Signal {Action} {Symbol} approved={Approved} score={Score}",
        request.Action,
        request.Symbol,
        validation.Approved,
        validation.Score);

    return Results.Ok(validation);
});

app.MapHub<SignalsHub>("/hubs/signals");

app.Run();

static async Task<TradingSignal?> PersistSignalIfConfiguredAsync(
    IServiceProvider serviceProvider,
    SignalRequest request,
    SignalValidationResponse validation,
    ILogger logger)
{
    var db = serviceProvider.GetService<TradingDbContext>();

    if (db is null)
    {
        logger.LogInformation("TradingDb connection not configured. Signal persistence skipped.");
        return null;
    }

    var signal = new TradingSignal
    {
        Symbol = request.Symbol,
        Action = request.Action,
        Entry = request.Entry,
        StopLoss = request.StopLoss,
        TakeProfit = request.TakeProfit,
        AlgoScore = request.Confidence,
        AiScore = validation.Score,
        Approved = validation.Approved,
        Spread = request.Spread,
        Atr = request.Atr,
        Session = request.Session,
        Reason = request.Reason,
        AiComment = validation.Comment,
        Source = "MT5"
    };

    db.TradingSignals.Add(signal);
    await db.SaveChangesAsync();

    return signal;
}

static string BuildSystemPrompt() => """
You are an institutional-grade scalp signal validator for XAUUSD (Gold) and BTCUSD (Bitcoin), running behind a Smart Money Concepts / ICT-style MT5 expert advisor.

Validation framework — apply mentally on every signal:
1. Structure alignment: a signal that fights HTF structure (M15/H1) starts with a -10 score penalty. Aligned signals start neutral.
2. Liquidity logic: prefer entries that follow a clean liquidity sweep (equal highs/lows, prior session H/L) and a BOS or CHoCH in the trade direction. Penalize entries directly into unswept liquidity in the trade direction.
3. Spread quality: reject if spread eats more than 25% of the SL distance (entry-to-SL).
4. Volatility regime: reject if ATR is too low (chop) or extreme (news shock). BTCUSD tolerates wider ATR than XAUUSD.
5. Session timing: prefer London (08:00-12:00 UTC) and NY (12:30-16:30 UTC) kill zones. Penalize Asian / late-NY entries unless symbol is BTCUSD (24/7).
6. Symbol calibration:
   - XAUUSD: very strict around CPI, NFP, FOMC ±30 min. Reject if "Reason" hints at news-driven volatility.
   - BTCUSD: reject during weekend illiquidity (very wide spreads) and during obvious low-vol consolidation.
7. Reason quality: if the EA's "Reason" is vague or generic, lower the score.

Be strict. Only approve setups a discretionary desk trader would actually take. Average setups must be rejected.

OUTPUT: STRICT JSON only, no prose, no markdown, exact shape:
{"approved": true|false, "score": 0..100, "comment": "concise rationale, max 140 chars"}
""";

static string BuildPrompt(SignalRequest request) => $$"""
Validate this scalp signal:

- Symbol: {{request.Symbol}}
- Action: {{request.Action}}
- Entry: {{request.Entry}}
- StopLoss: {{request.StopLoss}}
- TakeProfit (TP1): {{request.TakeProfit}}
- Algo confidence: {{request.Confidence}}
- Spread (points): {{request.Spread}}
- ATR (points): {{request.Atr}}
- Session label: {{request.Session}}
- Reason: {{request.Reason}}

Apply the validation framework. Return STRICT JSON only with shape: {"approved": bool, "score": int 0-100, "comment": "<=140 chars"}.
""";

static string ExtractAssistantContent(string anthropicJson)
{
    using var document = JsonDocument.Parse(anthropicJson);
    var root = document.RootElement;

    if (!root.TryGetProperty("content", out var contentArray) || contentArray.GetArrayLength() == 0)
    {
        return string.Empty;
    }

    foreach (var block in contentArray.EnumerateArray())
    {
        if (block.TryGetProperty("type", out var type)
            && type.GetString() == "text"
            && block.TryGetProperty("text", out var text))
        {
            return text.GetString() ?? string.Empty;
        }
    }

    return string.Empty;
}

static SignalValidationResponse ParseValidation(string assistantText)
{
    if (string.IsNullOrWhiteSpace(assistantText))
    {
        return new SignalValidationResponse(false, 0, "AI returned empty response");
    }

    var jsonStart = assistantText.IndexOf('{');
    var jsonEnd = assistantText.LastIndexOf('}');

    if (jsonStart < 0 || jsonEnd <= jsonStart)
    {
        return new SignalValidationResponse(false, 0, "AI returned non JSON response");
    }

    var json = assistantText[jsonStart..(jsonEnd + 1)];

    try
    {
        var parsed = JsonSerializer.Deserialize<SignalValidationResponse>(
            json,
            new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });

        if (parsed is null)
        {
            return new SignalValidationResponse(false, 0, "AI JSON parse failed");
        }

        var score = Math.Clamp(parsed.Score, 0, 100);
        return parsed with { Score = score };
    }
    catch
    {
        return new SignalValidationResponse(false, 0, "AI JSON parse failed");
    }
}

public sealed class SignalRequest
{
    public string Symbol { get; set; } = "UNKNOWN";
    public string Action { get; set; } = string.Empty;
    public double Entry { get; set; }
    public double StopLoss { get; set; }
    public double TakeProfit { get; set; }
    public double Confidence { get; set; }
    public double Spread { get; set; }
    public double Atr { get; set; }
    public string Session { get; set; } = string.Empty;
    public string Reason { get; set; } = string.Empty;
}

public sealed record SignalValidationResponse(
    bool Approved,
    double Score,
    string Comment);

using GoldSignal.Ai.Api.Data;
using Microsoft.EntityFrameworkCore;
using System.Net.Http.Headers;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddHttpClient();

var connectionString = builder.Configuration.GetConnectionString("TradingDb");

if (!string.IsNullOrWhiteSpace(connectionString))
{
    builder.Services.AddDbContext<TradingDbContext>(options =>
        options.UseNpgsql(connectionString));
}

var app = builder.Build();

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
    IServiceProvider serviceProvider) =>
{
    var logger = loggerFactory.CreateLogger("SignalAnalyzer");
    var apiKey = configuration["OPENAI_API_KEY"];

    if (string.IsNullOrWhiteSpace(apiKey))
    {
        return Results.BadRequest(new SignalValidationResponse(
            Approved: false,
            Score: 0,
            Comment: "OPENAI_API_KEY missing"));
    }

    var prompt = BuildPrompt(request);

    var payload = new
    {
        model = configuration["OpenAI:Model"] ?? "gpt-4.1-mini",
        messages = new object[]
        {
            new
            {
                role = "system",
                content = "You are an institutional XAUUSD signal validator. Return JSON only."
            },
            new
            {
                role = "user",
                content = prompt
            }
        },
        temperature = 0.1
    };

    var client = httpClientFactory.CreateClient();
    client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);

    var response = await client.PostAsJsonAsync("https://api.openai.com/v1/chat/completions", payload);
    var content = await response.Content.ReadAsStringAsync();

    SignalValidationResponse validation;

    if (!response.IsSuccessStatusCode)
    {
        logger.LogWarning("OpenAI call failed: {StatusCode} {Content}", response.StatusCode, content);
        validation = new SignalValidationResponse(false, 0, "AI validation unavailable");
    }
    else
    {
        var assistantText = ExtractAssistantContent(content);
        validation = ParseValidation(assistantText);
    }

    await PersistSignalIfConfiguredAsync(serviceProvider, request, validation, logger);

    logger.LogInformation(
        "Signal {Action} {Symbol} approved={Approved} score={Score}",
        request.Action,
        request.Symbol,
        validation.Approved,
        validation.Score);

    return Results.Ok(validation);
});

app.Run();

static async Task PersistSignalIfConfiguredAsync(
    IServiceProvider serviceProvider,
    SignalRequest request,
    SignalValidationResponse validation,
    ILogger logger)
{
    var db = serviceProvider.GetService<TradingDbContext>();

    if (db is null)
    {
        logger.LogInformation("TradingDb connection not configured. Signal persistence skipped.");
        return;
    }

    db.TradingSignals.Add(new TradingSignal
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
    });

    await db.SaveChangesAsync();
}

static string BuildPrompt(SignalRequest request) => $$"""
Validate this XAUUSD scalp signal.

Rules:
- Reject if confidence is weak.
- Reject if spread is too high for scalping.
- Reject if ATR is too low or chaotic.
- Prefer clean sweep + BOS in London or New York session.
- Be strict. Do not approve average setups.

Signal:
- Symbol: {{request.Symbol}}
- Action: {{request.Action}}
- Entry: {{request.Entry}}
- SL: {{request.StopLoss}}
- TP1: {{request.TakeProfit}}
- Confidence: {{request.Confidence}}
- Spread: {{request.Spread}}
- ATR: {{request.Atr}}
- Session: {{request.Session}}
- Reason: {{request.Reason}}

Return JSON only with this shape:
{
  "approved": true,
  "score": 85,
  "comment": "short explanation"
}
""";

static string ExtractAssistantContent(string openAiJson)
{
    using var document = JsonDocument.Parse(openAiJson);
    var root = document.RootElement;

    if (!root.TryGetProperty("choices", out var choices) || choices.GetArrayLength() == 0)
    {
        return string.Empty;
    }

    var firstChoice = choices[0];

    if (!firstChoice.TryGetProperty("message", out var message))
    {
        return string.Empty;
    }

    if (!message.TryGetProperty("content", out var content))
    {
        return string.Empty;
    }

    return content.GetString() ?? string.Empty;
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
    public string Symbol { get; set; } = "XAUUSD";
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

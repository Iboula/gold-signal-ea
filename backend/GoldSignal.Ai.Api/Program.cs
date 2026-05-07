using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddHttpClient();

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI();

app.MapGet("/health", () => Results.Ok(new
{
    status = "ok",
    service = "GoldSignal.Ai.Api"
}));

app.MapPost("/api/signals/analyze", async (
    SignalRequest request,
    IHttpClientFactory httpClientFactory,
    IConfiguration configuration) =>
{
    var apiKey = configuration["OPENAI_API_KEY"];

    if (string.IsNullOrWhiteSpace(apiKey))
    {
        return Results.BadRequest(new
        {
            error = "OPENAI_API_KEY missing"
        });
    }

    var prompt = $"""
You are validating a XAUUSD scalp trading signal.

Signal:
- Action: {request.Action}
- Entry: {request.Entry}
- SL: {request.StopLoss}
- TP1: {request.TakeProfit}
- Confidence: {request.Confidence}
- Spread: {request.Spread}
- ATR: {request.Atr}
- Session: {request.Session}
- Reason: {request.Reason}

Return JSON only:
{
  \"approved\": true/false,
  \"score\": 0-100,
  \"comment\": \"short explanation\"
}
""";

    var payload = new
    {
        model = "gpt-4.1-mini",
        messages = new object[]
        {
            new
            {
                role = "system",
                content = "You are an institutional XAUUSD signal validator."
            },
            new
            {
                role = "user",
                content = prompt
            }
        },
        temperature = 0.2
    };

    var client = httpClientFactory.CreateClient();

    client.DefaultRequestHeaders.Authorization =
        new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", apiKey);

    var response = await client.PostAsJsonAsync(
        "https://api.openai.com/v1/chat/completions",
        payload);

    var content = await response.Content.ReadAsStringAsync();

    return Results.Ok(new
    {
        raw = JsonDocument.Parse(content)
    });
});

app.Run();

public sealed class SignalRequest
{
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

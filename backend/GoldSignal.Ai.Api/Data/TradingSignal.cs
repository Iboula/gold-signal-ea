namespace GoldSignal.Ai.Api.Data;

public sealed class TradingSignal
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;

    public string Symbol { get; set; } = "XAUUSD";

    public string Action { get; set; } = string.Empty;

    public double Entry { get; set; }

    public double StopLoss { get; set; }

    public double TakeProfit { get; set; }

    public double AlgoScore { get; set; }

    public double AiScore { get; set; }

    public bool Approved { get; set; }

    public double Spread { get; set; }

    public double Atr { get; set; }

    public string Session { get; set; } = string.Empty;

    public string Reason { get; set; } = string.Empty;

    public string AiComment { get; set; } = string.Empty;

    public string Source { get; set; } = "MT5";
}

namespace GoldSignal.Dashboard.Models;

public sealed class SignalDto
{
    public Guid Id { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public string Symbol { get; set; } = string.Empty;
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
    public string Source { get; set; } = string.Empty;
}

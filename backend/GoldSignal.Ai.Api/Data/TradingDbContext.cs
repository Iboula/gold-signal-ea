using Microsoft.EntityFrameworkCore;

namespace GoldSignal.Ai.Api.Data;

public sealed class TradingDbContext : DbContext
{
    public TradingDbContext(DbContextOptions<TradingDbContext> options)
        : base(options)
    {
    }

    public DbSet<TradingSignal> TradingSignals => Set<TradingSignal>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        var signal = modelBuilder.Entity<TradingSignal>();

        signal.HasKey(x => x.Id);

        signal.Property(x => x.Symbol)
            .HasMaxLength(20);

        signal.Property(x => x.Action)
            .HasMaxLength(20);

        signal.Property(x => x.Session)
            .HasMaxLength(50);

        signal.Property(x => x.Source)
            .HasMaxLength(50);

        signal.Property(x => x.Reason)
            .HasMaxLength(2000);

        signal.Property(x => x.AiComment)
            .HasMaxLength(2000);

        signal.HasIndex(x => x.CreatedAtUtc);
        signal.HasIndex(x => x.Symbol);
        signal.HasIndex(x => x.Approved);
    }
}

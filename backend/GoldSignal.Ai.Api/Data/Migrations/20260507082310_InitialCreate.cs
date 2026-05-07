using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace GoldSignal.Ai.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "TradingSignals",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    Symbol = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    Action = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    Entry = table.Column<double>(type: "double precision", nullable: false),
                    StopLoss = table.Column<double>(type: "double precision", nullable: false),
                    TakeProfit = table.Column<double>(type: "double precision", nullable: false),
                    AlgoScore = table.Column<double>(type: "double precision", nullable: false),
                    AiScore = table.Column<double>(type: "double precision", nullable: false),
                    Approved = table.Column<bool>(type: "boolean", nullable: false),
                    Spread = table.Column<double>(type: "double precision", nullable: false),
                    Atr = table.Column<double>(type: "double precision", nullable: false),
                    Session = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    Reason = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: false),
                    AiComment = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: false),
                    Source = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TradingSignals", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_TradingSignals_Approved",
                table: "TradingSignals",
                column: "Approved");

            migrationBuilder.CreateIndex(
                name: "IX_TradingSignals_CreatedAtUtc",
                table: "TradingSignals",
                column: "CreatedAtUtc");

            migrationBuilder.CreateIndex(
                name: "IX_TradingSignals_Symbol",
                table: "TradingSignals",
                column: "Symbol");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "TradingSignals");
        }
    }
}

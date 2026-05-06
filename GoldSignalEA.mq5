//+------------------------------------------------------------------+
//|                                                 GoldSignalEA.mq5 |
//|                                                            Yazil |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Yazil"
#property link      "https://www.mql5.com"
#property version   "1.00"
#include "GoldSignalEngine.mqh"
#include "RiskManager.mqh"
#include "TradeManager.mqh"

input double RiskPercent = 0.1;        // très prudent
input double MaxLot = 0.10;            // sécurité importante
input int MagicNumber = 20260429;
input bool AutoTrade = true;          // parfait pour tester
input double FinalTPMultiplier = 2.0;  // bon ratio TP final
input double MaxSpread = 50;           // OK pour XAUUSD selon broker
input int CooldownMinutes = 15;        // bon anti-surtrading
input bool UseSessionFilter = true;
input int LondonStartHour = 9;
input int NewYorkEndHour = 17;
input bool BlockHour08 = true;
input bool UseAllowedEntryHours = false;
input string AllowedEntryHours = "8,9,10,11,15,16";
input double MinConfidence = 75.0;
input bool UseManualButton = false;
input bool ResetCsvOnTesterStart = true;
input int BreakoutLookback = 20;
input double StopBuffer = 1.0;
input double BreakoutConfirmPoints = 20.0;
input double BuyRsiMin = 55.0;
input double BuyRsiMax = 72.0;
input double SellRsiMin = 28.0;
input double SellRsiMax = 45.0;
input bool AllowBuySignals = true;
input bool AllowSellSignals = true;
input int MaxTradesPerDay = 4;
input double MaxDailyLossMoney = 25.0;
input double DailyProfitLockMoney = 15.0;
input int MaxConsecutiveLosses = 3;
input bool UseNoTradeWindow = false;
input int NoTradeStartHour = 12;
input int NoTradeEndHour = 15;
input bool UseAtrStopCap = true;
input int AtrStopPeriod = 14;
input double AtrStopMultiplier = 1.5;
input double MaxStopDistancePoints = 1800.0;
input bool UsePullbackEntry = false;
input int PullbackCandles = 2;
input int PullbackWindowBars = 7;
input double PullbackBreakoutConfirmPoints = 5.0;
input bool UseH4ZoneRetest = true;
input bool H4UsePreviousDayRange = true;
input int H4ZoneFirstBars = 1;
input int H4RetestWindowBars = 18;
input double H4RetestTolerancePoints = 120.0;
input double H4BreakoutMinPoints = 120.0;
input double H4BreakoutBodyPct = 35.0;
input bool H4RequireM15Trend = false;
input double H4SLBufferPoints = 120.0;

#define TRADES_JOURNAL_FILE "GoldSignalEA_Trades.csv"
#define SIGNAL_CONTEXT_FILE "GoldSignalEA_SignalContext.csv"

//En démo semi-réelle
//RiskPercent = 0.1
//MaxLot = 0.05 ou 0.10
//AutoTrade = false d’abord
//UseSessionFilter = true

//En auto-test démo uniquement
//AutoTrade = true
//RiskPercent = 0.1
//MaxLot = 0.05

void CreateAcceptButton()
{
   if(!UseManualButton)
      return;

   string buttonName = "BTN_ACCEPT_SIGNAL";

   if(ObjectFind(0, buttonName) >= 0)
      return;

   if(!ObjectCreate(0, buttonName, OBJ_BUTTON, 0, 0, 0))
   {
      Print("Erreur creation bouton manuel: ", GetLastError());
      return;
   }

   ObjectSetInteger(0, buttonName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, buttonName, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, buttonName, OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, buttonName, OBJPROP_XSIZE, 120);
   ObjectSetInteger(0, buttonName, OBJPROP_YSIZE, 24);
   ObjectSetString(0, buttonName, OBJPROP_TEXT, "ACCEPTER");
   ObjectSetInteger(0, buttonName, OBJPROP_FONTSIZE, 8);
}

int OpenCsvFile(string fileName)
{
   int fileHandle = FileOpen(fileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');

   if(fileHandle != INVALID_HANDLE)
      return fileHandle;

   fileHandle = FileOpen(fileName, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');

   if(fileHandle == INVALID_HANDLE)
      return INVALID_HANDLE;

   FileClose(fileHandle);

   return FileOpen(fileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
}

void ResetTesterCsvFiles()
{
   if(!ResetCsvOnTesterStart)
      return;

   if(!MQLInfoInteger(MQL_TESTER))
      return;

   FileDelete(TRADES_JOURNAL_FILE, FILE_COMMON);
   FileDelete(SIGNAL_CONTEXT_FILE, FILE_COMMON);
}

bool EnsureTradesJournalFile()
{
   int fileHandle = OpenCsvFile(TRADES_JOURNAL_FILE);

   if(fileHandle == INVALID_HANDLE)
   {
      Print("Erreur ouverture Trades CSV: ", GetLastError());
      return false;
   }

   if(FileSize(fileHandle) == 0)
   {
      FileWrite(
         fileHandle,
         "Date",
         "Symbol",
         "PositionId",
         "DealTicket",
         "Direction",
         "OpenDate",
         "DurationMinutes",
         "Volume",
         "EntryPrice",
         "ClosePrice",
         "Profit",
         "Result",
         "RSI_M5",
         "ATR_M5",
         "ATR_M5_Change",
         "EMA20_M15",
         "EMA50_M15",
         "EMA_Distance",
         "M15Trend"
      );
   }

   FileClose(fileHandle);
   return true;
}

bool EnsureSignalContextFile()
{
   int fileHandle = OpenCsvFile(SIGNAL_CONTEXT_FILE);

   if(fileHandle == INVALID_HANDLE)
   {
      Print("Erreur ouverture Signal Context CSV: ", GetLastError());
      return false;
   }

   if(FileSize(fileHandle) == 0)
   {
      FileWrite(
         fileHandle,
         "Date",
         "Symbol",
         "Action",
         "Setup",
         "Entry",
         "SL",
         "TP1",
         "TPFinal",
         "Lot",
         "Spread",
         "Confidence",
         "RSI_M5",
         "EMA20_M15",
         "EMA50_M15",
         "EMA_Distance",
         "ATR_M5",
         "ATR_M5_Change",
         "M15Trend",
         "TradesToday",
         "DailyPnL",
         "ConsecutiveLosses",
         "InSession",
         "InNoTradeWindow",
         "CanTrade",
         "BlockReason",
         "Config",
         "Reason"
      );
   }

   FileClose(fileHandle);
   return true;
}

bool IsClosingDeal(long entryType)
{
   return entryType == DEAL_ENTRY_OUT ||
          entryType == DEAL_ENTRY_OUT_BY ||
          entryType == DEAL_ENTRY_INOUT;
}

string DealTypeToDirection(long dealType)
{
   if(dealType == DEAL_TYPE_BUY)
      return "BUY";

   if(dealType == DEAL_TYPE_SELL)
      return "SELL";

   return "UNKNOWN";
}

bool FindOpeningDeal(long positionId, datetime &openTime, double &openPrice, string &direction)
{
   openTime = 0;
   openPrice = 0.0;
   direction = "UNKNOWN";

   int totalDeals = HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);

      if(HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) != positionId)
         continue;

      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol)
         continue;

      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber)
         continue;

      if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;

      openTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      openPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      direction = DealTypeToDirection(HistoryDealGetInteger(dealTicket, DEAL_TYPE));
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   ResetTesterCsvFiles();
   EnsureTradesJournalFile();
   EnsureSignalContextFile();
   Print("GoldSignalEA config: ", GetActiveConfigSummary());
   CreateAcceptButton();
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectDelete(0, "BTN_ACCEPT_SIGNAL");
}
  
double CalculateFinalTP(const SignalResult &signal)
{
   if(signal.action == SIGNAL_BUY || signal.action == SIGNAL_BUY_LIMIT)
      return signal.entry + MathAbs(signal.entry - signal.sl) * FinalTPMultiplier;

   if(signal.action == SIGNAL_SELL || signal.action == SIGNAL_SELL_LIMIT)
      return signal.entry - MathAbs(signal.entry - signal.sl) * FinalTPMultiplier;

   return 0.0;
}

datetime lastTradeTime = 0;

double GetSpreadPoints()
{
   return (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
}

bool CanTradeNow()
{
   return GetTradeFilterReason() == "OK";
}

string GetTradeFilterReason()
{
   double spread = GetSpreadPoints();

   if(spread > MaxSpread)
      return "Spread trop eleve";

   if((TimeCurrent() - lastTradeTime) < (CooldownMinutes * 60))
      return "Cooldown actif";

   if(IsBlockedHour08())
      return "Heure 08 bloquee";

   if(!IsAllowedEntryHour())
      return "Heure non autorisee";

   if(!IsTradingSession())
      return "Hors session";

   if(IsNoTradeWindow())
      return "Fenetre no-trade";

   string dailyRiskReason = GetDailyRiskBlockReason();

   if(dailyRiskReason != "OK")
      return dailyRiskReason;

   return "OK";
}

bool IsTradingSession()
{
   if(!UseSessionFilter)
      return true;

   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);

   int hour = timeStruct.hour;

   if(hour >= LondonStartHour && hour <= NewYorkEndHour)
      return true;

   return false;
}

bool IsNoTradeWindow()
{
   if(!UseNoTradeWindow)
      return false;

   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);

   int hour = timeStruct.hour;

   if(NoTradeStartHour == NoTradeEndHour)
      return false;

   if(NoTradeStartHour < NoTradeEndHour)
      return hour >= NoTradeStartHour && hour < NoTradeEndHour;

   return hour >= NoTradeStartHour || hour < NoTradeEndHour;
}

bool IsBlockedHour08()
{
   if(!BlockHour08)
      return false;

   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);

   return timeStruct.hour == 8;
}

bool IsAllowedEntryHour()
{
   if(!UseAllowedEntryHours)
      return true;

   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);

   string hourText = IntegerToString(timeStruct.hour);
   string list = "," + AllowedEntryHours + ",";

   StringReplace(list, " ", "");

   return StringFind(list, "," + hourText + ",") >= 0;
}

datetime GetDayStart(datetime value)
{
   MqlDateTime timeStruct;
   TimeToStruct(value, timeStruct);
   timeStruct.hour = 0;
   timeStruct.min = 0;
   timeStruct.sec = 0;

   return StructToTime(timeStruct);
}

void GetDailyClosedTradeStats(int &closedTrades, double &profit, int &consecutiveLosses)
{
   closedTrades = 0;
   profit = 0.0;
   consecutiveLosses = 0;

   datetime dayStart = GetDayStart(TimeCurrent());

   if(!HistorySelect(dayStart, TimeCurrent()))
      return;

   int totalDeals = HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);

      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol)
         continue;

      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber)
         continue;

      if(!IsClosingDeal(HistoryDealGetInteger(dealTicket, DEAL_ENTRY)))
         continue;

      closedTrades++;
      profit += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   }

   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong dealTicket = HistoryDealGetTicket(i);

      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol)
         continue;

      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber)
         continue;

      if(!IsClosingDeal(HistoryDealGetInteger(dealTicket, DEAL_ENTRY)))
         continue;

      double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);

      if(dealProfit < 0)
      {
         consecutiveLosses++;
         continue;
      }

      break;
   }
}

bool IsDailyRiskAllowed()
{
   return GetDailyRiskBlockReason() == "OK";
}

string GetDailyRiskBlockReason()
{
   int closedTrades = 0;
   int consecutiveLosses = 0;
   double dailyProfit = 0.0;

   GetDailyClosedTradeStats(closedTrades, dailyProfit, consecutiveLosses);

   if(MaxTradesPerDay > 0 && closedTrades >= MaxTradesPerDay)
      return "Max trades jour atteint";

   if(MaxDailyLossMoney > 0 && dailyProfit <= -MaxDailyLossMoney)
      return "Perte jour max atteinte";

   if(DailyProfitLockMoney > 0 && dailyProfit >= DailyProfitLockMoney)
      return "Profit lock jour atteint";

   if(MaxConsecutiveLosses > 0 && consecutiveLosses >= MaxConsecutiveLosses)
      return "Pertes consecutives max";

   return "OK";
}

SignalResult lastSignal;
double lastLot = 0.0;
double lastFinalTP = 0.0;
string lastLoggedContextKey = "";

string GetTradeBlockReason(const SignalResult &signal, bool canTrade, bool confidenceOK)
{
   if(signal.action == SIGNAL_WAIT)
   {
      if(signal.reason != "" && signal.reason != "Pas de setup clair")
         return "WAIT - " + signal.reason;

      return "WAIT - aucun setup";
   }

   if(HasActiveTradeOrOrder(MagicNumber))
      return "Trade ou ordre deja actif";

   if(!confidenceOK)
      return "Confiance insuffisante";

   if(!canTrade)
      return GetTradeFilterReason();

   if(!AutoTrade)
      return "AutoTrade OFF";

   return "Pret a trader";
}

ulong lastLoggedDealTicket = 0;

string GetM15TrendLabel(double ema20, double ema50)
{
   if(ema20 <= 0 || ema50 <= 0)
      return "UNKNOWN";

   if(ema20 > ema50)
      return "BULLISH";

   if(ema20 < ema50)
      return "BEARISH";

   return "FLAT";
}

double GetSafeAtrChange()
{
   double atrCurrent = GetATRValue(PERIOD_M5, AtrStopPeriod, 1);
   double atrPrevious = GetATRValue(PERIOD_M5, AtrStopPeriod, 2);

   if(atrCurrent <= 0 || atrPrevious <= 0)
      return 0.0;

   return atrCurrent - atrPrevious;
}

string GetActiveConfigSummary()
{
   return
      "Session=" + (UseSessionFilter ? "ON" : "OFF") +
      "|LondonStart=" + IntegerToString(LondonStartHour) +
      "|NYEnd=" + IntegerToString(NewYorkEndHour) +
      "|AllowedHours=" + (UseAllowedEntryHours ? AllowedEntryHours : "OFF") +
      "|Block08=" + (BlockHour08 ? "ON" : "OFF") +
      "|NoTrade=" + (UseNoTradeWindow ? "ON" : "OFF") +
      "|NoTradeWindow=" + IntegerToString(NoTradeStartHour) + "-" + IntegerToString(NoTradeEndHour) +
      "|ProfitLock=" + DoubleToString(DailyProfitLockMoney, 2) +
      "|ATRCap=" + (UseAtrStopCap ? "ON" : "OFF") +
      "|Pullback=" + (UsePullbackEntry ? "ON" : "OFF") +
      "|H4ZoneRetest=" + (UseH4ZoneRetest ? "ON" : "OFF") +
      "|H4ZoneSource=" + (H4UsePreviousDayRange ? "PrevD1" : "FirstH4") +
      "|H4RetestBars=" + IntegerToString(H4RetestWindowBars);
}

void LogSignalContextToCSV(
   const SignalResult &signal,
   double finalTP,
   double lot,
   double spread,
   string setupQuality,
   bool canTrade,
   string blockReason,
   int dailyClosedTrades,
   double dailyProfit,
   int dailyConsecutiveLosses,
   bool inSession,
   bool inNoTradeWindow
)
{
   bool isPullbackState =
      signal.reason != "pullback idle" &&
      (StringFind(signal.reason, "pullback") >= 0 ||
       StringFind(signal.reason, "Pullback") >= 0 ||
       StringFind(signal.reason, "Fenetre") >= 0 ||
       StringFind(signal.reason, "Setup detecte") >= 0);
   bool isH4ZoneState =
      StringFind(signal.reason, "H4 zone") >= 0 ||
      StringFind(signal.reason, "H4/D1 zone") >= 0;

   if(signal.action == SIGNAL_WAIT && !isPullbackState && !isH4ZoneState)
      return;

   datetime candleTime = iTime(_Symbol, PERIOD_M5, 1);
   string contextKey =
      TimeToString(candleTime, TIME_DATE | TIME_MINUTES) + "_" +
      SignalActionToString(signal.action);

   if(contextKey == lastLoggedContextKey)
      return;

   double rsiM5 = GetRSIValue(PERIOD_M5, 14, 1);
   double ema20M15 = GetEMAValue(PERIOD_M15, 20, 1);
   double ema50M15 = GetEMAValue(PERIOD_M15, 50, 1);
   double atrM5 = GetATRValue(PERIOD_M5, AtrStopPeriod, 1);
   double atrM5Change = GetSafeAtrChange();
   double emaDistance = ema20M15 - ema50M15;

   int fileHandle = OpenCsvFile(SIGNAL_CONTEXT_FILE);

   if(fileHandle == INVALID_HANDLE)
   {
      Print("Erreur ouverture Signal Context CSV: ", GetLastError());
      return;
   }

   FileSeek(fileHandle, 0, SEEK_END);

   FileWrite(
      fileHandle,
      TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES),
      _Symbol,
      SignalActionToString(signal.action),
      setupQuality,
      DoubleToString(signal.entry, _Digits),
      DoubleToString(signal.sl, _Digits),
      DoubleToString(signal.tp1, _Digits),
      DoubleToString(finalTP, _Digits),
      DoubleToString(lot, 2),
      DoubleToString(spread, 1),
      DoubleToString(signal.confidence, 1),
      DoubleToString(rsiM5, 2),
      DoubleToString(ema20M15, _Digits),
      DoubleToString(ema50M15, _Digits),
      DoubleToString(emaDistance, _Digits),
      DoubleToString(atrM5, _Digits),
      DoubleToString(atrM5Change, _Digits),
      GetM15TrendLabel(ema20M15, ema50M15),
      IntegerToString(dailyClosedTrades),
      DoubleToString(dailyProfit, 2),
      IntegerToString(dailyConsecutiveLosses),
      inSession ? "YES" : "NO",
      inNoTradeWindow ? "YES" : "NO",
      canTrade ? "YES" : "NO",
      blockReason,
      GetActiveConfigSummary(),
      signal.reason
   );

   FileClose(fileHandle);
   lastLoggedContextKey = contextKey;
}

void LogClosedTradesToCSV()
{
   HistorySelect(0, TimeCurrent());

   int totalDeals = HistoryDealsTotal();

   ulong newestLoggedTicket = lastLoggedDealTicket;

   for(int i = 0; i < totalDeals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);

      if(dealTicket <= lastLoggedDealTicket)
         continue;

      string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);

      if(symbol != _Symbol)
         continue;

      long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);

      if(magic != MagicNumber)
         continue;

      long entryType = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

      if(!IsClosingDeal(entryType))
         continue;

      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      double price = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      double volume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
      datetime closeTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      long positionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      datetime openTime = 0;
      double openPrice = 0.0;
      string direction = "UNKNOWN";
      FindOpeningDeal(positionId, openTime, openPrice, direction);

      int durationMinutes = 0;

      if(openTime > 0)
         durationMinutes = (int)((closeTime - openTime) / 60);

      string result = "BE";

      if(profit > 0)
         result = "WIN";
      else if(profit < 0)
         result = "LOSS";

      double rsiM5 = GetRSIValue(PERIOD_M5, 14, 1);
      double atrM5 = GetATRValue(PERIOD_M5, AtrStopPeriod, 1);
      double atrM5Change = GetSafeAtrChange();
      double ema20M15 = GetEMAValue(PERIOD_M15, 20, 1);
      double ema50M15 = GetEMAValue(PERIOD_M15, 50, 1);
      double emaDistance = ema20M15 - ema50M15;

      int fileHandle = OpenCsvFile(TRADES_JOURNAL_FILE);

      if(fileHandle == INVALID_HANDLE)
      {
         Print("Erreur ouverture Trades CSV: ", GetLastError());
         return;
      }

      FileSeek(fileHandle, 0, SEEK_END);

      FileWrite(
         fileHandle,
         TimeToString(closeTime, TIME_DATE | TIME_MINUTES),
         symbol,
         IntegerToString(positionId),
         IntegerToString(dealTicket),
         direction,
         openTime > 0 ? TimeToString(openTime, TIME_DATE | TIME_MINUTES) : "",
         IntegerToString(durationMinutes),
         DoubleToString(volume, 2),
         openPrice > 0 ? DoubleToString(openPrice, _Digits) : "",
         DoubleToString(price, _Digits),
         DoubleToString(profit, 2),
         result,
         DoubleToString(rsiM5, 2),
         DoubleToString(atrM5, _Digits),
         DoubleToString(atrM5Change, _Digits),
         DoubleToString(ema20M15, _Digits),
         DoubleToString(ema50M15, _Digits),
         DoubleToString(emaDistance, _Digits),
         GetM15TrendLabel(ema20M15, ema50M15)
      );

      FileClose(fileHandle);

      if(dealTicket > newestLoggedTicket)
         newestLoggedTicket = dealTicket;
   }

   lastLoggedDealTicket = newestLoggedTicket;
}

string GetTradeStatus()
{
   if(HasOpenTrade(MagicNumber))
      return "POSITION OUVERTE";

   if(HasPendingOrder(MagicNumber))
      return "ORDRE PENDING";

   return "AUCUN ORDRE";
}

double GetPendingOrderDistance()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);

      if(OrderSelect(ticket))
      {
         if(OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetString(ORDER_SYMBOL) == _Symbol)
         {
            long type = OrderGetInteger(ORDER_TYPE);
            double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);

            if(type == ORDER_TYPE_BUY_LIMIT)
               return MathAbs(ask - orderPrice);

            if(type == ORDER_TYPE_SELL_LIMIT)
               return MathAbs(bid - orderPrice);
         }
      }
   }

   return 0.0;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   ManageBreakEven(MagicNumber);
   LogClosedTradesToCSV();

   SignalResult signal = AnalyzeMarket(
      BreakoutLookback,
      StopBuffer,
      BreakoutConfirmPoints,
      BuyRsiMin,
      BuyRsiMax,
      SellRsiMin,
      SellRsiMax,
      AllowBuySignals,
      AllowSellSignals,
      UseAtrStopCap,
      AtrStopPeriod,
      AtrStopMultiplier,
      MaxStopDistancePoints,
      UsePullbackEntry,
      PullbackCandles,
      PullbackWindowBars,
      PullbackBreakoutConfirmPoints,
      UseH4ZoneRetest,
      H4UsePreviousDayRange,
      H4ZoneFirstBars,
      H4RetestWindowBars,
      H4RetestTolerancePoints,
      H4BreakoutMinPoints,
      H4BreakoutBodyPct,
      H4RequireM15Trend,
      H4SLBufferPoints
   );

   double lot = 0.0;
   double finalTP = 0.0;
   double spread = GetSpreadPoints();
   bool canTrade = CanTradeNow();
   bool confidenceOK = signal.confidence >= MinConfidence;
   string setupQuality = GetSetupQuality(signal.confidence);
   string blockReason = GetTradeBlockReason(signal, canTrade, confidenceOK);
   
   if(signal.action != SIGNAL_WAIT)
   {
      lot = CalculateLotSize(signal.entry, signal.sl, RiskPercent);

      if(lot > MaxLot)
         lot = MaxLot;

      finalTP = CalculateFinalTP(signal);

      if(AutoTrade && canTrade && confidenceOK)
      {
         if(OpenSignalTrade(signal, lot, MagicNumber, FinalTPMultiplier))
         {
            lastTradeTime = TimeCurrent();
         }
      }
   }
   
   lastSignal = signal;
   lastLot = lot;
   lastFinalTP = finalTP;

   bool inSession = IsTradingSession();
   bool inNoTradeWindow = IsNoTradeWindow();
   bool inBlockedHour08 = IsBlockedHour08();
   bool inAllowedEntryHour = IsAllowedEntryHour();
   int dailyClosedTrades = 0;
   int dailyConsecutiveLosses = 0;
   double dailyProfit = 0.0;
   GetDailyClosedTradeStats(dailyClosedTrades, dailyProfit, dailyConsecutiveLosses);
   double pendingDistance = GetPendingOrderDistance();

   LogSignalContextToCSV(
      signal,
      finalTP,
      lot,
      spread,
      setupQuality,
      canTrade,
      blockReason,
      dailyClosedTrades,
      dailyProfit,
      dailyConsecutiveLosses,
      inSession,
      inNoTradeWindow
   );

   string text = "";

   text += "GoldSignalEA V1\n";
   text += "Action: " + SignalActionToString(signal.action) + "\n";
   text += "Setup: " + setupQuality + "\n";
   text += "Entry: " + DoubleToString(signal.entry, _Digits) + "\n";
   text += "SL: " + DoubleToString(signal.sl, _Digits) + "\n";
   text += "TP1: " + DoubleToString(signal.tp1, _Digits) + "\n";
   text += "TP Final: " + DoubleToString(finalTP, _Digits) + "\n";
   text += "Lot: " + DoubleToString(lot, 2) + "\n";
   text += "Spread: " + DoubleToString(spread, 1) + "\n";
   text += "Can Trade: " + (canTrade ? "OUI" : "NON") + "\n";
   text += "AutoTrade: " + (AutoTrade ? "ON" : "OFF") + "\n";
   text += "Trade actif: " + (HasActiveTradeOrOrder(MagicNumber) ? "OUI" : "NON") + "\n";
   text += "Status: " + GetTradeStatus() + "\n";
   text += "Pending Distance: " + DoubleToString(pendingDistance, _Digits) + "\n";
   text += "Confiance: " + DoubleToString(signal.confidence, 1) + "%\n";
   text += "Confidence OK: " + (confidenceOK ? "OUI" : "NON") + "\n";
   text += "Raison: " + signal.reason + "\n";
   text += "Session OK: " + (inSession ? "OUI" : "NON") + "\n";
   text += "Block 08h: " + (inBlockedHour08 ? "OUI" : "NON") + "\n";
   text += "Heure OK: " + (inAllowedEntryHour ? "OUI" : "NON") + "\n";
   text += "NoTrade: " + (inNoTradeWindow ? "OUI" : "NON") + "\n";
   text += "Trades jour: " + IntegerToString(dailyClosedTrades) + "/" + IntegerToString(MaxTradesPerDay) + "\n";
   text += "PnL jour: " + DoubleToString(dailyProfit, 2) + "\n";
   text += "ProfitLock: " + (DailyProfitLockMoney > 0 && dailyProfit >= DailyProfitLockMoney ? "OUI" : "NON") + "\n";
   text += "Loss suite: " + IntegerToString(dailyConsecutiveLosses) + "/" + IntegerToString(MaxConsecutiveLosses) + "\n";
   text += "Block: " + blockReason + "\n";

   Comment(text);
}

void OnChartEvent(
   const int id,
   const long &lparam,
   const double &dparam,
   const string &sparam
)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam != "BTN_ACCEPT_SIGNAL")
      return;

   if(lastSignal.action == SIGNAL_WAIT)
   {
      Print("Aucun signal valide à accepter.");
      return;
   }

   if(!CanTradeNow())
   {
      Print("Trade refusé : filtres non validés.");
      return;
   }

   if(lastSignal.confidence < MinConfidence)
   {
      Print("Trade refusé : confiance insuffisante.");
      return;
   }

   if(HasActiveTradeOrOrder(MagicNumber))
   {
      Print("Trade refusé : trade ou ordre déjà actif.");
      return;
   }

   if(OpenSignalTrade(lastSignal, lastLot, MagicNumber, FinalTPMultiplier))
   {
      lastTradeTime = TimeCurrent();
      Print("Signal accepté manuellement et trade ouvert.");
   }
   else
   {
      Print("Erreur ouverture manuelle du trade.");
   }
}

string GetSetupQuality(double confidence)
{
   if(confidence >= 85)
      return "SNIPER";

   if(confidence >= 75)
      return "FORT";

   if(confidence >= 65)
      return "MODERE";

   return "FAIBLE";
}
//+------------------------------------------------------------------+

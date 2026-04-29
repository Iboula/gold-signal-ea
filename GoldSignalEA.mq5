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
input bool UseSessionFilter = false;
input int LondonStartHour = 8;
input int NewYorkEndHour = 17;
input double MinConfidence = 80.0;
input bool UseManualButton = false;

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

   ObjectSetInteger(0, buttonName, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, buttonName, OBJPROP_YDISTANCE, 180);
   ObjectSetInteger(0, buttonName, OBJPROP_XSIZE, 120);
   ObjectSetInteger(0, buttonName, OBJPROP_YSIZE, 24);
   ObjectSetString(0, buttonName, OBJPROP_TEXT, "ACCEPTER");
   ObjectSetInteger(0, buttonName, OBJPROP_FONTSIZE, 8);
   
   ObjectSetInteger(0, buttonName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
ObjectSetInteger(0, buttonName, OBJPROP_XDISTANCE, 20);
ObjectSetInteger(0, buttonName, OBJPROP_YDISTANCE, 20);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   if(!InitIndicators())
      return(INIT_FAILED);
   CreateAcceptButton();
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ReleaseIndicators();
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
   double spread = GetSpreadPoints();

   if(spread > MaxSpread)
      return false;

   if((TimeCurrent() - lastTradeTime) < (CooldownMinutes * 60))
      return false;

   if(!IsTradingSession())
   return false;

   return true;
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

datetime lastLoggedCandleTime = 0;

void LogSignalToCSV(const SignalResult &signal, double finalTP, double lot, double spread, string setupQuality)
{
   datetime candleTime = iTime(_Symbol, PERIOD_M5, 1);

   string signalKey =
      TimeToString(candleTime, TIME_DATE | TIME_MINUTES) + "_" +
      SignalActionToString(signal.action) + "_" +
      DoubleToString(signal.entry, _Digits);
   
   if(signalKey == lastLoggedSignalKey)
      return;

   if(signal.action == SIGNAL_WAIT)
      return;

   lastLoggedSignalTime = candleTime;
   lastLoggedSignalKey = signalKey;

   int fileHandle = FileOpen(
      "GoldSignalEA_Journal.csv",
      FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON,
      ';'
   );

   if(fileHandle == INVALID_HANDLE)
      return;

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
         "Reason"
      );
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
      signal.reason
   );

   FileClose(fileHandle);
}

SignalResult lastSignal;
double lastLot = 0.0;
double lastFinalTP = 0.0;

string GetTradeBlockReason(const SignalResult &signal, bool canTrade, bool confidenceOK)
{
   if(signal.action == SIGNAL_WAIT)
      return "WAIT - aucun setup";

   if(HasOpenTrade(MagicNumber))
      return "Trade deja actif";

   if(!confidenceOK)
      return "Confiance insuffisante";

   if(!canTrade)
      return "Filtre bloque: spread/session/cooldown";

   if(!AutoTrade)
      return "AutoTrade OFF";

   return "Pret a trader";
}

datetime lastLoggedSignalTime = 0;
string lastLoggedSignalKey = "";
ulong lastLoggedDealTicket = 0;

void LogClosedTradesToCSV()
{
   HistorySelect(0, TimeCurrent());

   int totalDeals = HistoryDealsTotal();

   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong dealTicket = HistoryDealGetTicket(i);

      if(dealTicket <= lastLoggedDealTicket)
         return;

      string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);

      if(symbol != _Symbol)
         continue;

      long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);

      if(magic != MagicNumber)
         continue;

      long entryType = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

      if(entryType != DEAL_ENTRY_OUT)
         continue;

      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      double price = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      double volume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
      datetime closeTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);

      string result = "BE";

      if(profit > 0)
         result = "WIN";
      else if(profit < 0)
         result = "LOSS";

      int fileHandle = FileOpen(
         "GoldSignalEA_Trades.csv",
         FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON,
         ';'
      );

      if(fileHandle == INVALID_HANDLE)
      {
         Print("Erreur ouverture Trades CSV: ", GetLastError());
         return;
      }

      if(FileSize(fileHandle) == 0)
      {
         FileWrite(
            fileHandle,
            "Date",
            "Symbol",
            "DealTicket",
            "Volume",
            "ClosePrice",
            "Profit",
            "Result"
         );
      }

      FileSeek(fileHandle, 0, SEEK_END);

      FileWrite(
         fileHandle,
         TimeToString(closeTime, TIME_DATE | TIME_MINUTES),
         symbol,
         IntegerToString(dealTicket),
         DoubleToString(volume, 2),
         DoubleToString(price, _Digits),
         DoubleToString(profit, 2),
         result
      );

      FileClose(fileHandle);

      lastLoggedDealTicket = dealTicket;
   }
}

string GetTradeStatus()
{
   if(HasOpenTrade(MagicNumber))
      return "POSITION OUVERTE";

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);

      if(OrderSelect(ticket))
      {
         if(OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetString(ORDER_SYMBOL) == _Symbol)
         {
            return "ORDRE PENDING";
         }
      }
   }

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

   SignalResult signal = AnalyzeMarket();

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

   LogSignalToCSV(signal, finalTP, lot, spread, setupQuality);
   
   bool inSession = IsTradingSession();
   double pendingDistance = GetPendingOrderDistance();

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
   text += "Trade actif: " + (HasOpenTrade(MagicNumber) ? "OUI" : "NON") + "\n";
   text += "Status: " + GetTradeStatus() + "\n";
   text += "Pending Distance: " + DoubleToString(pendingDistance, _Digits) + "\n";
   text += "Confiance: " + DoubleToString(signal.confidence, 1) + "%\n";
   text += "Confidence OK: " + (confidenceOK ? "OUI" : "NON") + "\n";
   text += "Raison: " + signal.reason + "\n";
   text += "Session OK: " + (inSession ? "OUI" : "NON") + "\n";
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

   if(HasOpenTrade(MagicNumber))
   {
      Print("Trade refusé : trade déjà actif.");
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

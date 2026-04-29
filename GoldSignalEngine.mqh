#ifndef GOLD_SIGNAL_ENGINE_MQH
#define GOLD_SIGNAL_ENGINE_MQH

enum SignalAction
{
   SIGNAL_WAIT,
   SIGNAL_BUY,
   SIGNAL_SELL,
   SIGNAL_BUY_LIMIT,
   SIGNAL_SELL_LIMIT
};

struct SignalResult
{
   SignalAction action;
   double entry;
   double sl;
   double tp1;
   double confidence;
   string reason;
};

// --- Handles globaux (crees une seule fois dans OnInit) ---
int g_hEMA20_M15 = INVALID_HANDLE;
int g_hEMA50_M15 = INVALID_HANDLE;
int g_hRSI_M5    = INVALID_HANDLE;
int g_hBB_M5     = INVALID_HANDLE;
int g_hMACD_M5   = INVALID_HANDLE;
int g_hATR_M5    = INVALID_HANDLE;

bool InitIndicators()
{
   g_hEMA20_M15 = iMA(_Symbol, PERIOD_M15, 20,  0, MODE_EMA, PRICE_CLOSE);
   g_hEMA50_M15 = iMA(_Symbol, PERIOD_M15, 50,  0, MODE_EMA, PRICE_CLOSE);
   g_hRSI_M5    = iRSI(_Symbol, PERIOD_M5, 14, PRICE_CLOSE);
   g_hBB_M5     = iBands(_Symbol, PERIOD_M5, 20, 0, 2.0, PRICE_CLOSE);
   g_hMACD_M5   = iMACD(_Symbol, PERIOD_M5, 12, 26, 9, PRICE_CLOSE);
   g_hATR_M5    = iATR(_Symbol, PERIOD_M5, 14);

   if(g_hEMA20_M15 == INVALID_HANDLE || g_hEMA50_M15 == INVALID_HANDLE ||
      g_hRSI_M5    == INVALID_HANDLE || g_hBB_M5     == INVALID_HANDLE ||
      g_hMACD_M5   == INVALID_HANDLE || g_hATR_M5    == INVALID_HANDLE)
   {
      Print("Erreur initialisation indicateurs: ", GetLastError());
      return false;
   }
   return true;
}

void ReleaseIndicators()
{
   if(g_hEMA20_M15 != INVALID_HANDLE){ IndicatorRelease(g_hEMA20_M15); g_hEMA20_M15 = INVALID_HANDLE; }
   if(g_hEMA50_M15 != INVALID_HANDLE){ IndicatorRelease(g_hEMA50_M15); g_hEMA50_M15 = INVALID_HANDLE; }
   if(g_hRSI_M5    != INVALID_HANDLE){ IndicatorRelease(g_hRSI_M5);    g_hRSI_M5    = INVALID_HANDLE; }
   if(g_hBB_M5     != INVALID_HANDLE){ IndicatorRelease(g_hBB_M5);     g_hBB_M5     = INVALID_HANDLE; }
   if(g_hMACD_M5   != INVALID_HANDLE){ IndicatorRelease(g_hMACD_M5);   g_hMACD_M5   = INVALID_HANDLE; }
   if(g_hATR_M5    != INVALID_HANDLE){ IndicatorRelease(g_hATR_M5);    g_hATR_M5    = INVALID_HANDLE; }
}

double GetIndValue(int handle, int bufferIdx, int shift)
{
   if(handle == INVALID_HANDLE) return 0.0;
   double buf[];
   if(CopyBuffer(handle, bufferIdx, shift, 1, buf) <= 0) return 0.0;
   return buf[0];
}

double GetRSI(int shift = 1)      { return GetIndValue(g_hRSI_M5,  0, shift); }
double GetBBUpper(int shift = 1)  { return GetIndValue(g_hBB_M5,   1, shift); }
double GetBBLower(int shift = 1)  { return GetIndValue(g_hBB_M5,   2, shift); }
double GetBBMiddle(int shift = 1) { return GetIndValue(g_hBB_M5,   0, shift); }
double GetMACDMain(int shift = 1) { return GetIndValue(g_hMACD_M5, 0, shift); }
double GetATR(int shift = 1)      { return GetIndValue(g_hATR_M5,  0, shift); }

bool IsM15BullishTrend()
{
   double ema20 = GetIndValue(g_hEMA20_M15, 0, 1);
   double ema50 = GetIndValue(g_hEMA50_M15, 0, 1);
   return ema20 > 0 && ema50 > 0 && ema20 > ema50;
}

bool IsM15BearishTrend()
{
   double ema20 = GetIndValue(g_hEMA20_M15, 0, 1);
   double ema50 = GetIndValue(g_hEMA50_M15, 0, 1);
   return ema20 > 0 && ema50 > 0 && ema20 < ema50;
}

double GetRecentHigh(int candles)
{
   double high = iHigh(_Symbol, PERIOD_M5, 1);
   for(int i = 2; i <= candles; i++)
   {
      double h = iHigh(_Symbol, PERIOD_M5, i);
      if(h > high) high = h;
   }
   return high;
}

double GetRecentLow(int candles)
{
   double low = iLow(_Symbol, PERIOD_M5, 1);
   for(int i = 2; i <= candles; i++)
   {
      double l = iLow(_Symbol, PERIOD_M5, i);
      if(l < low) low = l;
   }
   return low;
}

bool IsStrongBullishCandle()
{
   double open  = iOpen(_Symbol,  PERIOD_M5, 1);
   double close = iClose(_Symbol, PERIOD_M5, 1);
   double high  = iHigh(_Symbol,  PERIOD_M5, 1);
   double low   = iLow(_Symbol,   PERIOD_M5, 1);
   double body  = MathAbs(close - open);
   double range = high - low;
   if(range <= 0) return false;
   return close > open && body >= range * 0.60;
}

bool IsStrongBearishCandle()
{
   double open  = iOpen(_Symbol,  PERIOD_M5, 1);
   double close = iClose(_Symbol, PERIOD_M5, 1);
   double high  = iHigh(_Symbol,  PERIOD_M5, 1);
   double low   = iLow(_Symbol,   PERIOD_M5, 1);
   double body  = MathAbs(close - open);
   double range = high - low;
   if(range <= 0) return false;
   return close < open && body >= range * 0.60;
}

// -----------------------------------------------------------------------
// AnalyzeMarket : 4 setups avec score de confiance dynamique
//
// Setup 1 & 2 : Mean-Reversion BB+RSI (inspire de BBRSI, valide XAUUSD-5M)
//   RSI croise 30/70 ET prix repasse le BB lower/upper -> rebond sur extreme
// Setup 3 & 4 : Cassure de range (amelioree)
//   Cassure H/L 20 bougies + bougie forte + filtre MACD + RSI
// SL dynamique : 0.5*ATR au lieu du buffer fixe 1.0 (inadapte a l'or)
// Confiance    : calculee dynamiquement selon confirmations actives
// -----------------------------------------------------------------------
SignalResult AnalyzeMarket()
{
   SignalResult signal;
   signal.action     = SIGNAL_WAIT;
   signal.entry      = 0;
   signal.sl         = 0;
   signal.tp1        = 0;
   signal.confidence = 0;
   signal.reason     = "Pas de setup clair";

   double close  = iClose(_Symbol, PERIOD_M5, 1);
   double close2 = iClose(_Symbol, PERIOD_M5, 2);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double rsi1  = GetRSI(1);
   double rsi2  = GetRSI(2);
   double bbUp1 = GetBBUpper(1);
   double bbUp2 = GetBBUpper(2);
   double bbLo1 = GetBBLower(1);
   double bbLo2 = GetBBLower(2);
   double macd1 = GetMACDMain(1);
   double atr   = GetATR(1);

   if(atr <= 0) atr = 50.0 * _Point;
   double atrBuffer = atr * 0.5;

   bool bullTrend = IsM15BullishTrend();
   bool bearTrend = IsM15BearishTrend();

   // SETUP 1 : Mean Reversion Buy (BB+RSI)
   // RSI croise 30 a la hausse ET prix repasse au-dessus du BB lower
   if(rsi2 < 30.0 && close2 < bbLo2 && rsi1 > 30.0 && close > bbLo1)
   {
      double conf = 70.0;
      string reasons = "BB+RSI oversold bounce";
      if(bullTrend)               { conf += 10.0; reasons += " | EMA M15 haussier"; }
      if(macd1 > 0)               { conf += 5.0;  reasons += " | MACD>0"; }
      if(IsStrongBullishCandle()) { conf += 5.0;  reasons += " | bougie forte"; }

      signal.action     = SIGNAL_BUY;
      signal.entry      = ask;
      signal.sl         = bbLo1 - atrBuffer;
      signal.tp1        = ask + MathAbs(ask - signal.sl) * 1.5;
      signal.confidence = MathMin(conf, 95.0);
      signal.reason     = reasons;
      return signal;
   }

   // SETUP 2 : Mean Reversion Sell (BB+RSI)
   // RSI croise 70 a la baisse ET prix repasse sous le BB upper
   if(rsi2 > 70.0 && close2 > bbUp2 && rsi1 < 70.0 && close < bbUp1)
   {
      double conf = 70.0;
      string reasons = "BB+RSI overbought rejection";
      if(bearTrend)               { conf += 10.0; reasons += " | EMA M15 baissier"; }
      if(macd1 < 0)               { conf += 5.0;  reasons += " | MACD<0"; }
      if(IsStrongBearishCandle()) { conf += 5.0;  reasons += " | bougie forte"; }

      signal.action     = SIGNAL_SELL;
      signal.entry      = bid;
      signal.sl         = bbUp1 + atrBuffer;
      signal.tp1        = bid - MathAbs(signal.sl - bid) * 1.5;
      signal.confidence = MathMin(conf, 95.0);
      signal.reason     = reasons;
      return signal;
   }

   // SETUP 3 : Cassure haussiere (SL base sur ATR)
   double recentHigh = GetRecentHigh(20);
   double recentLow  = GetRecentLow(20);

   if(close > recentHigh && IsStrongBullishCandle() && bullTrend)
   {
      double conf = 65.0;
      string reasons = "Cassure haussiere M5";
      if(macd1 > 0)                   { conf += 10.0; reasons += " | MACD>0"; }
      if(rsi1 > 50.0 && rsi1 < 70.0) { conf += 5.0;  reasons += " | RSI neutre-haussier"; }
      if(rsi1 < 30.0)                   conf -= 10.0;

      signal.action     = SIGNAL_BUY;
      signal.entry      = ask;
      signal.sl         = recentHigh - atrBuffer;
      signal.tp1        = ask + MathAbs(ask - signal.sl) * 1.5;
      signal.confidence = MathMin(MathMax(conf, 0.0), 95.0);
      signal.reason     = reasons;
      return signal;
   }

   // SETUP 4 : Cassure baissiere (SL base sur ATR)
   if(close < recentLow && IsStrongBearishCandle() && bearTrend)
   {
      double conf = 65.0;
      string reasons = "Cassure baissiere M5";
      if(macd1 < 0)                   { conf += 10.0; reasons += " | MACD<0"; }
      if(rsi1 < 50.0 && rsi1 > 30.0) { conf += 5.0;  reasons += " | RSI neutre-baissier"; }
      if(rsi1 > 70.0)                   conf -= 10.0;

      signal.action     = SIGNAL_SELL;
      signal.entry      = bid;
      signal.sl         = recentLow + atrBuffer;
      signal.tp1        = bid - MathAbs(signal.sl - bid) * 1.5;
      signal.confidence = MathMin(MathMax(conf, 0.0), 95.0);
      signal.reason     = reasons;
      return signal;
   }

   return signal;
}

string SignalActionToString(SignalAction action)
{
   if(action == SIGNAL_BUY)        return "BUY";
   if(action == SIGNAL_SELL)       return "SELL";
   if(action == SIGNAL_BUY_LIMIT)  return "BUY LIMIT";
   if(action == SIGNAL_SELL_LIMIT) return "SELL LIMIT";
   return "WAIT";
}

#endif
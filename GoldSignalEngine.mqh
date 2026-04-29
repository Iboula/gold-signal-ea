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

double GetRecentHigh(int candles)
{
   double high = iHigh(_Symbol, PERIOD_M5, 1);

   for(int i = 2; i <= candles; i++)
   {
      double h = iHigh(_Symbol, PERIOD_M5, i);
      if(h > high)
         high = h;
   }

   return high;
}

double GetRecentLow(int candles)
{
   double low = iLow(_Symbol, PERIOD_M5, 1);

   for(int i = 2; i <= candles; i++)
   {
      double l = iLow(_Symbol, PERIOD_M5, i);
      if(l < low)
         low = l;
   }

   return low;
}

bool IsStrongBullishCandle()
{
   double open = iOpen(_Symbol, PERIOD_M5, 1);
   double close = iClose(_Symbol, PERIOD_M5, 1);
   double high = iHigh(_Symbol, PERIOD_M5, 1);
   double low = iLow(_Symbol, PERIOD_M5, 1);

   double body = MathAbs(close - open);
   double range = high - low;

   if(range <= 0)
      return false;

   return close > open && body >= range * 0.60;
}

bool IsStrongBearishCandle()
{
   double open = iOpen(_Symbol, PERIOD_M5, 1);
   double close = iClose(_Symbol, PERIOD_M5, 1);
   double high = iHigh(_Symbol, PERIOD_M5, 1);
   double low = iLow(_Symbol, PERIOD_M5, 1);

   double body = MathAbs(close - open);
   double range = high - low;

   if(range <= 0)
      return false;

   return close < open && body >= range * 0.60;
}

bool IsRejectionFromResistance(double resistance)
{
   double open = iOpen(_Symbol, PERIOD_M5, 1);
   double close = iClose(_Symbol, PERIOD_M5, 1);
   double high = iHigh(_Symbol, PERIOD_M5, 1);
   double low = iLow(_Symbol, PERIOD_M5, 1);

   double upperWick = high - MathMax(open, close);
   double range = high - low;

   if(range <= 0)
      return false;

   return high >= resistance && close < resistance && upperWick >= range * 0.40;
}

bool IsRejectionFromSupport(double support)
{
   double open = iOpen(_Symbol, PERIOD_M5, 1);
   double close = iClose(_Symbol, PERIOD_M5, 1);
   double high = iHigh(_Symbol, PERIOD_M5, 1);
   double low = iLow(_Symbol, PERIOD_M5, 1);

   double lowerWick = MathMin(open, close) - low;
   double range = high - low;

   if(range <= 0)
      return false;

   return low <= support && close > support && lowerWick >= range * 0.40;
}

bool IsBullishClose()
{
   double open = iOpen(_Symbol, PERIOD_M5, 1);
   double close = iClose(_Symbol, PERIOD_M5, 1);

   return close > open;
}

bool IsBearishClose()
{
   double open = iOpen(_Symbol, PERIOD_M5, 1);
   double close = iClose(_Symbol, PERIOD_M5, 1);

   return close < open;
}

double GetEMAValue(ENUM_TIMEFRAMES timeframe, int period, int shift)
{
   int handle = iMA(_Symbol, timeframe, period, 0, MODE_EMA, PRICE_CLOSE);

   if(handle == INVALID_HANDLE)
      return 0.0;

   double buffer[];

   if(CopyBuffer(handle, 0, shift, 1, buffer) <= 0)
   {
      IndicatorRelease(handle);
      return 0.0;
   }

   IndicatorRelease(handle);

   return buffer[0];
}

bool IsM15BullishTrend()
{
   double ema20 = GetEMAValue(PERIOD_M15, 20, 1);
   double ema50 = GetEMAValue(PERIOD_M15, 50, 1);

   if(ema20 <= 0 || ema50 <= 0)
      return false;

   return ema20 > ema50;
}

bool IsM15BearishTrend()
{
   double ema20 = GetEMAValue(PERIOD_M15, 20, 1);
   double ema50 = GetEMAValue(PERIOD_M15, 50, 1);

   if(ema20 <= 0 || ema50 <= 0)
      return false;

   return ema20 < ema50;
}

double GetRSIValue(ENUM_TIMEFRAMES timeframe, int period, int shift)
{
   int handle = iRSI(_Symbol, timeframe, period, PRICE_CLOSE);

   if(handle == INVALID_HANDLE)
      return 50.0;

   double buffer[];

   if(CopyBuffer(handle, 0, shift, 1, buffer) <= 0)
   {
      IndicatorRelease(handle);
      return 50.0;
   }

   IndicatorRelease(handle);

   return buffer[0];
}

SignalResult AnalyzeMarket()
{
   SignalResult signal;

   signal.action = SIGNAL_WAIT;
   signal.entry = 0;
   signal.sl = 0;
   signal.tp1 = 0;
   signal.confidence = 0;
   signal.reason = "Pas de setup clair";

   double recentHigh = GetRecentHigh(20);
   double recentLow = GetRecentLow(20);

   double close = iClose(_Symbol, PERIOD_M5, 1);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double buffer = 1.0;

   if(close > recentHigh && IsStrongBullishCandle() && IsM15BullishTrend())
   {
      signal.action = SIGNAL_BUY;
      signal.entry = ask;
      signal.sl = recentHigh - buffer;
      signal.tp1 = ask + ((ask - signal.sl) * 1.5);
      signal.confidence = 80;
      signal.reason = "Cassure haussiere M5 avec bougie forte";
      return signal;
   }

   if(close < recentLow && IsStrongBearishCandle() && IsM15BearishTrend())
   {
      signal.action = SIGNAL_SELL;
      signal.entry = bid;
      signal.sl = recentLow + buffer;
      signal.tp1 = bid - ((signal.sl - bid) * 1.5);
      signal.confidence = 80;
      signal.reason = "Cassure baissiere M5 avec bougie forte";
      return signal;
   }

   return signal;
}

string SignalActionToString(SignalAction action)
{
   if(action == SIGNAL_BUY)
      return "BUY";

   if(action == SIGNAL_SELL)
      return "SELL";

   if(action == SIGNAL_BUY_LIMIT)
      return "BUY LIMIT";

   if(action == SIGNAL_SELL_LIMIT)
      return "SELL LIMIT";

   return "WAIT";
}

#endif
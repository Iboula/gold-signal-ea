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

double GetRecentHigh(int candles, int startShift)
{
   if(candles <= 0 || startShift < 1)
      return 0.0;

   double high = iHigh(_Symbol, PERIOD_M5, startShift);

   for(int i = startShift + 1; i < startShift + candles; i++)
   {
      double h = iHigh(_Symbol, PERIOD_M5, i);
      if(h > high)
         high = h;
   }

   return high;
}

double GetRecentLow(int candles, int startShift)
{
   if(candles <= 0 || startShift < 1)
      return 0.0;

   double low = iLow(_Symbol, PERIOD_M5, startShift);

   for(int i = startShift + 1; i < startShift + candles; i++)
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

double GetATRValue(ENUM_TIMEFRAMES timeframe, int period, int shift)
{
   int handle = iATR(_Symbol, timeframe, period);

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

double GetCappedStopDistance(double structuralDistance, double atrValue, double atrMultiplier, double maxStopPoints)
{
   double stopDistance = structuralDistance;

   if(atrValue > 0 && atrMultiplier > 0)
      stopDistance = MathMin(stopDistance, atrValue * atrMultiplier);

   if(maxStopPoints > 0)
      stopDistance = MathMin(stopDistance, maxStopPoints * _Point);

   return MathMax(stopDistance, _Point);
}

SignalResult EmptySignal(string reason)
{
   SignalResult signal;

   signal.action = SIGNAL_WAIT;
   signal.entry = 0;
   signal.sl = 0;
   signal.tp1 = 0;
   signal.confidence = 0;
   signal.reason = reason;

   return signal;
}

SignalResult BuildBuySignal(
   double entry,
   double structuralSL,
   double atr,
   bool useAtrStopCap,
   double atrStopMultiplier,
   double maxStopDistancePoints,
   string reason
)
{
   SignalResult signal;

   signal.action = SIGNAL_BUY;
   signal.entry = entry;

   double stopDistance = MathAbs(signal.entry - structuralSL);

   if(useAtrStopCap)
      stopDistance = GetCappedStopDistance(stopDistance, atr, atrStopMultiplier, maxStopDistancePoints);

   signal.sl = signal.entry - stopDistance;
   signal.tp1 = signal.entry + ((signal.entry - signal.sl) * 1.5);
   signal.confidence = 80;
   signal.reason = reason;

   return signal;
}

SignalResult BuildSellSignal(
   double entry,
   double structuralSL,
   double atr,
   bool useAtrStopCap,
   double atrStopMultiplier,
   double maxStopDistancePoints,
   string reason
)
{
   SignalResult signal;

   signal.action = SIGNAL_SELL;
   signal.entry = entry;

   double stopDistance = MathAbs(structuralSL - signal.entry);

   if(useAtrStopCap)
      stopDistance = GetCappedStopDistance(stopDistance, atr, atrStopMultiplier, maxStopDistancePoints);

   signal.sl = signal.entry + stopDistance;
   signal.tp1 = signal.entry - ((signal.sl - signal.entry) * 1.5);
   signal.confidence = 80;
   signal.reason = reason;

   return signal;
}

SignalResult AnalyzeImmediateMarket(
   int breakoutLookback,
   double stopBuffer,
   double breakoutConfirmPoints,
   double buyRsiMin,
   double buyRsiMax,
   double sellRsiMin,
   double sellRsiMax,
   bool allowBuySignals,
   bool allowSellSignals,
   bool useAtrStopCap,
   int atrStopPeriod,
   double atrStopMultiplier,
   double maxStopDistancePoints
)
{
   SignalResult signal = EmptySignal("Pas de setup clair");

   int lookback = breakoutLookback < 2 ? 2 : breakoutLookback;
   double buffer = MathMax(_Point, stopBuffer);
   double confirmDistance = MathMax(0.0, breakoutConfirmPoints) * _Point;

   double recentHigh = GetRecentHigh(lookback, 2);
   double recentLow = GetRecentLow(lookback, 2);
   double rsi = GetRSIValue(PERIOD_M5, 14, 1);
   double atr = useAtrStopCap ? GetATRValue(PERIOD_M5, atrStopPeriod, 1) : 0.0;

   double close = iClose(_Symbol, PERIOD_M5, 1);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(allowBuySignals &&
      recentHigh > 0 &&
      close > recentHigh + confirmDistance &&
      IsStrongBullishCandle() &&
      IsM15BullishTrend() &&
      rsi >= buyRsiMin &&
      rsi <= buyRsiMax)
   {
      double structuralSL = recentHigh - buffer;

      return BuildBuySignal(
         ask,
         structuralSL,
         atr,
         useAtrStopCap,
         atrStopMultiplier,
         maxStopDistancePoints,
         "Cassure haussiere M5 confirmee avec RSI et stop dynamique"
      );
   }

   if(allowSellSignals &&
      recentLow > 0 &&
      close < recentLow - confirmDistance &&
      IsStrongBearishCandle() &&
      IsM15BearishTrend() &&
      rsi >= sellRsiMin &&
      rsi <= sellRsiMax)
   {
      double structuralSL = recentLow + buffer;

      return BuildSellSignal(
         bid,
         structuralSL,
         atr,
         useAtrStopCap,
         atrStopMultiplier,
         maxStopDistancePoints,
         "Cassure baissiere M5 confirmee avec RSI et stop dynamique"
      );
   }

   return signal;
}

enum PullbackEntryState
{
   PULLBACK_IDLE,
   PULLBACK_ARMED_BUY,
   PULLBACK_ARMED_SELL,
   PULLBACK_WINDOW_BUY,
   PULLBACK_WINDOW_SELL
};

PullbackEntryState g_pullbackState = PULLBACK_IDLE;
datetime g_pullbackLastClosedCandle = 0;
double g_pullbackBreakoutLevel = 0.0;
int g_pullbackCounter = 0;
int g_pullbackWindowCounter = 0;
int g_pullbackBarsSinceArmed = 0;

bool g_h4ZoneWaitingRetest = false;
int g_h4ZoneBreakoutDir = 0;
datetime g_h4ZoneDayStart = 0;
datetime g_h4ZoneBreakoutTime = 0;
datetime g_h4ZoneLastClosedCandle = 0;
double g_h4ZoneHigh = 0.0;
double g_h4ZoneLow = 0.0;
int g_h4ZoneWaitBars = 0;

void ResetPullbackEntry()
{
   g_pullbackState = PULLBACK_IDLE;
   g_pullbackBreakoutLevel = 0.0;
   g_pullbackCounter = 0;
   g_pullbackWindowCounter = 0;
   g_pullbackBarsSinceArmed = 0;
}

string PullbackStateLabel()
{
   if(g_pullbackState == PULLBACK_ARMED_BUY)
      return "pullback BUY arme";

   if(g_pullbackState == PULLBACK_ARMED_SELL)
      return "pullback SELL arme";

   if(g_pullbackState == PULLBACK_WINDOW_BUY)
      return "fenetre BUY ouverte";

   if(g_pullbackState == PULLBACK_WINDOW_SELL)
      return "fenetre SELL ouverte";

   return "pullback idle";
}

void ResetH4ZoneRetest()
{
   g_h4ZoneWaitingRetest = false;
   g_h4ZoneBreakoutDir = 0;
   g_h4ZoneBreakoutTime = 0;
   g_h4ZoneWaitBars = 0;
}

bool BuildH4Zone(bool usePreviousDayRange, int firstH4Bars)
{
   datetime currentDayStart = iTime(_Symbol, PERIOD_D1, 0);

   if(currentDayStart <= 0)
      return false;

   if(currentDayStart == g_h4ZoneDayStart && g_h4ZoneHigh > 0 && g_h4ZoneLow > 0)
      return true;

   g_h4ZoneHigh = 0.0;
   g_h4ZoneLow = 0.0;
   g_h4ZoneDayStart = currentDayStart;
   ResetH4ZoneRetest();

   if(usePreviousDayRange)
   {
      g_h4ZoneHigh = iHigh(_Symbol, PERIOD_D1, 1);
      g_h4ZoneLow = iLow(_Symbol, PERIOD_D1, 1);
      return g_h4ZoneHigh > 0 && g_h4ZoneLow > 0 && g_h4ZoneHigh > g_h4ZoneLow;
   }

   int barsToRead = firstH4Bars < 1 ? 1 : firstH4Bars;
   datetime readyTime = currentDayStart + (barsToRead * 4 * 60 * 60);

   if(TimeCurrent() < readyTime)
      return false;

   int startShift = iBarShift(_Symbol, PERIOD_H4, currentDayStart, false);

   if(startShift < 0)
      return false;

   double high = -DBL_MAX;
   double low = DBL_MAX;

   for(int index = 0; index < barsToRead; index++)
   {
      int shift = startShift - index;

      if(shift < 1)
         break;

      double candleHigh = iHigh(_Symbol, PERIOD_H4, shift);
      double candleLow = iLow(_Symbol, PERIOD_H4, shift);

      if(candleHigh <= 0 || candleLow <= 0)
         continue;

      high = MathMax(high, candleHigh);
      low = MathMin(low, candleLow);
   }

   if(high <= 0 || low <= 0 || high <= low)
      return false;

   g_h4ZoneHigh = high;
   g_h4ZoneLow = low;
   return true;
}

bool CandleBodyPercentOK(double open, double close, double high, double low, double minimumBodyPct)
{
   double range = high - low;

   if(range <= 0)
      return false;

   double bodyPct = MathAbs(close - open) / range * 100.0;
   return bodyPct >= minimumBodyPct;
}

SignalResult AnalyzeH4ZoneRetestMarket(
   bool usePreviousDayRange,
   int firstH4Bars,
   int retestWindowBars,
   double retestTolerancePoints,
   double breakoutMinPoints,
   double breakoutBodyPct,
   bool requireM15Trend,
   double slBufferPoints,
   double buyRsiMin,
   double buyRsiMax,
   double sellRsiMin,
   double sellRsiMax,
   bool allowBuySignals,
   bool allowSellSignals,
   bool useAtrStopCap,
   int atrStopPeriod,
   double atrStopMultiplier,
   double maxStopDistancePoints
)
{
   datetime closedCandleTime = iTime(_Symbol, PERIOD_M5, 1);

   if(closedCandleTime <= 0 || closedCandleTime == g_h4ZoneLastClosedCandle)
      return EmptySignal(g_h4ZoneWaitingRetest ? "H4 zone retest en attente" : "H4 zone idle");

   g_h4ZoneLastClosedCandle = closedCandleTime;

   if(!BuildH4Zone(usePreviousDayRange, firstH4Bars))
      return EmptySignal("H4 zone indisponible");

   double open = iOpen(_Symbol, PERIOD_M5, 1);
   double close = iClose(_Symbol, PERIOD_M5, 1);
   double high = iHigh(_Symbol, PERIOD_M5, 1);
   double low = iLow(_Symbol, PERIOD_M5, 1);
   double previousClose = iClose(_Symbol, PERIOD_M5, 2);
   double tolerance = MathMax(0.0, retestTolerancePoints) * _Point;
   double breakoutDistance = MathMax(0.0, breakoutMinPoints) * _Point;
   int maxWaitBars = retestWindowBars < 1 ? 1 : retestWindowBars;
   double atr = useAtrStopCap ? GetATRValue(PERIOD_M5, atrStopPeriod, 1) : 0.0;
   double rsi = GetRSIValue(PERIOD_M5, 14, 1);
   double h4BuyRsiMin = MathMax(buyRsiMin, 55.0);
   double h4BuyRsiMax = MathMin(buyRsiMax, 68.0);
   double h4SellRsiMin = MathMax(sellRsiMin, 28.0);
   double h4SellRsiMax = MathMin(sellRsiMax, 45.0);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(!g_h4ZoneWaitingRetest)
   {
      bool bodyOK = CandleBodyPercentOK(open, close, high, low, breakoutBodyPct);
      bool bullishBreakout =
         allowBuySignals &&
         previousClose <= g_h4ZoneHigh &&
         close > g_h4ZoneHigh + breakoutDistance &&
         close > open &&
         bodyOK &&
         (!requireM15Trend || IsM15BullishTrend());
      bool bearishBreakout =
         allowSellSignals &&
         previousClose >= g_h4ZoneLow &&
         close < g_h4ZoneLow - breakoutDistance &&
         close < open &&
         bodyOK &&
         (!requireM15Trend || IsM15BearishTrend());

      if(bullishBreakout)
      {
         g_h4ZoneWaitingRetest = true;
         g_h4ZoneBreakoutDir = 1;
         g_h4ZoneBreakoutTime = closedCandleTime;
         g_h4ZoneWaitBars = 0;
         return EmptySignal("H4 zone breakout BUY detecte, attente retest");
      }

      if(bearishBreakout)
      {
         g_h4ZoneWaitingRetest = true;
         g_h4ZoneBreakoutDir = -1;
         g_h4ZoneBreakoutTime = closedCandleTime;
         g_h4ZoneWaitBars = 0;
         return EmptySignal("H4 zone breakout SELL detecte, attente retest");
      }

      return EmptySignal("H4 zone sans breakout");
   }

   g_h4ZoneWaitBars++;

   if(g_h4ZoneWaitBars > maxWaitBars)
   {
      ResetH4ZoneRetest();
      return EmptySignal("H4 zone retest expire");
   }

   if(g_h4ZoneBreakoutDir == 1)
   {
      bool retest =
         low <= g_h4ZoneHigh + tolerance &&
         close > g_h4ZoneHigh &&
         close > open &&
         rsi >= h4BuyRsiMin &&
         rsi <= h4BuyRsiMax &&
         (!requireM15Trend || IsM15BullishTrend());

      if(retest)
      {
         double structuralSL = MathMin(low, g_h4ZoneHigh) - (MathMax(_Point, slBufferPoints * _Point));
         ResetH4ZoneRetest();
         return BuildBuySignal(
            ask,
            structuralSL,
            atr,
            useAtrStopCap,
            atrStopMultiplier,
            maxStopDistancePoints,
            "H4/D1 zone breakout + retest BUY"
         );
      }
   }

   if(g_h4ZoneBreakoutDir == -1)
   {
      bool retest =
         high >= g_h4ZoneLow - tolerance &&
         close < g_h4ZoneLow &&
         close < open &&
         rsi >= h4SellRsiMin &&
         rsi <= h4SellRsiMax &&
         (!requireM15Trend || IsM15BearishTrend());

      if(retest)
      {
         double structuralSL = MathMax(high, g_h4ZoneLow) + (MathMax(_Point, slBufferPoints * _Point));
         ResetH4ZoneRetest();
         return BuildSellSignal(
            bid,
            structuralSL,
            atr,
            useAtrStopCap,
            atrStopMultiplier,
            maxStopDistancePoints,
            "H4/D1 zone breakout + retest SELL"
         );
      }
   }

   return EmptySignal("H4 zone retest en attente");
}

SignalResult AnalyzePullbackMarket(
   int breakoutLookback,
   double stopBuffer,
   double breakoutConfirmPoints,
   double buyRsiMin,
   double buyRsiMax,
   double sellRsiMin,
   double sellRsiMax,
   bool allowBuySignals,
   bool allowSellSignals,
   bool useAtrStopCap,
   int atrStopPeriod,
   double atrStopMultiplier,
   double maxStopDistancePoints,
   int pullbackCandles,
   int pullbackWindowBars,
   double pullbackBreakoutConfirmPoints
)
{
   datetime closedCandleTime = iTime(_Symbol, PERIOD_M5, 1);

   if(closedCandleTime <= 0 || closedCandleTime == g_pullbackLastClosedCandle)
      return EmptySignal(PullbackStateLabel());

   g_pullbackLastClosedCandle = closedCandleTime;

   int requiredPullbacks = pullbackCandles < 1 ? 1 : pullbackCandles;
   int windowBars = pullbackWindowBars < 1 ? 1 : pullbackWindowBars;
   double pullbackConfirmDistance = MathMax(0.0, pullbackBreakoutConfirmPoints) * _Point;
   double buffer = MathMax(_Point, stopBuffer);
   double atr = useAtrStopCap ? GetATRValue(PERIOD_M5, atrStopPeriod, 1) : 0.0;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double close = iClose(_Symbol, PERIOD_M5, 1);

   SignalResult freshSetup = AnalyzeImmediateMarket(
      breakoutLookback,
      stopBuffer,
      breakoutConfirmPoints,
      buyRsiMin,
      buyRsiMax,
      sellRsiMin,
      sellRsiMax,
      allowBuySignals,
      allowSellSignals,
      useAtrStopCap,
      atrStopPeriod,
      atrStopMultiplier,
      maxStopDistancePoints
   );

   if(g_pullbackState == PULLBACK_IDLE && freshSetup.action != SIGNAL_WAIT)
   {
      if(freshSetup.action == SIGNAL_BUY)
      {
         g_pullbackState = PULLBACK_ARMED_BUY;
         g_pullbackBreakoutLevel = iHigh(_Symbol, PERIOD_M5, 1);
      }
      else if(freshSetup.action == SIGNAL_SELL)
      {
         g_pullbackState = PULLBACK_ARMED_SELL;
         g_pullbackBreakoutLevel = iLow(_Symbol, PERIOD_M5, 1);
      }

      g_pullbackCounter = 0;
      g_pullbackWindowCounter = 0;
      g_pullbackBarsSinceArmed = 0;

      return EmptySignal("Setup detecte, attente pullback");
   }

   if(g_pullbackState == PULLBACK_ARMED_BUY || g_pullbackState == PULLBACK_ARMED_SELL)
   {
      g_pullbackBarsSinceArmed++;

      if(g_pullbackBarsSinceArmed > requiredPullbacks + windowBars + 5)
      {
         ResetPullbackEntry();
         return EmptySignal("Pullback expire");
      }

      if(g_pullbackState == PULLBACK_ARMED_BUY)
      {
         if(IsBearishClose())
            g_pullbackCounter++;

         if(freshSetup.action == SIGNAL_SELL)
         {
            ResetPullbackEntry();
            return EmptySignal("Pullback invalide par signal oppose");
         }

         if(g_pullbackCounter >= requiredPullbacks)
         {
            g_pullbackState = PULLBACK_WINDOW_BUY;
            g_pullbackWindowCounter = 0;
            return EmptySignal("Pullback BUY confirme, fenetre ouverte");
         }
      }

      if(g_pullbackState == PULLBACK_ARMED_SELL)
      {
         if(IsBullishClose())
            g_pullbackCounter++;

         if(freshSetup.action == SIGNAL_BUY)
         {
            ResetPullbackEntry();
            return EmptySignal("Pullback invalide par signal oppose");
         }

         if(g_pullbackCounter >= requiredPullbacks)
         {
            g_pullbackState = PULLBACK_WINDOW_SELL;
            g_pullbackWindowCounter = 0;
            return EmptySignal("Pullback SELL confirme, fenetre ouverte");
         }
      }
   }

   if(g_pullbackState == PULLBACK_WINDOW_BUY)
   {
      g_pullbackWindowCounter++;

      if(g_pullbackWindowCounter > windowBars)
      {
         ResetPullbackEntry();
         return EmptySignal("Fenetre pullback BUY expiree");
      }

      if(close > g_pullbackBreakoutLevel + pullbackConfirmDistance && IsBullishClose() && IsM15BullishTrend())
      {
         double structuralSL = GetRecentLow(requiredPullbacks + 2, 1) - buffer;
         ResetPullbackEntry();

         return BuildBuySignal(
            ask,
            structuralSL,
            atr,
            useAtrStopCap,
            atrStopMultiplier,
            maxStopDistancePoints,
            "Entree BUY apres breakout, pullback et reprise"
         );
      }
   }

   if(g_pullbackState == PULLBACK_WINDOW_SELL)
   {
      g_pullbackWindowCounter++;

      if(g_pullbackWindowCounter > windowBars)
      {
         ResetPullbackEntry();
         return EmptySignal("Fenetre pullback SELL expiree");
      }

      if(close < g_pullbackBreakoutLevel - pullbackConfirmDistance && IsBearishClose() && IsM15BearishTrend())
      {
         double structuralSL = GetRecentHigh(requiredPullbacks + 2, 1) + buffer;
         ResetPullbackEntry();

         return BuildSellSignal(
            bid,
            structuralSL,
            atr,
            useAtrStopCap,
            atrStopMultiplier,
            maxStopDistancePoints,
            "Entree SELL apres breakout, pullback et reprise"
         );
      }
   }

   return EmptySignal(PullbackStateLabel());
}

SignalResult AnalyzeMarket(
   int breakoutLookback,
   double stopBuffer,
   double breakoutConfirmPoints,
   double buyRsiMin,
   double buyRsiMax,
   double sellRsiMin,
   double sellRsiMax,
   bool allowBuySignals,
   bool allowSellSignals,
   bool useAtrStopCap,
   int atrStopPeriod,
   double atrStopMultiplier,
   double maxStopDistancePoints,
   bool usePullbackEntry,
   int pullbackCandles,
   int pullbackWindowBars,
   double pullbackBreakoutConfirmPoints,
   bool useH4ZoneRetest,
   bool h4UsePreviousDayRange,
   int h4ZoneFirstBars,
   int h4RetestWindowBars,
   double h4RetestTolerancePoints,
   double h4BreakoutMinPoints,
   double h4BreakoutBodyPct,
   bool h4RequireM15Trend,
   double h4SLBufferPoints
)
{
   if(useH4ZoneRetest)
   {
      return AnalyzeH4ZoneRetestMarket(
         h4UsePreviousDayRange,
         h4ZoneFirstBars,
         h4RetestWindowBars,
         h4RetestTolerancePoints,
         h4BreakoutMinPoints,
         h4BreakoutBodyPct,
         h4RequireM15Trend,
         h4SLBufferPoints,
         buyRsiMin,
         buyRsiMax,
         sellRsiMin,
         sellRsiMax,
         allowBuySignals,
         allowSellSignals,
         useAtrStopCap,
         atrStopPeriod,
         atrStopMultiplier,
         maxStopDistancePoints
      );
   }

   if(usePullbackEntry)
   {
      return AnalyzePullbackMarket(
         breakoutLookback,
         stopBuffer,
         breakoutConfirmPoints,
         buyRsiMin,
         buyRsiMax,
         sellRsiMin,
         sellRsiMax,
         allowBuySignals,
         allowSellSignals,
         useAtrStopCap,
         atrStopPeriod,
         atrStopMultiplier,
         maxStopDistancePoints,
         pullbackCandles,
         pullbackWindowBars,
         pullbackBreakoutConfirmPoints
      );
   }

   return AnalyzeImmediateMarket(
      breakoutLookback,
      stopBuffer,
      breakoutConfirmPoints,
      buyRsiMin,
      buyRsiMax,
      sellRsiMin,
      sellRsiMax,
      allowBuySignals,
      allowSellSignals,
      useAtrStopCap,
      atrStopPeriod,
      atrStopMultiplier,
      maxStopDistancePoints
   );
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

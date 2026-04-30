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

// -----------------------------------------------------------------------
// Handles globaux — initialises une seule fois dans OnInit
// -----------------------------------------------------------------------
int g_hEMA20_M15  = INVALID_HANDLE;  // Trend M15 rapide
int g_hEMA50_M15  = INVALID_HANDLE;  // Trend M15 lent
int g_hEMA200_H1  = INVALID_HANDLE;  // Direction majeure H1 (filtre principal)
int g_hRSI_M5     = INVALID_HANDLE;  // Oscillateur M5
int g_hBB_M5      = INVALID_HANDLE;  // Bandes de Bollinger M5 (20, 2.0)
int g_hMACD_M5    = INVALID_HANDLE;  // MACD M5 (12/26/9)
int g_hATR_M5     = INVALID_HANDLE;  // Volatilite M5
int g_hATR_H1     = INVALID_HANDLE;  // Volatilite H1 (contexte)

bool InitIndicators()
{
   g_hEMA20_M15 = iMA(_Symbol, PERIOD_M15, 20,  0, MODE_EMA, PRICE_CLOSE);
   g_hEMA50_M15 = iMA(_Symbol, PERIOD_M15, 50,  0, MODE_EMA, PRICE_CLOSE);
   g_hEMA200_H1 = iMA(_Symbol, PERIOD_H1,  200, 0, MODE_EMA, PRICE_CLOSE);
   g_hRSI_M5    = iRSI(_Symbol, PERIOD_M5, 14, PRICE_CLOSE);
   g_hBB_M5     = iBands(_Symbol, PERIOD_M5, 20, 0, 2.0, PRICE_CLOSE);
   g_hMACD_M5   = iMACD(_Symbol, PERIOD_M5, 12, 26, 9, PRICE_CLOSE);
   g_hATR_M5    = iATR(_Symbol, PERIOD_M5, 14);
   g_hATR_H1    = iATR(_Symbol, PERIOD_H1, 14);

   if(g_hEMA20_M15 == INVALID_HANDLE || g_hEMA50_M15 == INVALID_HANDLE ||
      g_hEMA200_H1 == INVALID_HANDLE || g_hRSI_M5    == INVALID_HANDLE ||
      g_hBB_M5     == INVALID_HANDLE || g_hMACD_M5   == INVALID_HANDLE ||
      g_hATR_M5    == INVALID_HANDLE || g_hATR_H1    == INVALID_HANDLE)
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
   if(g_hEMA200_H1 != INVALID_HANDLE){ IndicatorRelease(g_hEMA200_H1); g_hEMA200_H1 = INVALID_HANDLE; }
   if(g_hRSI_M5    != INVALID_HANDLE){ IndicatorRelease(g_hRSI_M5);    g_hRSI_M5    = INVALID_HANDLE; }
   if(g_hBB_M5     != INVALID_HANDLE){ IndicatorRelease(g_hBB_M5);     g_hBB_M5     = INVALID_HANDLE; }
   if(g_hMACD_M5   != INVALID_HANDLE){ IndicatorRelease(g_hMACD_M5);   g_hMACD_M5   = INVALID_HANDLE; }
   if(g_hATR_M5    != INVALID_HANDLE){ IndicatorRelease(g_hATR_M5);    g_hATR_M5    = INVALID_HANDLE; }
   if(g_hATR_H1    != INVALID_HANDLE){ IndicatorRelease(g_hATR_H1);    g_hATR_H1    = INVALID_HANDLE; }
}

// -----------------------------------------------------------------------
// Lecture generique d'un buffer d'indicateur
// -----------------------------------------------------------------------
double GetIndValue(int handle, int bufferIdx, int shift)
{
   if(handle == INVALID_HANDLE) return 0.0;
   double buf[];
   if(CopyBuffer(handle, bufferIdx, shift, 1, buf) <= 0) return 0.0;
   return buf[0];
}

// Accesseurs
double GetRSI(int shift = 1)       { return GetIndValue(g_hRSI_M5,    0, shift); }
double GetBBUpper(int shift = 1)   { return GetIndValue(g_hBB_M5,     1, shift); }
double GetBBLower(int shift = 1)   { return GetIndValue(g_hBB_M5,     2, shift); }
double GetBBMiddle(int shift = 1)  { return GetIndValue(g_hBB_M5,     0, shift); }
double GetMACDMain(int shift = 1)  { return GetIndValue(g_hMACD_M5,   0, shift); }
double GetATR(int shift = 1)       { return GetIndValue(g_hATR_M5,    0, shift); }
double GetATRH1(int shift = 1)     { return GetIndValue(g_hATR_H1,    0, shift); }
double GetEMA200H1(int shift = 1)  { return GetIndValue(g_hEMA200_H1, 0, shift); }

// -----------------------------------------------------------------------
// Filtres de tendance
// H1 EMA200 : direction MAJEURE (or en tendance baissiere = seulement SELL)
// M15 EMA20/50 : tendance intermediaire
// -----------------------------------------------------------------------
bool IsH1BullishMajor()
{
   double ema200 = GetEMA200H1(1);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return ema200 > 0 && bid > ema200;
}

bool IsH1BearishMajor()
{
   double ema200 = GetEMA200H1(1);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return ema200 > 0 && bid < ema200;
}

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

// Largeur BB : mesure la volatilite courante
double GetBBWidth(int shift = 1)
{
   double upper = GetBBUpper(shift);
   double lower = GetBBLower(shift);
   return upper > 0 && lower > 0 ? (upper - lower) : 0.0;
}

// -----------------------------------------------------------------------
// Helpers bougies
// -----------------------------------------------------------------------
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
// AnalyzeMarket — 4 setups avec filtres en cascade
//
// SETUP 1 & 2 : Mean-Reversion BB+RSI (inspire BBRSI XAUUSD-5M)
//   - RSI croise 25/75 (seuil plus strict : signaux plus rares, meilleure qualite)
//   - Prix repasse le BB lower/upper
//   - Filtre H1 EMA200 OBLIGATOIRE (direction majeure)
//   - SL = 1.0*ATR (plus large = moins de stops sur le bruit)
//   - TP = 2.0*SL  (RR 1:2)
//
// SETUP 3 & 4 : Cassure de range avec 3 conditions obligatoires
//   - Cassure H/L 20 bougies + bougie forte + EMA M15 + MACD dans la direction
//   - Prix au-dela du BB Middle (confirme la pression directionnelle)
//   - Filtre H1 EMA200 OBLIGATOIRE
//   - Filtre ATR minimum : ne pas trader si trop calme (ATR < 0.2*ATR_H1)
//   - SL = 1.0*ATR | TP = 2.0*SL
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

   double close   = iClose(_Symbol, PERIOD_M5, 1);
   double close2  = iClose(_Symbol, PERIOD_M5, 2);
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double rsi1    = GetRSI(1);
   double rsi2    = GetRSI(2);
   double bbUp1   = GetBBUpper(1);
   double bbUp2   = GetBBUpper(2);
   double bbLo1   = GetBBLower(1);
   double bbLo2   = GetBBLower(2);
   double bbMid1  = GetBBMiddle(1);
   double macd1   = GetMACDMain(1);
   double macd2   = GetMACDMain(2);
   double atr     = GetATR(1);
   double atrH1   = GetATRH1(1);

   // Fallback si ATR non disponible
   if(atr   <= 0) atr   = 50.0 * _Point;
   if(atrH1 <= 0) atrH1 = 200.0 * _Point;

   double slDistance = atr * 1.0;    // SL = 1 ATR (anterieur : 0.5)
   double tpRatio    = 2.0;          // TP = 2x SL (anterieur : 1.5)

   // Filtre volatilite : ne pas trader si ATR M5 < 20% de l'ATR H1
   // Evite les periodes trop calmes (nuit asiatique sur l'or)
   bool marketActive = (atr >= atrH1 * 0.20);

   bool bullMajor = IsH1BullishMajor();
   bool bearMajor = IsH1BearishMajor();
   bool bullM15   = IsM15BullishTrend();
   bool bearM15   = IsM15BearishTrend();

   if(!marketActive)
   {
      signal.reason = "Marche trop calme (ATR faible)";
      return signal;
   }

   // -------------------------------------------------------
   // SETUP 1 : Mean Reversion BUY (BB+RSI)
   // Conditions obligatoires :
   //   - RSI < 25 sur bougie 2, RSI > 25 sur bougie 1 (croisement haussier)
   //   - Close 2 sous BB Lower, Close 1 au-dessus
   //   - H1 EMA200 : prix AU-DESSUS (zone haussiere majeure)
   // -------------------------------------------------------
   if(bullMajor && rsi2 < 25.0 && close2 < bbLo2 && rsi1 > 25.0 && close > bbLo1)
   {
      double conf = 72.0;
      string reasons = "BB+RSI oversold (RSI<25)";

      if(bullM15)               { conf += 8.0;  reasons += " | EMA M15 haussier"; }
      if(macd1 > 0)             { conf += 5.0;  reasons += " | MACD>0"; }
      if(macd1 > macd2)         { conf += 3.0;  reasons += " | MACD hausse"; }
      if(IsStrongBullishCandle()){ conf += 5.0; reasons += " | bougie forte"; }
      if(rsi2 < 20.0)           { conf += 2.0;  reasons += " | RSI extreme"; }

      signal.action     = SIGNAL_BUY;
      signal.entry      = ask;
      signal.sl         = bbLo1 - slDistance;
      signal.tp1        = ask + MathAbs(ask - signal.sl) * tpRatio;
      signal.confidence = MathMin(conf, 95.0);
      signal.reason     = reasons;
      return signal;
   }

   // -------------------------------------------------------
   // SETUP 2 : Mean Reversion SELL (BB+RSI)
   // Conditions obligatoires :
   //   - RSI > 75 sur bougie 2, RSI < 75 sur bougie 1 (croisement baissier)
   //   - Close 2 au-dessus BB Upper, Close 1 en-dessous
   //   - H1 EMA200 : prix EN-DESSOUS (zone baissiere majeure)
   // -------------------------------------------------------
   if(bearMajor && rsi2 > 75.0 && close2 > bbUp2 && rsi1 < 75.0 && close < bbUp1)
   {
      double conf = 72.0;
      string reasons = "BB+RSI overbought (RSI>75)";

      if(bearM15)               { conf += 8.0;  reasons += " | EMA M15 baissier"; }
      if(macd1 < 0)             { conf += 5.0;  reasons += " | MACD<0"; }
      if(macd1 < macd2)         { conf += 3.0;  reasons += " | MACD baisse"; }
      if(IsStrongBearishCandle()){ conf += 5.0; reasons += " | bougie forte"; }
      if(rsi2 > 80.0)           { conf += 2.0;  reasons += " | RSI extreme"; }

      signal.action     = SIGNAL_SELL;
      signal.entry      = bid;
      signal.sl         = bbUp1 + slDistance;
      signal.tp1        = bid - MathAbs(signal.sl - bid) * tpRatio;
      signal.confidence = MathMin(conf, 95.0);
      signal.reason     = reasons;
      return signal;
   }

   // -------------------------------------------------------
   // SETUP 3 : Cassure haussiere de range
   // Conditions obligatoires :
   //   - Close > High des 20 dernieres bougies
   //   - Bougie forte haussiere
   //   - EMA M15 haussier ET MACD > 0 (MACD devient obligatoire)
   //   - Prix au-dessus du BB Middle (pression haussiere confirmee)
   //   - H1 EMA200 en zone haussiere
   // -------------------------------------------------------
   double recentHigh = GetRecentHigh(20);
   double recentLow  = GetRecentLow(20);

   if(bullMajor && bullM15 && macd1 > 0 &&
      close > recentHigh && close > bbMid1 &&
      IsStrongBullishCandle())
   {
      double conf = 68.0;
      string reasons = "Cassure haussiere M5";

      if(macd1 > macd2)                 { conf += 7.0;  reasons += " | MACD hausse"; }
      if(rsi1 > 50.0 && rsi1 < 70.0)   { conf += 5.0;  reasons += " | RSI haussier"; }
      if(close > bbMid1 * 1.001)        { conf += 3.0;  reasons += " | BB Middle franchi"; }

      signal.action     = SIGNAL_BUY;
      signal.entry      = ask;
      signal.sl         = recentHigh - slDistance;
      signal.tp1        = ask + MathAbs(ask - signal.sl) * tpRatio;
      signal.confidence = MathMin(conf, 95.0);
      signal.reason     = reasons;
      return signal;
   }

   // -------------------------------------------------------
   // SETUP 4 : Cassure baissiere de range
   // Conditions obligatoires :
   //   - Close < Low des 20 dernieres bougies
   //   - Bougie forte baissiere
   //   - EMA M15 baissier ET MACD < 0 (MACD devient obligatoire)
   //   - Prix en-dessous du BB Middle
   //   - H1 EMA200 en zone baissiere
   // -------------------------------------------------------
   if(bearMajor && bearM15 && macd1 < 0 &&
      close < recentLow && close < bbMid1 &&
      IsStrongBearishCandle())
   {
      double conf = 68.0;
      string reasons = "Cassure baissiere M5";

      if(macd1 < macd2)                 { conf += 7.0;  reasons += " | MACD baisse"; }
      if(rsi1 < 50.0 && rsi1 > 30.0)   { conf += 5.0;  reasons += " | RSI baissier"; }
      if(close < bbMid1 * 0.999)        { conf += 3.0;  reasons += " | BB Middle franchi"; }

      signal.action     = SIGNAL_SELL;
      signal.entry      = bid;
      signal.sl         = recentLow + slDistance;
      signal.tp1        = bid - MathAbs(signal.sl - bid) * tpRatio;
      signal.confidence = MathMin(conf, 95.0);
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
#ifndef DEEP_GOLD_SCALPING_STRATEGY_MQH
#define DEEP_GOLD_SCALPING_STRATEGY_MQH

#include "GoldSignalEngine.mqh"

double DgsHigh(ENUM_TIMEFRAMES tf,int bars,int shift)
{
   double value=iHigh(_Symbol,tf,shift);
   for(int i=shift+1;i<shift+bars;i++)
      value=MathMax(value,iHigh(_Symbol,tf,i));
   return value;
}

double DgsLow(ENUM_TIMEFRAMES tf,int bars,int shift)
{
   double value=iLow(_Symbol,tf,shift);
   for(int i=shift+1;i<shift+bars;i++)
      value=MathMin(value,iLow(_Symbol,tf,i));
   return value;
}

bool DgsTrendUp()
{
   double ema20=GetEMAValue(PERIOD_M15,20,1);
   double ema50=GetEMAValue(PERIOD_M15,50,1);
   return ema20>0 && ema50>0 && ema20>ema50;
}

bool DgsTrendDown()
{
   double ema20=GetEMAValue(PERIOD_M15,20,1);
   double ema50=GetEMAValue(PERIOD_M15,50,1);
   return ema20>0 && ema50>0 && ema20<ema50;
}

SignalResult AnalyzeDeepScalp(int rangeBars,int bosBars,double sweepPts,double confirmPts,double bufferPts,double tpR,bool useAtrCap,int atrPeriod,double atrMult,double maxStopPts)
{
   int rb=MathMax(5,rangeBars);
   int bb=MathMax(3,bosBars);
   double sweep=sweepPts*_Point;
   double confirm=confirmPts*_Point;
   double atr=useAtrCap?GetATRValue(PERIOD_M5,atrPeriod,1):0.0;

   double rangeHigh=DgsHigh(PERIOD_M5,rb,2);
   double rangeLow=DgsLow(PERIOD_M5,rb,2);
   double bosHigh=DgsHigh(PERIOD_M1,bb,2);
   double bosLow=DgsLow(PERIOD_M1,bb,2);

   double open=iOpen(_Symbol,PERIOD_M1,1);
   double close=iClose(_Symbol,PERIOD_M1,1);
   double high=iHigh(_Symbol,PERIOD_M1,1);
   double low=iLow(_Symbol,PERIOD_M1,1);

   if(DgsTrendUp() && low<rangeLow-sweep && close>rangeLow && close>open && close>bosHigh+confirm)
   {
      double sl=low-MathMax(_Point,bufferPts*_Point);
      SignalResult s=BuildBuySignal(SymbolInfoDouble(_Symbol,SYMBOL_ASK),sl,atr,useAtrCap,atrMult,maxStopPts,"DeepScalp BUY: sweep low + BOS M1 + trend M15");
      s.tp1=s.entry+MathAbs(s.entry-s.sl)*tpR;
      s.confidence=82.0;
      return s;
   }

   if(DgsTrendDown() && high>rangeHigh+sweep && close<rangeHigh && close<open && close<bosLow-confirm)
   {
      double sl=high+MathMax(_Point,bufferPts*_Point);
      SignalResult s=BuildSellSignal(SymbolInfoDouble(_Symbol,SYMBOL_BID),sl,atr,useAtrCap,atrMult,maxStopPts,"DeepScalp SELL: sweep high + BOS M1 + trend M15");
      s.tp1=s.entry-MathAbs(s.sl-s.entry)*tpR;
      s.confidence=82.0;
      return s;
   }

   return EmptySignal("DeepScalp WAIT");
}

#endif

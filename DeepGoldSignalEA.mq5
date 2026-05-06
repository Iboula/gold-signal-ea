#property version   "1.00"
#include "GoldSignalEngine.mqh"
#include "DeepGoldScalpingStrategy.mqh"

input bool AutoTrade = false;
input int DeepRangeBars = 12;
input int DeepBosBars = 5;
input double DeepSweepPoints = 80;
input double DeepBosConfirmPoints = 30;
input double DeepSLBufferPoints = 120;
input double DeepTP1RR = 2.0;
input bool UseAtrStopCap = true;
input int AtrStopPeriod = 14;
input double AtrStopMultiplier = 1.5;
input double MaxStopDistancePoints = 1800.0;

void OnTick()
{
   SignalResult signal = AnalyzeDeepScalp(
      DeepRangeBars,
      DeepBosBars,
      DeepSweepPoints,
      DeepBosConfirmPoints,
      DeepSLBufferPoints,
      DeepTP1RR,
      UseAtrStopCap,
      AtrStopPeriod,
      AtrStopMultiplier,
      MaxStopDistancePoints
   );

   string text="Deep Gold Scalping EA\n";
   text+="Action: "+SignalActionToString(signal.action)+"\n";
   text+="Entry: "+DoubleToString(signal.entry,_Digits)+"\n";
   text+="SL: "+DoubleToString(signal.sl,_Digits)+"\n";
   text+="TP1: "+DoubleToString(signal.tp1,_Digits)+"\n";
   text+="Confidence: "+DoubleToString(signal.confidence,1)+"\n";
   text+="Reason: "+signal.reason+"\n";

   Comment(text);

   if(signal.action!=SIGNAL_WAIT)
   {
      Alert("Deep scalp signal detected: "+SignalActionToString(signal.action));
   }
}

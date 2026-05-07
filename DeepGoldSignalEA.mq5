#property version   "1.03"
#include "GoldSignalEngine.mqh"
#include "DeepGoldScalpingStrategy.mqh"
#include "AiValidationClient.mqh"

#define DEEP_SIGNAL_FILE "DeepGoldSignalEA_Signals.csv"

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

input bool UseSessionFilter = true;
input int LondonStartHour = 8;
input int NewYorkEndHour = 17;
input bool UseNoTradeWindow = true;
input int NoTradeStartHour = 13;
input int NoTradeEndHour = 15;
input double MaxSpreadPoints = 50;
input double MinAtrPoints = 120;
input double MaxAtrPoints = 900;
input double MinConfidence = 80;
input int AlertCooldownMinutes = 10;

input bool UseAiValidation = true;
input string AiApiUrl = "http://localhost:5000/api/signals/analyze";
input int AiTimeoutMs = 8000;
input double MinAiScore = 80;
input bool SendTelegramOnlyIfAiApproved = true;

input bool UseTelegram = false;
input string TelegramBotToken = "";
input string TelegramChatId = "";
input int TelegramTimeoutMs = 5000;

string lastSignalKey = "";
datetime lastAlertTime = 0;

bool IsSessionOk()
{
   if(!UseSessionFilter)
      return true;

   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   return t.hour >= LondonStartHour && t.hour <= NewYorkEndHour;
}

bool IsNoTradeTime()
{
   if(!UseNoTradeWindow)
      return false;

   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);

   if(NoTradeStartHour < NoTradeEndHour)
      return t.hour >= NoTradeStartHour && t.hour < NoTradeEndHour;

   return t.hour >= NoTradeStartHour || t.hour < NoTradeEndHour;
}

double SpreadPoints()
{
   return (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
}

bool AtrOk(double atrPoints)
{
   if(MinAtrPoints > 0 && atrPoints < MinAtrPoints)
      return false;

   if(MaxAtrPoints > 0 && atrPoints > MaxAtrPoints)
      return false;

   return true;
}

double ScoreSignal(const SignalResult &signal, double spread, double atrPoints)
{
   if(signal.action == SIGNAL_WAIT)
      return 0.0;

   double score = signal.confidence;

   if(IsSessionOk())
      score += 5.0;

   if(spread <= MaxSpreadPoints * 0.60)
      score += 4.0;

   if(atrPoints >= MinAtrPoints && atrPoints <= MaxAtrPoints)
      score += 5.0;

   if(DeepTP1RR >= 2.0)
      score += 3.0;

   return MathMin(score, 95.0);
}

string BlockReason(double spread, double atrPoints, double score)
{
   if(!IsSessionOk())
      return "Hors session";

   if(IsNoTradeTime())
      return "Fenetre no-trade";

   if(spread > MaxSpreadPoints)
      return "Spread trop eleve";

   if(!AtrOk(atrPoints))
      return "ATR hors limite";

   if(score < MinConfidence)
      return "Confiance insuffisante";

   return "OK";
}

string UrlEncode(string value)
{
   string result = "";
   int length = StringLen(value);

   for(int i = 0; i < length; i++)
   {
      ushort c = StringGetCharacter(value, i);

      if((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))
         result += ShortToString(c);
      else if(c == ' ')
         result += "%20";
      else if(c == '\n')
         result += "%0A";
      else if(c == ':' )
         result += "%3A";
      else if(c == '|' )
         result += "%7C";
      else if(c == '#' )
         result += "%23";
      else if(c == '/' )
         result += "%2F";
      else if(c == '+' )
         result += "%2B";
      else if(c == '-' )
         result += "%2D";
      else if(c == '.' )
         result += ".";
      else
         result += "%20";
   }

   return result;
}

bool SendTelegram(string message)
{
   if(!UseTelegram || TelegramBotToken == "" || TelegramChatId == "")
      return false;

   string url = "https://api.telegram.org/bot" + TelegramBotToken + "/sendMessage?chat_id=" + TelegramChatId + "&text=" + UrlEncode(message);
   char data[];
   char result[];
   string headers;

   ResetLastError();
   int code = WebRequest("GET", url, "", TelegramTimeoutMs, data, result, headers);

   if(code == -1)
   {
      Print("Telegram WebRequest failed. Add https://api.telegram.org in MT5 options. Error=", GetLastError());
      return false;
   }

   return code == 200;
}

int OpenDeepCsv()
{
   int h = FileOpen(DEEP_SIGNAL_FILE, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');

   if(h != INVALID_HANDLE)
      return h;

   h = FileOpen(DEEP_SIGNAL_FILE, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
   if(h == INVALID_HANDLE)
      return INVALID_HANDLE;

   FileClose(h);
   return FileOpen(DEEP_SIGNAL_FILE, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
}

void LogSignal(const SignalResult &signal, double score, double spread, double atrPoints, string block)
{
   if(signal.action == SIGNAL_WAIT)
      return;

   datetime candleTime = iTime(_Symbol, PERIOD_M1, 1);
   string key = TimeToString(candleTime, TIME_DATE | TIME_MINUTES) + "_" + SignalActionToString(signal.action);

   if(key == lastSignalKey)
      return;

   int h = OpenDeepCsv();
   if(h == INVALID_HANDLE)
      return;

   if(FileSize(h) == 0)
   {
      FileWrite(h, "Date", "Symbol", "Action", "Entry", "SL", "TP1", "Confidence", "Spread", "ATRPoints", "Block", "Reason");
   }

   FileSeek(h, 0, SEEK_END);
   FileWrite(
      h,
      TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES),
      _Symbol,
      SignalActionToString(signal.action),
      DoubleToString(signal.entry, _Digits),
      DoubleToString(signal.sl, _Digits),
      DoubleToString(signal.tp1, _Digits),
      DoubleToString(score, 1),
      DoubleToString(spread, 1),
      DoubleToString(atrPoints, 1),
      block,
      signal.reason
   );

   FileClose(h);
   lastSignalKey = key;
}

string BuildSignalMessage(const SignalResult &signal, double score, double spread, double atrPoints, string aiComment)
{
   string msg = "Deep Gold Scalp " + SignalActionToString(signal.action) + "\n";
   msg += "Symbol: " + _Symbol + "\n";
   msg += "Entry: " + DoubleToString(signal.entry, _Digits) + "\n";
   msg += "SL: " + DoubleToString(signal.sl, _Digits) + "\n";
   msg += "TP1: " + DoubleToString(signal.tp1, _Digits) + "\n";
   msg += "Score: " + DoubleToString(score, 1) + "%\n";
   msg += "Spread: " + DoubleToString(spread, 1) + " pts\n";
   msg += "ATR M5: " + DoubleToString(atrPoints, 1) + " pts\n";
   if(aiComment != "")
      msg += "AI: " + aiComment + "\n";
   msg += "Reason: " + signal.reason;
   return msg;
}

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

   double spread = SpreadPoints();
   double atrPoints = GetATRValue(PERIOD_M5, AtrStopPeriod, 1) / _Point;
   double algoScore = ScoreSignal(signal, spread, atrPoints);
   string block = BlockReason(spread, atrPoints, algoScore);

   double finalScore = algoScore;
   bool aiApproved = !UseAiValidation;
   string aiComment = "AI disabled";

   bool shouldAskAi = signal.action != SIGNAL_WAIT && block == "OK" && UseAiValidation;

   if(shouldAskAi)
   {
      string sessionLabel = IsSessionOk() ? "OK" : "OUT";
      string json = BuildAiSignalJson(
         SignalActionToString(signal.action),
         signal.entry,
         signal.sl,
         signal.tp1,
         algoScore,
         spread,
         atrPoints,
         sessionLabel,
         signal.reason,
         _Digits
      );

      AiValidationResult ai = ValidateSignalWithAiApi(AiApiUrl, json, AiTimeoutMs);
      aiApproved = ai.success && ai.approved && ai.score >= MinAiScore;
      aiComment = ai.comment;

      if(ai.success && ai.score > 0)
         finalScore = ai.score;
   }

   if(UseAiValidation && signal.action != SIGNAL_WAIT && block == "OK" && !aiApproved)
      block = "AI refuse";

   LogSignal(signal, finalScore, spread, atrPoints, block);

   string text="Deep Gold Scalping EA v1.03\n";
   text+="Mode: SIGNAL ONLY\n";
   text+="Action: "+SignalActionToString(signal.action)+"\n";
   text+="Entry: "+DoubleToString(signal.entry,_Digits)+"\n";
   text+="SL: "+DoubleToString(signal.sl,_Digits)+"\n";
   text+="TP1: "+DoubleToString(signal.tp1,_Digits)+"\n";
   text+="Algo Score: "+DoubleToString(algoScore,1)+"\n";
   text+="Final Score: "+DoubleToString(finalScore,1)+"\n";
   text+="AI: "+(UseAiValidation ? (aiApproved ? "APPROVED" : "NOT APPROVED") : "OFF")+"\n";
   text+="Spread: "+DoubleToString(spread,1)+"\n";
   text+="ATR M5: "+DoubleToString(atrPoints,1)+" pts\n";
   text+="Session OK: "+(IsSessionOk()?"YES":"NO")+"\n";
   text+="NoTrade: "+(IsNoTradeTime()?"YES":"NO")+"\n";
   text+="Telegram: "+(UseTelegram?"ON":"OFF")+"\n";
   text+="Block: "+block+"\n";
   text+="AI Comment: "+aiComment+"\n";
   text+="Reason: "+signal.reason+"\n";
   Comment(text);

   bool telegramAllowed = !SendTelegramOnlyIfAiApproved || !UseAiValidation || aiApproved;
   bool canAlert = signal.action != SIGNAL_WAIT && block == "OK" && telegramAllowed && (TimeCurrent() - lastAlertTime) >= AlertCooldownMinutes * 60;

   if(canAlert)
   {
      string msg = BuildSignalMessage(signal, finalScore, spread, atrPoints, aiComment);
      Alert(msg);
      SendTelegram(msg);
      lastAlertTime = TimeCurrent();
   }
}

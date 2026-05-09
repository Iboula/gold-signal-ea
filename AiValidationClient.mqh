#ifndef AI_VALIDATION_CLIENT_MQH
#define AI_VALIDATION_CLIENT_MQH

struct AiValidationResult
{
   bool approved;
   double score;
   string comment;
   bool success;
};

string AiJsonEscape(string value)
{
   string result = value;
   StringReplace(result, "\\", "\\\\");
   StringReplace(result, "\"", "\\\"");
   StringReplace(result, "\r", " ");
   StringReplace(result, "\n", " ");
   return result;
}

string BuildAiSignalJson(
   string symbol,
   string action,
   double entry,
   double sl,
   double tp1,
   double confidence,
   double spread,
   double atr,
   string session,
   string reason,
   int digits
)
{
   string json = "{";
   json += "\"symbol\":\"" + AiJsonEscape(symbol) + "\",";
   json += "\"action\":\"" + AiJsonEscape(action) + "\",";
   json += "\"entry\":" + DoubleToString(entry, digits) + ",";
   json += "\"stopLoss\":" + DoubleToString(sl, digits) + ",";
   json += "\"takeProfit\":" + DoubleToString(tp1, digits) + ",";
   json += "\"confidence\":" + DoubleToString(confidence, 1) + ",";
   json += "\"spread\":" + DoubleToString(spread, 1) + ",";
   json += "\"atr\":" + DoubleToString(atr, 1) + ",";
   json += "\"session\":\"" + AiJsonEscape(session) + "\",";
   json += "\"reason\":\"" + AiJsonEscape(reason) + "\"";
   json += "}";
   return json;
}

string ExtractJsonString(string json, string key)
{
   string marker = "\"" + key + "\":";
   int pos = StringFind(json, marker);
   if(pos < 0) return "";

   pos += StringLen(marker);
   while(pos < StringLen(json) && StringGetCharacter(json, pos) == ' ') pos++;
   if(pos >= StringLen(json) || StringGetCharacter(json, pos) != '"') return "";

   pos++;
   int end = StringFind(json, "\"", pos);
   if(end < 0) return "";

   return StringSubstr(json, pos, end - pos);
}

bool ExtractJsonBool(string json, string key)
{
   string marker = "\"" + key + "\":";
   int pos = StringFind(json, marker);
   if(pos < 0) return false;

   pos += StringLen(marker);
   string value = StringSubstr(json, pos, 5);
   return StringFind(value, "true") >= 0;
}

double ExtractJsonDouble(string json, string key)
{
   string marker = "\"" + key + "\":";
   int pos = StringFind(json, marker);
   if(pos < 0) return 0.0;

   pos += StringLen(marker);
   int end = pos;
   while(end < StringLen(json))
   {
      ushort c = StringGetCharacter(json, end);
      if((c >= '0' && c <= '9') || c == '.' || c == '-')
      {
         end++;
         continue;
      }
      break;
   }

   return StringToDouble(StringSubstr(json, pos, end - pos));
}

AiValidationResult ValidateSignalWithAiApi(string apiUrl, string jsonBody, int timeoutMs)
{
   AiValidationResult validation;
   validation.approved = false;
   validation.score = 0.0;
   validation.comment = "AI unavailable";
   validation.success = false;

   char body[];
   StringToCharArray(jsonBody, body, 0, StringLen(jsonBody));

   char response[];
   string responseHeaders;
   string headers = "Content-Type: application/json\r\n";

   ResetLastError();
   int status = WebRequest("POST", apiUrl, headers, timeoutMs, body, response, responseHeaders);

   if(status == -1)
   {
      validation.comment = "WebRequest failed. Add API URL in MT5 options.";
      return validation;
   }

   string raw = CharArrayToString(response);
   validation.success = status >= 200 && status < 300;
   validation.approved = ExtractJsonBool(raw, "approved");
   validation.score = ExtractJsonDouble(raw, "score");
   validation.comment = ExtractJsonString(raw, "comment");

   if(validation.comment == "")
      validation.comment = raw;

   return validation;
}

#endif

#ifndef MARKET_DATA_EXPORTER_MQH
#define MARKET_DATA_EXPORTER_MQH

//+------------------------------------------------------------------+
//| MarketDataExporter.mqh                                           |
//|                                                                  |
//| Exports OHLCV bars (multi-timeframe), live state and a filtered  |
//| MT5 economic calendar to MQL5/Files/<baseDir>/<symbol_lower>/    |
//| so an external analyst (e.g. Claude) can read the snapshots      |
//| offline. All writes happen in MQL5/Files (no FILE_COMMON).       |
//+------------------------------------------------------------------+

//================== String / array helpers ==========================

string MdeToLower(const string s)
{
   string r = s;
   StringToLower(r);
   return r;
}

string MdeTfLabel(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return "TF";
   }
}

ENUM_TIMEFRAMES MdeTfFromLabel(const string label)
{
   string u = label;
   StringToUpper(u);
   if(u == "M1")  return PERIOD_M1;
   if(u == "M5")  return PERIOD_M5;
   if(u == "M15") return PERIOD_M15;
   if(u == "M30") return PERIOD_M30;
   if(u == "H1")  return PERIOD_H1;
   if(u == "H4")  return PERIOD_H4;
   if(u == "D1")  return PERIOD_D1;
   if(u == "W1")  return PERIOD_W1;
   if(u == "MN1") return PERIOD_MN1;
   return PERIOD_CURRENT;
}

// Splits a comma/space separated list into trimmed non-empty tokens.
int MdeSplit(const string source, const string sep, string &out[])
{
   ArrayResize(out, 0);
   if(source == "") return 0;

   int start = 0;
   int sepLen = StringLen(sep);
   int sLen = StringLen(source);

   while(start <= sLen)
   {
      int idx = StringFind(source, sep, start);
      string token = (idx < 0)
         ? StringSubstr(source, start)
         : StringSubstr(source, start, idx - start);

      StringTrimLeft(token);
      StringTrimRight(token);

      if(token != "")
      {
         int n = ArraySize(out);
         ArrayResize(out, n + 1);
         out[n] = token;
      }

      if(idx < 0) break;
      start = idx + sepLen;
   }

   return ArraySize(out);
}

string MdeJsonEscape(const string s)
{
   string r = s;
   StringReplace(r, "\\", "\\\\");
   StringReplace(r, "\"", "\\\"");
   StringReplace(r, "\r", " ");
   StringReplace(r, "\n", " ");
   StringReplace(r, "\t", " ");
   return r;
}

// Calendar values are stored as long*1e6, with LONG_MIN/MAX meaning "no value".
string MdeCalendarValueStr(long raw)
{
   if(raw == LONG_MIN || raw == LONG_MAX) return "null";
   return DoubleToString((double)raw / 1000000.0, 4);
}

//================== OHLCV CSV export ===============================

// Writes <baseDir>/<symbol_lower>/<tf_lower>.csv with `barsCount` recent
// bars (chronological, oldest first). Returns true on success.
bool MdeExportBars(const string symbol, ENUM_TIMEFRAMES tf, int barsCount, const string baseDir)
{
   if(!SymbolSelect(symbol, true))
   {
      PrintFormat("[MDE] SymbolSelect failed: %s err=%d", symbol, GetLastError());
      return false;
   }

   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   int copied = CopyRates(symbol, tf, 0, barsCount, rates);
   if(copied <= 0)
   {
      PrintFormat("[MDE] CopyRates(%s,%s) failed err=%d", symbol, MdeTfLabel(tf), GetLastError());
      return false;
   }

   string path = baseDir + "/" + MdeToLower(symbol) + "/" + MdeToLower(MdeTfLabel(tf)) + ".csv";

   int h = FileOpen(path, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ, ',');
   if(h == INVALID_HANDLE)
   {
      PrintFormat("[MDE] FileOpen failed: %s err=%d", path, GetLastError());
      return false;
   }

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   FileWrite(h, "time", "open", "high", "low", "close", "tick_volume", "spread", "real_volume");

   // Iterate from oldest to newest so the file is naturally chronological.
   for(int i = copied - 1; i >= 0; i--)
   {
      FileWrite(
         h,
         TimeToString(rates[i].time, TIME_DATE | TIME_SECONDS),
         DoubleToString(rates[i].open,  digits),
         DoubleToString(rates[i].high,  digits),
         DoubleToString(rates[i].low,   digits),
         DoubleToString(rates[i].close, digits),
         (string)rates[i].tick_volume,
         (string)rates[i].spread,
         (string)rates[i].real_volume
      );
   }

   FileClose(h);
   return true;
}

//================== Live state JSON ================================

bool MdeExportState(const string symbol, const string baseDir, const string profile)
{
   if(!SymbolSelect(symbol, true)) return false;

   double bid    = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double spreadPts = (point > 0.0) ? (ask - bid) / point : 0.0;

   string path = baseDir + "/" + MdeToLower(symbol) + "/state.json";

   int h = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI, 0, CP_UTF8);
   if(h == INVALID_HANDLE)
   {
      PrintFormat("[MDE] FileOpen state failed: %s err=%d", path, GetLastError());
      return false;
   }

   string json = "{\n";
   json += "  \"symbol\": \""        + MdeJsonEscape(symbol) + "\",\n";
   json += "  \"profile\": \""       + MdeJsonEscape(profile) + "\",\n";
   json += "  \"server_time\": \""   + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "\",\n";
   json += "  \"bid\": "             + DoubleToString(bid, digits) + ",\n";
   json += "  \"ask\": "             + DoubleToString(ask, digits) + ",\n";
   json += "  \"spread_points\": "   + DoubleToString(spreadPts, 1) + ",\n";
   json += "  \"point\": "           + DoubleToString(point, digits) + ",\n";
   json += "  \"digits\": "          + IntegerToString(digits) + ",\n";
   json += "  \"account_balance\": " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + ",\n";
   json += "  \"account_equity\": "  + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + ",\n";
   json += "  \"open_positions\": "  + IntegerToString(PositionsTotal()) + "\n";
   json += "}\n";

   FileWriteString(h, json);
   FileClose(h);
   return true;
}

//================== Economic calendar JSON =========================

// Exports MT5 economic calendar events for the given currencies, filtered
// to high-importance, in a window of [-lookbehindHours, +lookaheadHours].
bool MdeExportCalendar(
   const string symbol,
   const string &currencies[],
   int lookbehindHours,
   int lookaheadHours,
   const string baseDir
)
{
   datetime now  = TimeCurrent();
   datetime from = now - lookbehindHours * 3600;
   datetime to   = now + lookaheadHours  * 3600;

   string path = baseDir + "/" + MdeToLower(symbol) + "/calendar.json";

   int h = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI, 0, CP_UTF8);
   if(h == INVALID_HANDLE)
   {
      PrintFormat("[MDE] FileOpen calendar failed: %s err=%d", path, GetLastError());
      return false;
   }

   string json = "{\n";
   json += "  \"symbol\": \""        + MdeJsonEscape(symbol) + "\",\n";
   json += "  \"generated_at\": \""  + TimeToString(now, TIME_DATE | TIME_SECONDS) + "\",\n";
   json += "  \"window_from\": \""   + TimeToString(from, TIME_DATE | TIME_SECONDS) + "\",\n";
   json += "  \"window_to\": \""     + TimeToString(to,   TIME_DATE | TIME_SECONDS) + "\",\n";
   json += "  \"filter_currencies\": [";
   for(int c = 0; c < ArraySize(currencies); c++)
   {
      if(c > 0) json += ", ";
      json += "\"" + MdeJsonEscape(currencies[c]) + "\"";
   }
   json += "],\n";
   json += "  \"events\": [\n";

   bool firstEvent = true;
   int  totalEvents = 0;

   for(int c = 0; c < ArraySize(currencies); c++)
   {
      MqlCalendarValue values[];
      ResetLastError();
      int n = CalendarValueHistory(values, from, to, NULL, currencies[c]);
      if(n <= 0) continue;

      for(int i = 0; i < n; i++)
      {
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[i].event_id, ev)) continue;
         if(ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;

         if(!firstEvent) json += ",\n";
         firstEvent = false;
         totalEvents++;

         json += "    {";
         json += "\"time\": \""       + TimeToString(values[i].time, TIME_DATE | TIME_SECONDS) + "\", ";
         json += "\"currency\": \""   + MdeJsonEscape(currencies[c]) + "\", ";
         json += "\"name\": \""       + MdeJsonEscape(ev.name) + "\", ";
         json += "\"importance\": \"high\", ";
         json += "\"forecast\": "     + MdeCalendarValueStr(values[i].forecast_value) + ", ";
         json += "\"prev\": "         + MdeCalendarValueStr(values[i].prev_value)     + ", ";
         json += "\"actual\": "       + MdeCalendarValueStr(values[i].actual_value);
         json += "}";
      }
   }

   json += "\n  ],\n";
   json += "  \"events_count\": " + IntegerToString(totalEvents) + ",\n";
   json += "  \"note\": \"MT5 calendar covers macro economic events only. Crypto-specific catalysts (ETF flows, on-chain metrics, regulatory news) are NOT included and must be sourced separately by the analyst.\"\n";
   json += "}\n";

   FileWriteString(h, json);
   FileClose(h);
   return true;
}

//================== Top-level orchestration ========================

// Exports bars (all requested timeframes) + state + calendar for one symbol.
// `calendarCurrencies` is the list of currencies to filter calendar events on.
bool MdeExportSymbol(
   const string symbol,
   const string &timeframeLabels[],
   int barsCount,
   const string &calendarCurrencies[],
   int calendarLookbehindHours,
   int calendarLookaheadHours,
   const string baseDir,
   const string profile
)
{
   bool ok = true;

   for(int i = 0; i < ArraySize(timeframeLabels); i++)
   {
      ENUM_TIMEFRAMES tf = MdeTfFromLabel(timeframeLabels[i]);
      if(tf == PERIOD_CURRENT)
      {
         PrintFormat("[MDE] Unknown timeframe label '%s', skipped.", timeframeLabels[i]);
         continue;
      }
      if(!MdeExportBars(symbol, tf, barsCount, baseDir)) ok = false;
   }

   if(!MdeExportState(symbol, baseDir, profile)) ok = false;
   if(!MdeExportCalendar(symbol, calendarCurrencies, calendarLookbehindHours, calendarLookaheadHours, baseDir)) ok = false;

   return ok;
}

// Resolves the calendar currency filter based on the symbol type.
// XAU: USD/EUR/GBP/CHF (drivers via DXY and yields).
// BTC: USD only (macro Fed/CPI/NFP).
// Other: USD as a sensible default.
void MdeResolveCalendarCurrencies(const string symbol, string &out[])
{
   ArrayResize(out, 0);

   string u = symbol;
   StringToUpper(u);

   bool isBtc = (StringFind(u, "BTC") >= 0) || (StringFind(u, "XBT") >= 0);
   bool isXau = (StringFind(u, "XAU") >= 0) || (StringFind(u, "GOLD") >= 0);

   if(isXau)
   {
      ArrayResize(out, 4);
      out[0] = "USD"; out[1] = "EUR"; out[2] = "GBP"; out[3] = "CHF";
      return;
   }

   if(isBtc)
   {
      ArrayResize(out, 1);
      out[0] = "USD";
      return;
   }

   ArrayResize(out, 1);
   out[0] = "USD";
}

// Writes a top-level meta.json describing the snapshot.
bool MdeWriteMeta(
   const string baseDir,
   const string &symbols[],
   const string &timeframes[],
   int barsCount,
   const string eaName,
   const string eaVersion
)
{
   string path = baseDir + "/meta.json";

   int h = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI, 0, CP_UTF8);
   if(h == INVALID_HANDLE)
   {
      PrintFormat("[MDE] FileOpen meta failed: %s err=%d", path, GetLastError());
      return false;
   }

   string json = "{\n";
   json += "  \"updated_at\": \"" + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "\",\n";
   json += "  \"ea_name\": \""    + MdeJsonEscape(eaName) + "\",\n";
   json += "  \"ea_version\": \"" + MdeJsonEscape(eaVersion) + "\",\n";
   json += "  \"bars_per_file\": " + IntegerToString(barsCount) + ",\n";
   json += "  \"symbols\": [";
   for(int i = 0; i < ArraySize(symbols); i++)
   {
      if(i > 0) json += ", ";
      json += "\"" + MdeJsonEscape(symbols[i]) + "\"";
   }
   json += "],\n";
   json += "  \"timeframes\": [";
   for(int i = 0; i < ArraySize(timeframes); i++)
   {
      if(i > 0) json += ", ";
      json += "\"" + MdeJsonEscape(timeframes[i]) + "\"";
   }
   json += "]\n";
   json += "}\n";

   FileWriteString(h, json);
   FileClose(h);
   return true;
}

#endif // MARKET_DATA_EXPORTER_MQH

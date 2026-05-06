#ifndef TRADE_MANAGER_MQH
#define TRADE_MANAGER_MQH

#include <Trade/Trade.mqh>
#include "GoldSignalEngine.mqh"

CTrade trade;

bool HasOpenTrade(int magicNumber)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == magicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            return true;
         }
      }
   }

   return false;
}

bool HasPendingOrder(int magicNumber)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);

      if(OrderSelect(ticket))
      {
         if(OrderGetInteger(ORDER_MAGIC) == magicNumber &&
            OrderGetString(ORDER_SYMBOL) == _Symbol)
         {
            return true;
         }
      }
   }

   return false;
}

bool HasActiveTradeOrOrder(int magicNumber)
{
   return HasOpenTrade(magicNumber) || HasPendingOrder(magicNumber);
}

bool OpenSignalTrade(const SignalResult &signal, double lot, int magicNumber, double finalTPMultiplier)
{
   if(signal.action == SIGNAL_WAIT)
      return false;

   if(HasActiveTradeOrOrder(magicNumber))
      return false;

   trade.SetExpertMagicNumber(magicNumber);

   double finalTP = signal.tp1;

   if(signal.action == SIGNAL_BUY || signal.action == SIGNAL_BUY_LIMIT)
      finalTP = signal.entry + MathAbs(signal.entry - signal.sl) * finalTPMultiplier;

   if(signal.action == SIGNAL_SELL || signal.action == SIGNAL_SELL_LIMIT)
      finalTP = signal.entry - MathAbs(signal.entry - signal.sl) * finalTPMultiplier;

   bool result = false;

   if(signal.action == SIGNAL_BUY)
      result = trade.Buy(lot, _Symbol, 0, signal.sl, finalTP);

   else if(signal.action == SIGNAL_SELL)
      result = trade.Sell(lot, _Symbol, 0, signal.sl, finalTP);

   else if(signal.action == SIGNAL_BUY_LIMIT)
      result = trade.BuyLimit(lot, signal.entry, _Symbol, signal.sl, finalTP);

   else if(signal.action == SIGNAL_SELL_LIMIT)
      result = trade.SellLimit(lot, signal.entry, _Symbol, signal.sl, finalTP);

   return result;
}

void ManageBreakEven(int magicNumber)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != magicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(type == POSITION_TYPE_BUY)
      {
         double halfway = openPrice + ((currentTP - openPrice) * 0.5);

         if(bid >= halfway && currentSL < openPrice)
         {
            trade.PositionModify(ticket, openPrice, currentTP);
         }
      }

      if(type == POSITION_TYPE_SELL)
      {
         double halfway = openPrice - ((openPrice - currentTP) * 0.5);

         if(ask <= halfway && (currentSL > openPrice || currentSL == 0))
         {
            trade.PositionModify(ticket, openPrice, currentTP);
         }
      }
   }
}

#endif

#ifndef RISK_MANAGER_MQH
#define RISK_MANAGER_MQH

double CalculateLotSize(double entryPrice, double stopLoss, double riskPercent)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(balance <= 0 || riskPercent <= 0)
      return 0.01;

   double riskMoney = balance * (riskPercent / 100.0);

   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0 || tickValue <= 0)
      return 0.01;

   double slDistance = MathAbs(entryPrice - stopLoss);

   if(slDistance <= 0)
      return 0.01;

   double ticks = slDistance / tickSize;
   double costPerLot = ticks * tickValue;

   if(costPerLot <= 0)
      return 0.01;

   double lot = riskMoney / costPerLot;

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(minLot, MathMin(lot, maxLot));

   return NormalizeDouble(lot, 2);
}

#endif
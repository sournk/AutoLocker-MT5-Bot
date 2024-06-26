//+------------------------------------------------------------------+
//|                                           AutoLocker-MT5-Bot.mq5 |
//|                                                  Denis Kislitsyn |
//|                                             https://kislitsyn.me |
//+------------------------------------------------------------------+

#include <Arrays\ArrayLong.mqh>
#include <Arrays\ArrayDouble.mqh>

#include <Trade\AccountInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>

#include "Include\DKStdLib\Common\DKStdLib.mqh"
#include "Include\DKStdLib\Logger\DKLogger.mqh"

#include "CTesterMock.mqh"

#property script_show_inputs

input  group               "1. LOCK ACTIVATION SETTINGS"
input  bool                InpLASEnabled                     = false;                            // 1.LAS.E: Locking Enabled?
input  double              InpLASLoss                        = 100.0;                            // 1.LAS.L: Max Loss Sum to Activate
input  bool                InpLASCloseCharts                 = true;                             // 1.LAS.CC: Close other Charts on lock

input  group               "2. TESTER MODE"
input  bool                InpTMMockEnabled                  = false;                            // 2.TM.MCK: Enabled Mock Pos
input  datetime            InpTMPOS1Time                     = D'2024.04.25 11:00';              // 2.TM.P1T: Pos 1: Time
input  ENUM_POSITION_TYPE  InpTMPOS1Type                     = POSITION_TYPE_BUY;                // 2.TM.P1D: Pos 1: Dir
input  double              InpTMPOS1Lot                      = 1.0;                              // 2.TM.P1L: Pos 1: Lot
input  datetime            InpTMPOS2Time                     = D'2024.04.25 12:00';              // 2.TM.P2T: Pos 2: Time
input  ENUM_POSITION_TYPE  InpTMPOS2Type                     = POSITION_TYPE_BUY;                // 2.TM.P2D: Pos 2: Dir
input  double              InpTMPOS2Lot                      = 2.0;                              // 2.TM.P2L: Pos 2: Lot
input  datetime            InpTMPOS3Time                     = D'2024.04.25 13:00';              // 2.TM.P3T: Pos 3: Time
input  ENUM_POSITION_TYPE  InpTMPOS3Type                     = POSITION_TYPE_BUY;                // 2.TM.P3D: Pos 3: Dir
input  double              InpTMPOS3Lot                      = 3.0;                              // 2.TM.P3L: Pos 3: Lot
input  datetime            InpTMLockActivation               = D'2024.04.25 15:45';              // 2.TM.LAT: Lock Activation Time

input  group               "10. MISC"
sinput LogLevel            InpLL                             = LogLevel(INFO);                   // 10.LL: Log Level
sinput int                 InpMGC                            = 20240506;                         // 10.MGC: Magic
       int                 InpAUP                            = 32*24*60*60;                      // 10.AUP: Allowed usage period, sec
       string              InpGP                             = "AL";                             // 10.GP: Global Prefix


enum ENUM_LOCK_STEP {
  LOCK_STEP_WAITING_LOSS_LIMIT,   // Waiting Max Loss Limit
  LOCK_STEP_LOCKING,              // Locking
  LOCK_STEP_LOCKED,               // Locked
  LOCK_STEP_LOCKED_CHARTS_CLOSED  // Locked And All Charts Closed
};



CAccountInfo               acc;
DKLogger                   logger;

CArrayLong                 base_orders_to_lock;

ENUM_LOCK_STEP             curr_step;
double                     loss_locked;

CTesterMock                tester_mock;

bool                       lock_enabled;



void ShowComment() {
  string text = StringFormat("MODE: %s" + "\n" +
                             "LOSS CURRENT: %.0f %s %.0f" + "\n" +
                             "LOSS LOCKED: %.0f",
                             (lock_enabled) ? EnumToString(curr_step) : "Disabled",
                             (acc.Profit() < 0.0) ? -1*acc.Profit() : 0,
                             (-1*acc.Profit() >= InpLASLoss) ? ">=" : "<",
                             InpLASLoss,
                             loss_locked
                             );

  Comment(text);
}

//+------------------------------------------------------------------+
//| Open opposite position
//+------------------------------------------------------------------+
ulong Trade(CPositionInfo& _pos) {
  CTrade trade;
  trade.SetExpertMagicNumber(InpMGC);
  trade.SetMarginMode();
  trade.SetTypeFillingBySymbol(_pos.Symbol());
  //trade.SetDeviationInPoints(InpSLP); 

  bool openRes = false;
  string comment = StringFormat("%s:%I64u|%.0f|%.0f",
                                logger.Name,
                                _pos.Ticket(),
                                _pos.Volume(),
                                _pos.Profit()
                                );    
  
  double sl  = 0.0;
  double tp  = 0.0;
  double lot = _pos.Volume();
  
  if (_pos.PositionType() == POSITION_TYPE_BUY)
    openRes = trade.Sell(lot, _pos.Symbol(), 0, sl, tp, comment);
    
  if (_pos.PositionType() == POSITION_TYPE_SELL)
    openRes = trade.Buy(lot, _pos.Symbol(), 0, sl, tp, comment);    
  
  if(openRes) {
    ulong ticket = trade.ResultDeal();
    if(ticket != 0) {
      ulong order = trade.ResultOrder();
      double order_open_price = trade.RequestPrice();
      logger.Warn(StringFormat("Lock pos open: BASE_POS=%I64u/%s; %LOCK_POS=%I64u/%s; LOCK_LOT=%f; LOCK_SL=%f; LOCK_TP=%f",
                               _pos.Ticket(),
                               (_pos.PositionType() == POSITION_TYPE_BUY) ? "BUY" : "SELL",
                               ticket,
                               (_pos.PositionType() == POSITION_TYPE_BUY) ? "SELL" : "BUY",
                               lot,
                               sl,
                               tp
                               ), true);

      return ticket;
    }
  }

  logger.Error(StringFormat("Lock pos open error: RETCODE=%d; BASE_POS=%I64u/%s; LOCK_LOT=%f; LOCK_SL=%f; LOCK_TP=%f",
                            trade.ResultRetcode(),
                            _pos.Ticket(),
                            (_pos.PositionType() == POSITION_TYPE_BUY) ? "BUY" : "SELL",
                            lot,
                            sl,
                            tp
                            ), true);

  return(0);
}

//+------------------------------------------------------------------+
//| Open lock pos for every pos with loss
//+------------------------------------------------------------------+
void Lock() {
  CPositionInfo pos;
  int i = 0;
  while (i<base_orders_to_lock.Total()){
    // No such pos
    if (!pos.SelectByTicket(base_orders_to_lock.At(i))) {
      base_orders_to_lock.Delete(i);
      continue;
    }
    
    // Lock pos opened 
    if (Trade(pos) > 0) {
      base_orders_to_lock.Delete(i);
      continue;
    }
    
    i++;
  }
}

//+------------------------------------------------------------------+
//| Open lock pos for every pos with loss
//+------------------------------------------------------------------+
void FindPosToLock() {
  CPositionInfo pos;
  
  for (int i=0; i<PositionsTotal(); i++){
    if (pos.SelectByIndex(i) <= 0) continue;
    
    if (base_orders_to_lock.Search(pos.Ticket()) < 0)
      base_orders_to_lock.Add(pos.Ticket());
  }
}

ulong FindPosWithProfit(const int _max) {
  CPositionInfo pos;
  double profit = 0.0;
  ulong  ticket = 0;
    
  for (int i=0; i<PositionsTotal(); i++) {
    if (!pos.SelectByIndex(i)) continue;
    
    if (_max > 0) 
      if (pos.Profit() > 0 && pos.Profit() > profit) {
        ticket = pos.Ticket();
        profit = pos.Profit();
      }
      
    if (_max < 0) 
      if (pos.Profit() < 0 && pos.Profit() < profit) {
        ticket = pos.Ticket();
        profit = pos.Profit();
      }      
  }
  
  return ticket;
}

uint CloseCharts() {
  CArrayLong charts_id_to_close;
  
  long id = ChartFirst();
  while (id >= 0) {
    if (id != ChartID()) 
      charts_id_to_close.Add(id);
    id = ChartNext(id);
  }
  
  for (int i=0; i<charts_id_to_close.Total(); i++) {
    id = charts_id_to_close.At(i);
    ChartClose(charts_id_to_close.At(i));
    logger.Info(StringFormat("Chart closed: ID=%I64u; SYM=%s; PERIOD=%s",
                             id,
                             ChartSymbol(id),
                             TimeframeToString(ChartPeriod(id))), true);
  }

  return 0;
}

//bool ClosePosProfitProportion(const ulong _pos_ticket_to_close, const double _sum) {
//  CPositionInfo pos;
//  if (!pos.SelectByTicket(_pos_ticket_to_close)) return;
//  
//  CTrade trade;
//  trade.SetExpertMagicNumber(InpMGC);
//  trade.SetMarginMode();
//  trade.SetTypeFillingBySymbol(pos.Symbol());
//  //trade.SetDeviationInPoints(InpSLP);
//
//  if (MathAbs(pos.Profit()) > MathAbs(_sum)) {
//    double vol = MathAbs(_sum * pos.Volume() / pos.Profit());
//    double vol_norm = NormalizeLot(pos.Symbol(), vol);
//    
//    // Can close only if normilised vol <= vol calced for availibale profit
//    if (vol_norm > 0.0 && vol_norm <= vol)
//      trade.PositionClosePartial(pos.Ticket(), vol);
//  }
//  else
//    trade.PositionClose(_pos_ticket_to_close);
//}

////+------------------------------------------------------------------+
////| Partial 
////+------------------------------------------------------------------+
//void Unlock() {
//  CPositionInfo pos;
//  
//  ulong  max_profit_ticket = FindPosWithProfit(+1);
//  ulong  max_loss_ticket   = FindPosWithProfit(-1);
//  double max_profit = 0.0;
//  double max_loss   = 0.0;
//  
//  // No any pos with profit
//  if (max_profit_ticket <= 0) return; 
//  if (!pos.SelectByTicket(max_profit_ticket)) return;
//  max_profit = pos.Profit();
//  
//  if (max_loss_ticket > 0) {
//    if (!pos.SelectByTicket(max_loss_ticket)) return; 
//    max_loss = -1*pos.Profit(); 
//    
//    logger.Debug(StringFormat("%s/%d: PROFIT=%I64u/%.0f; LOSS=%I64u/%.0f",
//                              __FUNCTION__, __LINE__,
//                              max_profit_ticket, max_profit,
//                              max_loss_ticket, -1*max_loss
//                              ));
//  
//  
//    if (max_profit >= max_loss) {
//      ClosePosProfitProportion(max_loss_ticket, max_loss);     // Full close
//      ClosePosProfitProportion(max_profit_ticket, max_loss);   // Partial close
//    }
//    else {
//      ClosePosProfitProportion(max_profit_ticket, max_profit); // Full close
//      ClosePosProfitProportion(max_loss_ticket, max_profit);   // Partial close
//    }
//  }
//  else {
//    logger.Debug(StringFormat("%s/%d: PROFIT=%I64u/%.0f",
//                                  __FUNCTION__, __LINE__,
//                                  max_profit_ticket, max_profit
//                              ));  
//    ClosePosProfitProportion(max_profit_ticket, max_profit); // Full close
//  }    
//}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
  // Logger init
  logger.Name   = InpGP;
  logger.Level  = InpLL;
  logger.Format = "%name%:[%level%] %message%";
  
  base_orders_to_lock.Clear();
  
  curr_step = LOCK_STEP_WAITING_LOSS_LIMIT;
  loss_locked  = 0.0;
  lock_enabled = InpLASEnabled;  
  if(InpTMMockEnabled && MQL5InfoInteger(MQL5_DEBUGGING)) 
    lock_enabled = false;    
  
  tester_mock.Add(InpTMPOS1Time, Symbol(), InpTMPOS1Type, InpTMPOS1Lot);
  tester_mock.Add(InpTMPOS2Time, Symbol(), InpTMPOS2Type, InpTMPOS2Lot);
  tester_mock.Add(InpTMPOS3Time, Symbol(), InpTMPOS3Type, InpTMPOS3Lot);
  
  ShowComment();
  EventSetTimer(5);
  
  return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
  Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
  if(InpTMMockEnabled && MQL5InfoInteger(MQL5_DEBUGGING)) {
    tester_mock.CheckTimeAndOpenPos();
    if (TimeCurrent() >= InpTMLockActivation) lock_enabled = true;
  }

  if (lock_enabled) {
    if (curr_step == LOCK_STEP_WAITING_LOSS_LIMIT)
      if (-1*acc.Profit() >= InpLASLoss) {
        FindPosToLock();    
        if (base_orders_to_lock.Total() > 0) {
          curr_step = LOCK_STEP_LOCKING;
          loss_locked = acc.Profit();
        }
      }
      
    if (curr_step == LOCK_STEP_LOCKING) {    
      Lock();
      if (base_orders_to_lock.Total() <= 0)
        curr_step = LOCK_STEP_LOCKED;
    }
    
    if (curr_step == LOCK_STEP_LOCKED) {   
      if (InpLASCloseCharts) CloseCharts();
      curr_step = LOCK_STEP_LOCKED_CHARTS_CLOSED; 
    }    
  }
}
//+------------------------------------------------------------------+
//| OnTimer                                                   |
//+------------------------------------------------------------------+
void OnTimer() {
  ShowComment();
}
//+------------------------------------------------------------------+
//| Trade function                                                   |
//+------------------------------------------------------------------+
void OnTrade() {

}
//+------------------------------------------------------------------+
//| TradeTransaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result) {
}

#include <Trade\Trade.mqh>

struct PosToOpen {
  datetime                   Time;
  string                     Sym;
  ENUM_POSITION_TYPE         Dir;
  double                     Lot;
};

class CTesterMock {
private:
  PosToOpen                  pos_arr[];
public:
  int                        CTesterMock::Add(const datetime _dt, const string _sym, const ENUM_POSITION_TYPE _dir, const double _lot);
  int                        CTesterMock::CheckTimeAndOpenPos(datetime _dt = 0);
};

int CTesterMock::Add(const datetime _dt, const string _sym, const ENUM_POSITION_TYPE _dir, const double _lot) {
  ArrayResize(pos_arr, ArraySize(pos_arr)+1);
  
  PosToOpen pos;
  pos.Time = _dt;
  pos.Sym  = _sym;
  pos.Dir  = _dir;
  pos.Lot  = _lot;
  pos_arr[ArraySize(pos_arr)-1] = pos;
  
  return ArraySize(pos_arr);
}

int CTesterMock::CheckTimeAndOpenPos(datetime _dt = 0) {
  CTrade trade;
  //trade.SetExpertMagicNumber(InpMGC);
  trade.SetMarginMode();
  //trade.SetTypeFillingBySymbol(_pos.Symbol());
  //trade.SetDeviationInPoints(InpSLP);
  
  if (_dt == 0) _dt = TimeCurrent();
  
  int i=0;
  while (i<ArraySize(pos_arr)) {
    if (pos_arr[i].Time <= _dt) {
      trade.SetTypeFillingBySymbol(pos_arr[i].Sym);
      if (pos_arr[i].Dir == POSITION_TYPE_BUY) {
        trade.Buy(pos_arr[i].Lot, pos_arr[i].Sym);
        ArrayRemove(pos_arr, i, 1);
        continue;
      }
      if (pos_arr[i].Dir == POSITION_TYPE_SELL) {
        trade.Sell(pos_arr[i].Lot, pos_arr[i].Sym);        
        ArrayRemove(pos_arr, i, 1);
        continue;
      }
    }
    i++;
  }
  
  return 0;
}
//+------------------------------------------------------------------+
//|                                                CDKSymbolInfo.mqh |
//|                                                  Denis Kislitsyn |
//|                                             https://kislitsyn.me |
//+------------------------------------------------------------------+
#property copyright "Denis Kislitsyn"
#property link      "https://kislitsyn.me"

#include <Trade\SymbolInfo.mqh>

class CDKSymbolInfo : public CSymbolInfo {
private:
  double              GetMockValue(const string _name);
public:
  void                CDKSymbolInfo();
  void                ~CDKSymbolInfo();

  int                 PriceToPoints(const double aPrice);                              // Convert aPrice to price value for current Symbol
  double              PointsToPrice(const int aPoint);                                 // Convert aPoint to points for current Symbol
  
  double              GetPriceToOpen(const ENUM_POSITION_TYPE aPositionDirection);     // Returns market price Ask or Bid to OPEN new pos with aPositionDirection dir
  double              GetPriceToClose(const ENUM_POSITION_TYPE aPositionDirection);    // Returns market price Ask or Bid to CLOSE new pos with aPositionDirection dir
  
  double              NormalizeLot(double lot, const bool _floor = true);              // Returns normalized lots size for symbol
  
  double              Ask();
  void                AskMockSet(const double _value);
  void                AskMockRemove();
  
  double              Bid();
  void                BidMockSet(const double _value);
  void                BidMockRemove();
  
  void                MockTimeSet(const datetime _dt, const ENUM_SERIESMODE _series_mode);
  void                MockTimeRemove();
  
  void                MockRemoveAll();
};

void CDKSymbolInfo::CDKSymbolInfo() {
  MockRemoveAll();
}

void CDKSymbolInfo::~CDKSymbolInfo() {
  MockRemoveAll();
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Price Operations
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Convert aPrice to price value for current Symbol                 |
//+------------------------------------------------------------------+
int CDKSymbolInfo::PriceToPoints(const double aPrice) {
  RefreshRates();
  
  int dig = Digits();
  int dig2 = this.Digits();
  
  return((int)(aPrice * MathPow(10, Digits())));
}

//+------------------------------------------------------------------+
//| Convert aPoint to points for current Symbol                      |
//+------------------------------------------------------------------+
double CDKSymbolInfo::PointsToPrice(const int aPoint) {
  RefreshRates();
  
  return(NormalizeDouble(aPoint * this.Point(), this.Digits()));
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Market Price Operations
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+

double CDKSymbolInfo::GetPriceToOpen(const ENUM_POSITION_TYPE aPositionDirection) {
  RefreshRates();
  
  if (aPositionDirection == POSITION_TYPE_BUY)  return Ask();
  if (aPositionDirection == POSITION_TYPE_SELL) return Bid();
  return 0;   
}

double CDKSymbolInfo::GetPriceToClose(const ENUM_POSITION_TYPE aPositionDirection) {
  RefreshRates();
  
  if (aPositionDirection == POSITION_TYPE_BUY)  return Bid();
  if (aPositionDirection == POSITION_TYPE_SELL) return Ask();
  return 0;   
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Lots Size Operations
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+

double CDKSymbolInfo::NormalizeLot(double lot, const bool _floor = true) {
  RefreshRates();
  
  lot =  NormalizeDouble(lot, Digits());
  double lotStep = LotsStep();
  if (_floor) return floor(lot / lotStep) * lotStep;
  return round(lot / lotStep) * lotStep;
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Market data can be mocked by global variable for testing
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+

double CDKSymbolInfo::GetMockValue(const string _name) {
  if (GlobalVariableCheck(_name)) {
    double global_value = GlobalVariableGet(_name);
    if (global_value > 0) return global_value;
  }
  
  if (GlobalVariableCheck("CDKSymbolInfo::MockTime_dt")) {
    datetime dt = (datetime)GlobalVariableGet("CDKSymbolInfo::MockTime_dt");
    int mode = (ENUM_SERIESMODE)GlobalVariableGet("CDKSymbolInfo::MockTime_series_mode");
    
    int bar_shift = iBarShift(Name(), PERIOD_M1, dt);
    if (mode == MODE_OPEN)  return iOpen(Name(),  PERIOD_M1, bar_shift);
    if (mode == MODE_CLOSE) return iClose(Name(), PERIOD_M1, bar_shift);
    if (mode == MODE_HIGH)  return iHigh(Name(),  PERIOD_M1, bar_shift);
    if (mode == MODE_LOW)   return iLow(Name(),   PERIOD_M1, bar_shift);
  }
  
  return 0;
}

double CDKSymbolInfo::Ask() {
  double global_value = GetMockValue("CDKSymbolInfo::Ask");
  if (global_value > 0) return global_value;
  
  return CSymbolInfo::Ask();      
}

void CDKSymbolInfo::AskMockSet(const double _value) {
  GlobalVariableSet("CDKSymbolInfo::Ask", _value);  
}

void CDKSymbolInfo::AskMockRemove() {
  GlobalVariableDel("CDKSymbolInfo::Ask");
}

double CDKSymbolInfo::Bid() {
  double global_value = GetMockValue("CDKSymbolInfo::Bid");
  if (global_value > 0) return global_value;
  
  return CSymbolInfo::Bid();      
}

void CDKSymbolInfo::BidMockSet(const double _value) {
  GlobalVariableSet("CDKSymbolInfo::Bid", _value);  
}

void CDKSymbolInfo::BidMockRemove() {
  GlobalVariableDel("CDKSymbolInfo::Bid");
}

void CDKSymbolInfo::MockRemoveAll() {
  AskMockRemove();
  BidMockRemove();
  
  MockTimeRemove();
}

void CDKSymbolInfo::MockTimeSet(const datetime _dt, const ENUM_SERIESMODE _series_mode) {
  GlobalVariableSet("CDKSymbolInfo::MockTime_dt", _dt); 
  GlobalVariableSet("CDKSymbolInfo::MockTime_series_mode", _series_mode);
}

void CDKSymbolInfo::MockTimeRemove() {
  GlobalVariableDel("CDKSymbolInfo::MockTime_dt");
  GlobalVariableDel("CDKSymbolInfo::MockTime_series_mode");
}
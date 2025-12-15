# Routes Refactoring Review & Verification

## Summary
This document reviews the refactoring of routes to use Rails RESTful conventions and verifies correct wiring between routes, controllers, views, and JavaScript.

## Routes → Controllers Mapping

### ✅ Verified Routes

1. **Dashboard**
   - `GET /` → `DashboardController#index`
   - `GET /dashboard` → `DashboardController#index`

2. **Positions**
   - `GET /positions` → `PositionsController#index`
   - Route helper: `positions_path`

3. **Portfolio**
   - `GET /portfolio` → `PortfoliosController#show`
   - Route helper: `portfolio_path`
   - Note: Uses singular `resource` (singleton pattern)

4. **Signals**
   - `GET /signals` → `SignalsController#index`
   - Route helper: `signals_path`

5. **Orders**
   - `GET /orders` → `OrdersController#index`
   - Route helper: `orders_path`

6. **Monitoring**
   - `GET /monitoring` → `MonitoringController#index`
   - Route helper: `monitoring_path`

7. **AI Evaluations**
   - `GET /ai-evaluations` → `AiEvaluationsController#index`
   - Route helper: `ai_evaluations_path`
   - Note: Custom path `"ai-evaluations"` for hyphenated URL

8. **Screeners** (Collection Routes)
   - `GET /screeners/swing` → `ScreenersController#swing`
   - Route helper: `swing_screeners_path`
   - `GET /screeners/longterm` → `ScreenersController#longterm`
   - Route helper: `longterm_screeners_path`
   - `POST /screeners/run` → `ScreenersController#run`
   - Route helper: `run_screeners_path`
   - `GET /screeners/check` → `ScreenersController#check_results`
   - Route helper: `check_results_screeners_path`
   - `POST /screeners/ltp/start` → `ScreenersController#start_ltp_updates`
   - Route helper: `start_ltp_updates_screeners_path`
   - `POST /screeners/ltp/stop` → `ScreenersController#stop_ltp_updates`
   - Route helper: `stop_ltp_updates_screeners_path`

9. **Trading Mode**
   - `POST /trading_mode/toggle` → `TradingModeController#toggle`
   - Route helper: `toggle_trading_mode_path`
   - Note: Uses singular `resource` with collection route

## Issues Found & Fixed

### 1. ✅ Fixed: MonitoringController Method Name
**Issue**: `MonitoringController#index` called `get_queue_stats` which doesn't exist.
**Fix**: Changed to `get_solid_queue_stats` from `SolidQueueHelper` concern.
**File**: `app/controllers/monitoring_controller.rb`

### 2. ✅ Fixed: PortfoliosController Model Inconsistency
**Issue**: Used `PaperPortfolio` model which has different associations than what dashboard uses.
**Fix**: Updated to use `CapitalAllocationPortfolio` for consistency with dashboard, and unified `Position` model for positions.
**File**: `app/controllers/portfolios_controller.rb`

### 3. ✅ Verified: Controller Includes
All controllers properly include required concerns:
- `ApplicationController` includes `TradingModeHelper` and `SolidQueueHelper`
- `ScreenersController` includes `SolidQueueHelper`
- `MonitoringController` includes `SolidQueueHelper`
- `TradingModeController` includes `TradingModeHelper`
- `DashboardController` includes `BalanceHelper`

### 4. ✅ Verified: View Files Exist
All view files match controller actions:
- `app/views/positions/index.html.erb` ✓
- `app/views/portfolios/show.html.erb` ✓
- `app/views/signals/index.html.erb` ✓
- `app/views/orders/index.html.erb` ✓
- `app/views/monitoring/index.html.erb` ✓
- `app/views/ai_evaluations/index.html.erb` ✓
- `app/views/screeners/swing.html.erb` ✓
- `app/views/screeners/longterm.html.erb` ✓

### 5. ✅ Verified: Route Helpers in Views
All route helpers are correctly used:
- `positions_path` ✓
- `portfolio_path` ✓
- `signals_path` ✓
- `orders_path` ✓
- `monitoring_path` ✓
- `ai_evaluations_path` ✓
- `swing_screeners_path` ✓
- `longterm_screeners_path` ✓
- `run_screeners_path` ✓
- `check_results_screeners_path` ✓
- `start_ltp_updates_screeners_path` ✓
- `stop_ltp_updates_screeners_path` ✓

### 6. ✅ Verified: JavaScript Routes
JavaScript correctly uses:
- `/trading_mode/toggle` for trading mode toggle ✓

### 7. ✅ Verified: Form Parameters
Screener forms correctly include hidden `type` field:
- Swing screener form includes `type: "swing"` ✓
- Longterm screener form includes `type: "longterm"` ✓

## Controller Actions Verification

### ScreenersController
- ✅ `swing` - Renders view, no JSON response
- ✅ `longterm` - Renders view, no JSON response
- ✅ `run` - Returns JSON, uses `@screener_type` from `before_action`
- ✅ `check_results` - Returns JSON, uses `@screener_type` from `before_action`
- ✅ `start_ltp_updates` - Returns JSON
- ✅ `stop_ltp_updates` - Returns JSON

### PositionsController
- ✅ `index` - Renders view with positions

### PortfoliosController
- ✅ `show` - Renders view with portfolio data
- ✅ `calculate_performance_metrics` - Private helper method

### SignalsController
- ✅ `index` - Renders view with signals

### OrdersController
- ✅ `index` - Renders view with orders

### MonitoringController
- ✅ `index` - Renders view with monitoring data
- ✅ All helper methods properly defined

### AiEvaluationsController
- ✅ `index` - Renders view with AI evaluation data

### TradingModeController
- ✅ `toggle` - Calls concern method, returns JSON/redirect

## Potential Issues to Monitor

1. **Portfolio Model Consistency**: Ensure `CapitalAllocationPortfolio` is always initialized for paper trading mode. The controller now includes initialization logic.

2. **Screener Type Parameter**: The `run` action relies on `@screener_type` being set by `before_action`, which reads from `params[:type]`. Ensure forms always include the `type` hidden field.

3. **SolidQueue Dependencies**: Several controllers depend on SolidQueue being installed. Methods gracefully handle missing SolidQueue, but ensure it's available in production.

4. **DhanHQ API Dependencies**: Some controllers require DhanHQ gem. Ensure proper error handling for missing gem or API failures.

## Testing Recommendations

1. Test all route helpers generate correct URLs
2. Test screener forms submit with correct `type` parameter
3. Test portfolio page works for both live and paper modes
4. Test trading mode toggle updates session correctly
5. Test monitoring page handles missing SolidQueue gracefully
6. Test all JSON endpoints return correct format

## Conclusion

All routes are correctly wired and follow Rails RESTful conventions. The refactoring maintains backward compatibility while improving code organization. All identified issues have been fixed.

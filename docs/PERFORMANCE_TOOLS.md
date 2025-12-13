# Performance Optimization Tools

This project includes two powerful tools for optimizing database queries and request performance:

1. **Bullet** - Detects N+1 queries and unused eager loading
2. **Rack Mini Profiler** - Profiles requests and shows query performance

## Bullet - N+1 Query Detection

Bullet helps identify and fix N+1 query problems in your Rails application.

### Features

- **N+1 Query Detection**: Alerts when you're making multiple queries instead of eager loading
- **Unused Eager Loading Detection**: Warns when you're loading associations you don't use
- **Counter Cache Detection**: Identifies missing counter caches

### How It Works

Bullet monitors your ActiveRecord queries and displays alerts in:
- **Browser console** (JavaScript alerts)
- **Rails logs** (log/development.log)
- **Terminal** (if running Rails console)

### Example Alert

```
USE eager loading detected
  Instrument => [:candle_series]
  Add to your finder: :includes => [:candle_series]
Call stack
  /app/controllers/dashboard_controller.rb:15:in `index'
```

### Enable/Disable

**Enable (default in development):**
```bash
ENABLE_BULLET=true
```

**Disable:**
```bash
ENABLE_BULLET=false
```

Or set in `.env`:
```bash
ENABLE_BULLET=false
```

### Configuration

Configuration is in `config/initializers/bullet.rb`:
- Alerts enabled in browser console
- Logs to Rails logger
- Detects N+1 queries, unused eager loading, and counter cache issues

---

## Rack Mini Profiler - Request Profiling

Rack Mini Profiler provides detailed performance information for each request.

### Features

- **Request Timing**: See how long each request takes
- **SQL Query Analysis**: View all SQL queries executed during a request
- **Query Timing**: See how long each query takes
- **Memory Usage**: Monitor memory consumption
- **Backtrace**: See where slow queries originate

### How to Use

1. **Start your Rails server:**
   ```bash
   rails server
   ```

2. **Visit any page** in your application

3. **Look for the profiler badge** in the bottom-right corner of the page

4. **Click the badge** to see detailed profiling information:
   - Total request time
   - Database query count and timing
   - View rendering time
   - Memory usage

### Example Output

```
Request: GET /dashboard
Total: 234ms | DB: 156ms (12 queries) | View: 45ms
```

### Enable/Disable

**Enable (default in development):**
```bash
ENABLE_MINI_PROFILER=true
```

**Disable:**
```bash
ENABLE_MINI_PROFILER=false
```

Or set in `.env`:
```bash
ENABLE_MINI_PROFILER=false
```

### Configuration

Configuration is in `config/initializers/rack_mini_profiler.rb`:
- Position: Bottom-right corner
- Skips profiling for: `/assets`, `/favicon.ico`, `/robots.txt`
- Shows advanced debugging tools
- Includes backtraces for slow queries

### Skipped Paths

The profiler automatically skips:
- Asset requests (`/assets/*`)
- Favicon requests
- Robot.txt requests

You can customize skipped paths in `config/initializers/rack_mini_profiler.rb`.

---

## Using Both Tools Together

Both tools work great together:

1. **Bullet** identifies N+1 queries and suggests fixes
2. **Rack Mini Profiler** shows the actual performance impact

### Workflow

1. Load a page and check Bullet alerts in the console
2. Check Rack Mini Profiler to see query timing
3. Fix N+1 queries by adding `.includes()` or `.preload()`
4. Verify improvements in Rack Mini Profiler

### Example Fix

**Before (N+1 query):**
```ruby
# In controller
@instruments = Instrument.limit(10)

# In view
@instruments.each do |instrument|
  instrument.candle_series.count  # N+1 query!
end
```

**Bullet Alert:**
```
N+1 Query detected
  Instrument => [:candle_series]
  Add to your finder: :includes => [:candle_series]
```

**After (Fixed):**
```ruby
# In controller
@instruments = Instrument.includes(:candle_series).limit(10)

# In view
@instruments.each do |instrument|
  instrument.candle_series.count  # No additional query!
end
```

**Rack Mini Profiler shows:**
- Before: 12 queries, 156ms
- After: 2 queries, 23ms

---

## Best Practices

### When to Use

- **During Development**: Always enabled to catch performance issues early
- **During Code Review**: Check for Bullet alerts before merging
- **Performance Debugging**: Use Rack Mini Profiler to identify slow requests

### When to Disable

- **Production**: Never enable in production (security and performance)
- **Heavy Testing**: Disable if profiling slows down test suite
- **CI/CD**: Disable in automated tests

### Tips

1. **Fix N+1 queries immediately** - They can cause significant performance issues
2. **Monitor query count** - Use Rack Mini Profiler to track improvements
3. **Use `.includes()` for associations** - Prevents N+1 queries
4. **Use `.preload()` when you don't need joins** - More efficient than `.includes()`
5. **Use `.eager_load()` when you need joins** - Combines queries efficiently

---

## Troubleshooting

### Bullet not showing alerts

- Check `ENABLE_BULLET=true` in `.env`
- Restart Rails server
- Check browser console (not just logs)
- Verify Bullet is in Gemfile

### Rack Mini Profiler not showing

- Check `ENABLE_MINI_PROFILER=true` in `.env`
- Restart Rails server
- Clear browser cache
- Check that you're in development mode

### Performance impact

Both tools have minimal performance impact in development. If you notice slowdowns:
- Disable when not actively debugging
- Use `ENABLE_BULLET=false` or `ENABLE_MINI_PROFILER=false`

---

## Additional Resources

- [Bullet Gem Documentation](https://github.com/flyerhzm/bullet)
- [Rack Mini Profiler Documentation](https://github.com/MiniProfiler/rack-mini-profiler)
- [Rails Query Optimization Guide](https://guides.rubyonrails.org/active_record_querying.html#eager-loading-associations)

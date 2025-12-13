# Ollama Gem Migration

## What Changed

We've migrated from custom HTTP implementation to using the **`ollama-ai`** gem for better maintainability and reliability.

## Benefits

✅ **Cleaner code** - Uses well-tested gem instead of custom HTTP  
✅ **Better error handling** - Gem handles edge cases  
✅ **Easier maintenance** - Gem updates handle API changes  
✅ **More features** - Access to all Ollama API features  

## Installation

The gem is already added to `Gemfile`:

```ruby
gem "ollama-ai", "~> 1.3"
```

Just run:

```bash
bundle install
```

## Usage (No Changes Required)

The API remains the same - no code changes needed:

```ruby
# Same API as before
result = Ollama::Service.call(
  prompt: "Analyze this trading signal...",
  model: "llama3.2",
  temperature: 0.3
)
```

## What the Gem Provides

The `ollama-ai` gem provides:

- ✅ Chat completions
- ✅ Model listing
- ✅ Health checks
- ✅ Error handling
- ✅ Timeout support
- ✅ Custom base URL support

## Behind the Scenes

The service now uses:

```ruby
require "ollama-ai"

client = Ollama.new(
  credentials: { address: @base_url },
  options: { timeout: @timeout }
)

events = client.chat(
  {
    model: @model,
    messages: [...],
    options: { temperature: @temperature }
  }
)

# Extract final response from events
final_event = events.find { |e| e["done"] == true }
content = final_event.dig("message", "content")
```

Instead of custom HTTP calls.

## Migration Notes

- ✅ **No breaking changes** - API is identical
- ✅ **Same configuration** - Uses same config options
- ✅ **Same caching** - Caching behavior unchanged
- ✅ **Same error handling** - Returns same error format

## Troubleshooting

If you encounter issues:

1. **Make sure gem is installed:**
   ```bash
   bundle install
   ```

2. **Check gem version:**
   ```ruby
   require "ollama-ai"
   puts OllamaAI::VERSION
   ```

3. **Test gem directly:**
   ```ruby
   require "ollama-ai"
   client = OllamaAI::Client.new
   models = client.list_models
   puts models
   ```

## Gem Documentation

- **GitHub**: https://github.com/gbaptista/ollama-ai
- **RubyGems**: https://rubygems.org/gems/ollama-ai

## Alternative Gems

If you prefer a different gem, you can easily switch:

### Option 1: `ruby_llm` (Supports multiple providers)
```ruby
gem "ruby_llm"
```

### Option 2: `ollama-ruby` (Simple)
```ruby
gem "ollama-ruby"
```

The service can be updated to use any of these gems with minimal changes.

# Provider Switching Guide: OpenAI ↔ Ollama

## Overview

The system supports seamless switching between **OpenAI** and **Ollama** providers. You can configure this at multiple levels:

1. **Global** - Set default provider for entire system
2. **Service-level** - Override per service call
3. **Config file** - Set in `config/algo.yml`
4. **Environment variable** - Set via `AI_PROVIDER`

## Configuration Options

### Option 1: Config File (`config/algo.yml`)

```yaml
# Global provider setting
ai:
  provider: ollama  # Options: "openai", "ollama", "auto"

# Or per-service setting
swing_trading:
  ai_ranking:
    provider: ollama  # Overrides global setting
    model: llama3.2   # Ollama model name
```

### Option 2: Environment Variable

```bash
# Set global provider
export AI_PROVIDER=ollama

# Options: "openai", "ollama", "auto"
```

### Option 3: Code-Level (Per Call)

```ruby
# Explicitly use Ollama
result = AI::UnifiedService.call(
  prompt: "Analyze this signal...",
  provider: "ollama",
  model: "llama3.2"
)

# Explicitly use OpenAI
result = AI::UnifiedService.call(
  prompt: "Analyze this signal...",
  provider: "openai",
  model: "gpt-4o-mini"
)

# Auto-detect (tries OpenAI, falls back to Ollama)
result = AI::UnifiedService.call(
  prompt: "Analyze this signal...",
  provider: "auto"
)
```

## Provider Modes

### 1. `provider: "openai"`

Always uses OpenAI API:

```yaml
ai:
  provider: openai

swing_trading:
  ai_ranking:
    model: gpt-4o-mini  # OpenAI model
```

**Requirements:**
- `OPENAI_API_KEY` environment variable must be set
- OpenAI API must be accessible

### 2. `provider: "ollama"`

Always uses Ollama (local):

```yaml
ai:
  provider: ollama

swing_trading:
  ai_ranking:
    model: llama3.2  # Ollama model
```

**Requirements:**
- Ollama server must be running (`ollama serve`)
- Model must be pulled (`ollama pull llama3.2`)

### 3. `provider: "auto"` (Default)

Smart fallback:
1. Tries OpenAI first
2. Falls back to Ollama if OpenAI fails

```yaml
ai:
  provider: auto

swing_trading:
  ai_ranking:
    model: gpt-4o-mini  # Used for OpenAI, Ollama uses config default
```

**Behavior:**
- If `OPENAI_API_KEY` is set → Uses OpenAI
- If OpenAI fails → Falls back to Ollama
- If no `OPENAI_API_KEY` → Uses Ollama directly

## Model Selection

### OpenAI Models

When `provider: "openai"`:
- `gpt-4o-mini` (recommended, cheap)
- `gpt-4o` (better quality, expensive)
- `gpt-4-turbo` (best quality, very expensive)

### Ollama Models

When `provider: "ollama"`:
- `llama3.2` (3B, fast, recommended)
- `llama3.1` (8B, better quality)
- `mistral` (7B, excellent balance)
- `qwen2.5` (7B, great for structured outputs)

**Important:** Make sure the model is pulled:
```bash
ollama pull llama3.2
```

## Examples

### Example 1: Use Ollama Only

```yaml
# config/algo.yml
ai:
  provider: ollama

ollama:
  model: llama3.2
```

```ruby
# In code
result = AI::UnifiedService.call(
  prompt: "Analyze RELIANCE signal",
  # provider defaults to "ollama" from config
  # model defaults to "llama3.2" from config
)
```

### Example 2: Use OpenAI Only

```yaml
# config/algo.yml
ai:
  provider: openai

swing_trading:
  ai_ranking:
    model: gpt-4o-mini
```

```bash
# Set API key
export OPENAI_API_KEY=sk-...
```

### Example 3: Auto-Detect with Fallback

```yaml
# config/algo.yml
ai:
  provider: auto  # Try OpenAI, fallback to Ollama
```

```ruby
# System will:
# 1. Try OpenAI (if API key exists)
# 2. Fall back to Ollama if OpenAI fails
result = AI::UnifiedService.call(
  prompt: "Analyze signal",
  provider: "auto"  # or omit to use config default
)
```

### Example 4: Override Per Call

```ruby
# Force Ollama even if config says OpenAI
result = AI::UnifiedService.call(
  prompt: "Analyze signal",
  provider: "ollama",  # Overrides config
  model: "llama3.1"    # Overrides config
)
```

## Priority Order

Provider selection follows this priority:

1. **Explicit parameter** (`provider: "ollama"` in code)
2. **Service config** (`swing_trading.ai_ranking.provider`)
3. **Global config** (`ai.provider`)
4. **Environment variable** (`AI_PROVIDER`)
5. **Default** (`"auto"`)

## Model Selection Priority

Model selection follows this priority:

1. **Explicit parameter** (`model: "llama3.2"` in code)
2. **Service config** (`swing_trading.ai_ranking.model` for OpenAI, `ollama.model` for Ollama)
3. **Default** (`gpt-4o-mini` for OpenAI, `llama3.2` for Ollama)

## Testing Provider Switching

### Test OpenAI

```ruby
# Rails console
result = AI::UnifiedService.call(
  prompt: "Hello",
  provider: "openai",
  model: "gpt-4o-mini"
)

puts result[:success] ? "✅ OpenAI works" : "❌ Error: #{result[:error]}"
```

### Test Ollama

```ruby
# Rails console
result = AI::UnifiedService.call(
  prompt: "Hello",
  provider: "ollama",
  model: "llama3.2"
)

puts result[:success] ? "✅ Ollama works" : "❌ Error: #{result[:error]}"
```

### Test Auto-Detect

```ruby
# Rails console
result = AI::UnifiedService.call(
  prompt: "Hello",
  provider: "auto"
)

puts "Provider used: #{result[:model] || 'unknown'}"
puts result[:success] ? "✅ Auto-detect works" : "❌ Error: #{result[:error]}"
```

## Common Issues

### Issue: Wrong Model for Provider

**Problem:** Using OpenAI model name with Ollama provider

```ruby
# ❌ Wrong
AI::UnifiedService.call(
  provider: "ollama",
  model: "gpt-4o-mini"  # OpenAI model!
)
```

**Solution:** Use correct model for provider

```ruby
# ✅ Correct
AI::UnifiedService.call(
  provider: "ollama",
  model: "llama3.2"  # Ollama model
)
```

### Issue: Ollama Not Running

**Problem:** Provider set to Ollama but server not running

**Solution:**
```bash
# Start Ollama
ollama serve

# Pull model if needed
ollama pull llama3.2
```

### Issue: OpenAI API Key Missing

**Problem:** Provider set to OpenAI but no API key

**Solution:**
```bash
export OPENAI_API_KEY=sk-...
```

## Migration Scenarios

### Scenario 1: Switch from OpenAI to Ollama

```yaml
# Before
ai:
  provider: openai

# After
ai:
  provider: ollama

ollama:
  model: llama3.2
```

```bash
# Start Ollama and pull model
ollama serve
ollama pull llama3.2
```

### Scenario 2: Switch from Ollama to OpenAI

```yaml
# Before
ai:
  provider: ollama

# After
ai:
  provider: openai
```

```bash
# Set OpenAI API key
export OPENAI_API_KEY=sk-...
```

### Scenario 3: Use Both (Auto-Detect)

```yaml
ai:
  provider: auto  # Tries OpenAI, falls back to Ollama
```

Best of both worlds:
- Uses OpenAI when available (better quality)
- Falls back to Ollama (zero cost, privacy)

## Best Practices

1. **Set explicit provider** in config for production
2. **Use "auto"** for development (flexibility)
3. **Test both providers** before deploying
4. **Monitor logs** to see which provider is used
5. **Set appropriate models** for each provider

## Logging

The system logs provider usage:

```
[AI::UnifiedService] Using provider: ollama
[AI::UnifiedService] OpenAI failed, falling back to Ollama
[Ollama::Service] Call tracked: 5 calls today
```

Check logs to verify which provider is being used.

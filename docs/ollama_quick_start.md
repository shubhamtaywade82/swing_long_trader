# Ollama Quick Start Guide

## 5-Minute Setup

### Step 1: Install the Gem

```bash
bundle install
```

This installs the `ollama-ai` gem used for Ollama integration.

### Step 2: Install Ollama Server

```bash
# macOS/Linux
curl -fsSL https://ollama.com/install.sh | sh

# Windows: Download from https://ollama.com/download
```

### Step 3: Pull a Model

```bash
# Recommended: Fast and good quality (3B parameters)
ollama pull llama3.2
```

### Step 4: Verify It Works

```bash
# Test Ollama
curl http://localhost:11434/api/tags

# Should return list of models including llama3.2
```

### Step 5: Update Config

Edit `config/algo.yml`:

```yaml
swing_trading:
  ai_ranking:
    enabled: true
    provider: ollama  # Change from "auto" to "ollama"
    model: llama3.2    # Ollama model name
```

### Step 6: Test

```bash
# Start Rails console
rails console

# Test Ollama service
result = Ollama::Service.call(
  prompt: "Analyze this swing trading signal: RELIANCE, Entry: 2500, SL: 2400, TP: 2700",
  model: "llama3.2"
)

puts result[:content] if result[:success]
```

## That's It! 🎉

Your swing trading system now uses local Ollama instead of OpenAI.

## Benefits

- ✅ **$0 cost** - No API charges
- ✅ **Unlimited calls** - No rate limits
- ✅ **Fast** - Local processing
- ✅ **Private** - Data stays on your machine

## Troubleshooting

**Ollama not found?**
```bash
# Start Ollama server
ollama serve
```

**Model not found?**
```bash
# Pull the model
ollama pull llama3.2
```

**Slow responses?**
- Use smaller model: `ollama pull deepseek-r1` (1.5B, very fast)
- Or larger model: `ollama pull llama3.1` (8B, better quality)

## Switch Back to OpenAI

Just change config back:

```yaml
swing_trading:
  ai_ranking:
    provider: openai  # or "auto" for auto-detect
    model: gpt-4o-mini
```

## More Models

```bash
# Better quality (8B)
ollama pull llama3.1

# Excellent balance (7B)
ollama pull mistral

# Great for structured outputs (7B)
ollama pull qwen2.5
```

See [full documentation](ollama_integration.md) for advanced configuration.

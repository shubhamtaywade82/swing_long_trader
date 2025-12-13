# Ollama Integration Guide

## Overview

The swing trading system now supports **Ollama** - a local LLM server that runs on your machine. This provides:

- ✅ **Zero API costs** - No OpenAI charges
- ✅ **Unlimited requests** - No rate limits
- ✅ **Privacy** - All data stays local
- ✅ **Fast responses** - No network latency
- ✅ **Offline capable** - Works without internet

## Installation

### 1. Install the Gem

The system uses the `ollama-ai` gem for Ollama integration. It's already added to the Gemfile:

```bash
bundle install
```

### 2. Install Ollama Server

**macOS/Linux:**
```bash
curl -fsSL https://ollama.com/install.sh | sh
```

**Windows:**
Download from [https://ollama.com/download](https://ollama.com/download)

**Docker:**
```bash
docker run -d -v ollama:/root/.ollama -p 11434:11434 --name ollama ollama/ollama
```

### 2. Pull a Model

Recommended models for trading analysis:

```bash
# Fast, good quality (3B parameters) - Recommended for most use cases
ollama pull llama3.2

# Better quality, still fast (8B parameters)
ollama pull llama3.1

# Excellent balance (7B parameters)
ollama pull mistral

# Great for structured outputs (7B parameters)
ollama pull qwen2.5

# Very fast, good for filtering (1.5B parameters)
ollama pull deepseek-r1
```

**Model Size Recommendations:**
- **Small systems (< 8GB RAM)**: `llama3.2` (3B) or `deepseek-r1` (1.5B)
- **Medium systems (8-16GB RAM)**: `llama3.1` (8B) or `mistral` (7B)
- **Large systems (> 16GB RAM)**: `qwen2.5` (7B) or larger models

### 3. Verify Installation

```bash
# Check if Ollama is running
curl http://localhost:11434/api/tags

# Test a simple query
ollama run llama3.2 "Hello, can you analyze trading signals?"
```

## Configuration

### Environment Variables

Add to your `.env` file:

```bash
# Optional: Custom Ollama URL (default: http://localhost:11434)
OLLAMA_BASE_URL=http://localhost:11434

# Optional: Global AI provider preference
AI_PROVIDER=ollama  # Options: "openai", "ollama", "auto"
```

### Config File (`config/algo.yml`)

```yaml
swing_trading:
  ai_ranking:
    enabled: true
    provider: ollama  # Use Ollama instead of OpenAI
    model: llama3.2   # Ollama model name
    temperature: 0.3

ollama:
  enabled: true
  base_url: http://localhost:11434
  model: llama3.2
  temperature: 0.3
  timeout: 30

ai:
  provider: auto  # Auto-detect: tries OpenAI first, falls back to Ollama
```

### Provider Options

1. **`provider: "openai"`** - Always use OpenAI
2. **`provider: "ollama"`** - Always use Ollama
3. **`provider: "auto"`** - Try OpenAI first, fallback to Ollama (default)

## Usage

### Automatic Detection

The system automatically detects and uses Ollama if:
- OpenAI API key is not configured, OR
- OpenAI rate limit is exceeded, OR
- Provider is set to "ollama" or "auto"

### Manual Selection

```ruby
# Use Ollama explicitly
result = AI::UnifiedService.call(
  prompt: "Analyze this trading signal...",
  provider: "ollama",
  model: "llama3.2",
  temperature: 0.3
)

# Use OpenAI explicitly
result = AI::UnifiedService.call(
  prompt: "Analyze this trading signal...",
  provider: "openai",
  model: "gpt-4o-mini",
  temperature: 0.3
)

# Auto-detect (tries OpenAI, falls back to Ollama)
result = AI::UnifiedService.call(
  prompt: "Analyze this trading signal...",
  provider: "auto"
)
```

### Direct Ollama Service

```ruby
# Direct Ollama service call
result = Ollama::Service.call(
  prompt: "Your prompt here",
  model: "llama3.2",
  temperature: 0.3,
  base_url: "http://localhost:11434",  # Optional
  cache: true  # Enable caching
)

if result[:success]
  puts result[:content]
  puts "Tokens used: #{result[:usage][:total_tokens]}"
else
  puts "Error: #{result[:error]}"
end
```

## Performance Comparison

### Speed
- **Ollama (local)**: ~0.5-2 seconds per request (depends on model size)
- **OpenAI API**: ~1-3 seconds per request (network latency)

### Cost
- **Ollama**: $0 (runs locally)
- **OpenAI**: ~$0.50-$2.00/day (depending on usage)

### Quality
- **Ollama (llama3.2)**: Good for structured outputs, trading analysis
- **OpenAI (gpt-4o-mini)**: Slightly better at complex reasoning
- **OpenAI (gpt-4o)**: Best quality, but expensive

**Recommendation**: For trading signal analysis, `llama3.2` or `llama3.1` provides excellent results at zero cost.

## Troubleshooting

### Ollama Not Found

**Error**: `Ollama not available` or connection refused

**Solutions:**
1. Check if Ollama is running:
   ```bash
   curl http://localhost:11434/api/tags
   ```

2. Start Ollama:
   ```bash
   ollama serve
   ```

3. Check if port 11434 is accessible:
   ```bash
   netstat -an | grep 11434
   ```

### Model Not Found

**Error**: `model not found`

**Solution**: Pull the model first:
```bash
ollama pull llama3.2
```

### Slow Responses

**Issue**: Ollama responses are slow

**Solutions:**
1. Use a smaller model (`llama3.2` instead of `llama3.1`)
2. Reduce `max_tokens` in prompts
3. Ensure Ollama has enough RAM (check with `htop` or `top`)
4. Use GPU acceleration if available (see Ollama docs)

### JSON Parsing Errors

**Issue**: Ollama sometimes returns non-JSON responses

**Solutions:**
1. Use models better at structured outputs (`qwen2.5`, `llama3.1`)
2. Lower temperature (0.1-0.3) for more consistent outputs
3. Add explicit JSON format instructions in prompts
4. The system automatically handles markdown code blocks

## Advanced Configuration

### Custom Ollama Server

If running Ollama on a different machine:

```bash
# Set environment variable
export OLLAMA_BASE_URL=http://192.168.1.100:11434

# Or in config/algo.yml
ollama:
  base_url: http://192.168.1.100:11434
```

### GPU Acceleration

Ollama automatically uses GPU if available. To check:

```bash
# Check GPU usage
nvidia-smi  # For NVIDIA GPUs

# Force CPU-only (if needed)
OLLAMA_NUM_GPU=0 ollama serve
```

### Model Customization

You can create custom models fine-tuned for trading:

```bash
# Create a Modelfile
cat > Modelfile << EOF
FROM llama3.2
SYSTEM "You are an expert swing trader specializing in technical analysis..."
EOF

# Create custom model
ollama create swing-trader -f Modelfile

# Use in config
ollama:
  model: swing-trader
```

## Monitoring

### Usage Tracking

The system tracks Ollama usage:

```ruby
# Check daily calls
today = Time.zone.today.to_s
calls = Rails.cache.read("ollama_calls:#{today}") || 0
tokens = Rails.cache.read("ollama_tokens:#{today}") || {}

puts "Calls today: #{calls}"
puts "Tokens: #{tokens[:total]}"
```

### Logs

Check Rails logs for Ollama activity:

```bash
tail -f log/development.log | grep Ollama
```

## Best Practices

1. **Start with `llama3.2`** - Good balance of speed and quality
2. **Use caching** - Enabled by default, reduces redundant calls
3. **Monitor performance** - Check response times and quality
4. **Fallback to OpenAI** - Use "auto" provider for reliability
5. **Test prompts** - Ensure prompts work well with local models

## Migration from OpenAI

To switch from OpenAI to Ollama:

1. **Install Ollama** (see Installation above)
2. **Pull a model**: `ollama pull llama3.2`
3. **Update config**:
   ```yaml
   ai_ranking:
     provider: ollama
     model: llama3.2
   ```
4. **Test**: Run a screener and verify AI evaluation works
5. **Monitor**: Check logs and performance

## Cost Savings

**Example**: If you make 50 AI calls per day:

- **OpenAI (gpt-4o-mini)**: ~$0.50/day = **$15/month**
- **Ollama (local)**: **$0/month**

**Annual savings**: ~$180/year

For higher usage (200+ calls/day), savings can be $500+/year.

## Next Steps

1. ✅ Install Ollama
2. ✅ Pull `llama3.2` model
3. ✅ Update config to use Ollama
4. ✅ Test with a screener run
5. ✅ Monitor performance and adjust model if needed

## Support

- **Ollama Docs**: [https://ollama.com/docs](https://ollama.com/docs)
- **Model Library**: [https://ollama.com/library](https://ollama.com/library)
- **Community**: [https://github.com/ollama/ollama](https://github.com/ollama/ollama)

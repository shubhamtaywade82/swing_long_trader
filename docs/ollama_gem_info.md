# Ollama-AI Gem Information

## Gem Details

- **Name**: `ollama-ai`
- **Version**: ~> 1.3.0
- **Downloads**: 53,000+
- **GitHub**: https://github.com/gbaptista/ollama-ai
- **RubyGems**: https://rubygems.org/gems/ollama-ai

## Why This Gem?

✅ **Most popular** - Highest download count for Ollama-specific gems  
✅ **Well maintained** - Recently updated (Dec 2024)  
✅ **Simple API** - Easy to use  
✅ **Full feature support** - Supports all Ollama API endpoints  
✅ **Streaming support** - Can handle streaming responses  

## API Usage

### Basic Setup

```ruby
require "ollama-ai"

client = Ollama.new(
  credentials: { address: "http://localhost:11434" },
  options: { timeout: 30 }
)
```

### Chat Completion

```ruby
events = client.chat(
  {
    model: "llama3.2",
    messages: [
      { role: "system", content: "You are a helpful assistant." },
      { role: "user", content: "Hello!" }
    ],
    options: {
      temperature: 0.3
    }
  }
)

# Events is an array, find the final one
final_event = events.find { |e| e["done"] == true }
content = final_event.dig("message", "content")
```

### List Models

```ruby
models = client.models.tags
# Returns array of available models
```

### Generate (Alternative to Chat)

```ruby
events = client.generate(
  {
    model: "llama3.2",
    prompt: "Hello!"
  }
)
```

## Features

- ✅ Chat completions
- ✅ Text generation
- ✅ Model management (list, pull, delete)
- ✅ Streaming support
- ✅ Custom base URL
- ✅ Timeout configuration
- ✅ Error handling

## Alternatives Considered

### 1. `ruby_llm` (4.2M downloads)
- **Pros**: Very popular, supports multiple providers
- **Cons**: Might be overkill for just Ollama
- **Use case**: If you want unified interface for OpenAI + Ollama + others

### 2. `ollama-ruby` (25k downloads)
- **Pros**: Simple, lightweight
- **Cons**: Less features, less maintained
- **Use case**: Minimal Ollama integration

### 3. `ollama-ai` (53k downloads) ✅ **CHOSEN**
- **Pros**: Most popular Ollama-specific gem, well maintained
- **Cons**: None significant
- **Use case**: Dedicated Ollama integration

## Migration Notes

The gem API is slightly different from our custom implementation:

**Before (Custom HTTP):**
```ruby
response = Net::HTTP.post(...)
content = JSON.parse(response.body)["message"]["content"]
```

**After (Gem):**
```ruby
events = client.chat(...)
content = events.find { |e| e["done"] }["message"]["content"]
```

But our service wrapper maintains the same external API, so no changes needed in calling code.

## Documentation

- **GitHub README**: https://github.com/gbaptista/ollama-ai
- **Ollama API Docs**: https://github.com/jmorganca/ollama/blob/main/docs/api.md

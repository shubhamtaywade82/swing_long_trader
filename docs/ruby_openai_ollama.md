# Using ruby-openai for Ollama

## Overview

Great news! The `ruby-openai` gem (which you already have installed) **supports Ollama** via Ollama's OpenAI-compatible API endpoint. This means:

✅ **No additional gems needed** - Use existing `ruby-openai`  
✅ **Same API** - Identical interface for OpenAI and Ollama  
✅ **Simpler codebase** - One gem for both providers  
✅ **Better maintenance** - One less dependency  

## How It Works

Ollama exposes an OpenAI-compatible API at `/v1/chat/completions`. The `ruby-openai` gem can connect to this endpoint by simply changing the `uri_base`.

### OpenAI Usage (Current)

```ruby
client = Ruby::OpenAI::Client.new(
  access_token: ENV["OPENAI_API_KEY"],
  uri_base: "https://api.openai.com/v1"  # Default
)

response = client.chat(
  parameters: {
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: "Hello!" }]
  }
)
```

### Ollama Usage (New)

```ruby
client = Ruby::OpenAI::Client.new(
  access_token: "ollama",  # Dummy token, Ollama doesn't require auth
  uri_base: "http://localhost:11434/v1"  # Ollama's OpenAI-compatible endpoint
)

response = client.chat(
  parameters: {
    model: "llama3.2",  # Your local Ollama model
    messages: [{ role: "user", content: "Hello!" }]
  }
)
```

## Implementation

Our `Ollama::Service` now uses `ruby-openai`:

```ruby
# app/services/ollama/service.rb
client = Ruby::OpenAI::Client.new(
  access_token: "ollama",
  uri_base: "#{@base_url}/v1",
  request_timeout: @timeout || 30,
)

response = client.chat(
  parameters: {
    model: @model,
    messages: [...],
    temperature: @temperature,
  }
)
```

## Benefits

### 1. Unified Interface
Both OpenAI and Ollama use the same `ruby-openai` gem, making it easy to switch:

```ruby
# Switch between providers easily
if use_ollama?
  client = Ruby::OpenAI::Client.new(uri_base: "http://localhost:11434/v1")
else
  client = Ruby::OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])
end
```

### 2. Same Response Format
Both return identical response structures:

```ruby
{
  "choices" => [{
    "message" => {
      "role" => "assistant",
      "content" => "Response text"
    }
  }],
  "usage" => {
    "prompt_tokens" => 10,
    "completion_tokens" => 20,
    "total_tokens" => 30
  }
}
```

### 3. Feature Parity
All `ruby-openai` features work with Ollama:
- ✅ Chat completions
- ✅ Streaming
- ✅ JSON mode
- ✅ Function calling (if model supports)
- ✅ Temperature, top_p, etc.

## Configuration

### Environment Variables

```bash
# Ollama base URL (default: http://localhost:11434)
OLLAMA_BASE_URL=http://localhost:11434
```

### Config File

```yaml
ollama:
  enabled: true
  base_url: http://localhost:11434
  model: llama3.2
  temperature: 0.3
```

## Testing

### Test Ollama Connection

```ruby
require "ruby/openai"

client = Ruby::OpenAI::Client.new(
  access_token: "ollama",
  uri_base: "http://localhost:11434/v1"
)

# List available models
models = client.models.list
puts models

# Test chat
response = client.chat(
  parameters: {
    model: "llama3.2",
    messages: [{ role: "user", content: "Hello!" }]
  }
)

puts response.dig("choices", 0, "message", "content")
```

## Migration from ollama-ai Gem

If you were using `ollama-ai` gem before:

**Before:**
```ruby
require "ollama-ai"
client = Ollama.new(credentials: { address: "http://localhost:11434" })
events = client.chat(...)
```

**After (using ruby-openai):**
```ruby
require "ruby/openai"
client = Ruby::OpenAI::Client.new(
  uri_base: "http://localhost:11434/v1"
)
response = client.chat(...)
```

## Ollama OpenAI-Compatible API

Ollama exposes these OpenAI-compatible endpoints:

- `POST /v1/chat/completions` - Chat completions
- `GET /v1/models` - List models
- `POST /v1/embeddings` - Generate embeddings
- `POST /v1/completions` - Text completions

See: https://github.com/ollama/ollama/blob/main/docs/openai.md

## Advantages Over ollama-ai Gem

| Feature | ollama-ai | ruby-openai |
|---------|-----------|-------------|
| **Already installed** | ❌ Need to add | ✅ Already in Gemfile |
| **OpenAI support** | ❌ Separate gem | ✅ Same gem |
| **API consistency** | Different API | ✅ Same API |
| **Maintenance** | One more gem | ✅ One less dependency |
| **Streaming** | ✅ Supported | ✅ Supported |
| **Error handling** | Custom | ✅ Well-tested |

## Troubleshooting

### Connection Refused

```ruby
# Make sure Ollama is running
system("ollama serve")

# Or check if it's running
curl http://localhost:11434/api/tags
```

### Model Not Found

```bash
# Pull the model first
ollama pull llama3.2
```

### Wrong Endpoint

Make sure you're using `/v1` in the URI:

```ruby
# ✅ Correct
uri_base: "http://localhost:11434/v1"

# ❌ Wrong
uri_base: "http://localhost:11434"
```

## References

- **ruby-openai**: https://github.com/alexrudall/ruby-openai
- **Ollama OpenAI API**: https://github.com/ollama/ollama/blob/main/docs/openai.md
- **Ollama Docs**: https://ollama.com/docs

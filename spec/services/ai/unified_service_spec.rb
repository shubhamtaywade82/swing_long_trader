# frozen_string_literal: true

require "rails_helper"

RSpec.describe AI::UnifiedService, type: :service do
  describe ".call" do
    let(:prompt) { "Test prompt" }

    context "when provider is 'openai'" do
      it "calls OpenAI service" do
        allow(Openai::Service).to receive(:call).and_return(
          { success: true, content: "OpenAI response", usage: {} },
        )

        result = described_class.call(
          prompt: prompt,
          provider: "openai",
          model: "gpt-4o-mini",
        )

        expect(result[:success]).to be true
        expect(result[:content]).to eq("OpenAI response")
        expect(Openai::Service).to have_received(:call)
      end
    end

    context "when provider is 'ollama'" do
      it "calls Ollama service" do
        allow(Ollama::Service).to receive(:call).and_return(
          { success: true, content: "Ollama response", usage: {} },
        )

        result = described_class.call(
          prompt: prompt,
          provider: "ollama",
          model: "llama3.2",
        )

        expect(result[:success]).to be true
        expect(result[:content]).to eq("Ollama response")
        expect(Ollama::Service).to have_received(:call)
      end
    end

    context "when provider is 'auto'" do
      context "when OpenAI succeeds" do
        it "uses OpenAI" do
          allow(Openai::Service).to receive(:call).and_return(
            { success: true, content: "OpenAI response", usage: {} },
          )

          result = described_class.call(
            prompt: prompt,
            provider: "auto",
          )

          expect(result[:success]).to be true
          expect(result[:content]).to eq("OpenAI response")
          expect(Openai::Service).to have_received(:call)
          expect(Ollama::Service).not_to have_received(:call)
        end
      end

      context "when OpenAI fails" do
        it "falls back to Ollama" do
          allow(Openai::Service).to receive(:call).and_return(
            { success: false, error: "OpenAI API error" },
          )
          allow(Ollama::Service).to receive(:call).and_return(
            { success: true, content: "Ollama response", usage: {} },
          )

          result = described_class.call(
            prompt: prompt,
            provider: "auto",
          )

          expect(result[:success]).to be true
          expect(result[:content]).to eq("Ollama response")
          expect(Openai::Service).to have_received(:call)
          expect(Ollama::Service).to have_received(:call)
        end
      end
    end

    context "when provider is determined from config" do
      it "uses config provider" do
        allow(AlgoConfig).to receive(:fetch).with(%i[ai provider]).and_return("ollama")
        allow(Ollama::Service).to receive(:call).and_return(
          { success: true, content: "Ollama response", usage: {} },
        )

        result = described_class.call(prompt: prompt)

        expect(result[:success]).to be true
        expect(Ollama::Service).to have_received(:call)
      end
    end

    context "when provider is determined from environment variable" do
      it "uses environment variable" do
        allow(ENV).to receive(:[]).with("AI_PROVIDER").and_return("ollama")
        allow(AlgoConfig).to receive(:fetch).and_return(nil)
        allow(Ollama::Service).to receive(:call).and_return(
          { success: true, content: "Ollama response", usage: {} },
        )

        result = described_class.call(prompt: prompt)

        expect(result[:success]).to be true
        expect(Ollama::Service).to have_received(:call)
      end
    end
  end
end

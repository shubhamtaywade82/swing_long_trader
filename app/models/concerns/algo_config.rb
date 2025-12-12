# frozen_string_literal: true

module AlgoConfig
  CONFIG_PATH = Rails.root.join("config/algo.yml")

  def self.fetch(key_path = nil, default = nil)
    config = load_config

    return config if key_path.nil?

    # Support dot notation, array notation, or symbol keys
    keys = case key_path
           when String
             key_path.split(".")
           when Array
             key_path
           else
             [key_path]
           end

    result = keys.reduce(config) do |memo, key|
      return default unless memo.is_a?(Hash)

      memo[key.to_sym] || memo[key.to_s]
    end

    result.nil? ? default : result
  end

  def self.load_config
    @load_config ||= begin
      erb = ERB.new(File.read(CONFIG_PATH))
      YAML.safe_load(erb.result, permitted_classes: [Symbol], aliases: true) || {}
    end
  end

  def self.reload!
    @config = nil
    load_config
  end

  def self.[](key)
    fetch(key)
  end
end

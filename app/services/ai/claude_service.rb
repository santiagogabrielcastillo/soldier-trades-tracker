# frozen_string_literal: true

require "net/http"
require "json"
require_relative "errors"

module Ai
  class ClaudeService
    ENDPOINT     = "https://api.anthropic.com"
    MODEL        = "claude-sonnet-4-6"
    API_VERSION  = "2023-06-01"
    WEB_SEARCH_TOOL = { "type" => "web_search_20260209", "name" => "web_search", "max_uses" => 10 }.freeze

    def initialize(api_key:)
      @api_key = api_key
    end

    def generate(prompt:, tools: nil, system: nil)
      uri = URI("#{ENDPOINT}/v1/messages")

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"]      = "application/json"
      request["x-api-key"]         = @api_key
      request["anthropic-version"] = API_VERSION

      body = {
        "model"      => MODEL,
        "max_tokens" => 8096,
        "messages"   => [ { "role" => "user", "content" => prompt } ]
      }
      body["system"] = system if system.present?
      body["tools"]  = tools  if tools.present?

      request.body = JSON.generate(body)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.open_timeout = 15
      http.read_timeout = 120

      response = http.request(request)
      parse_response!(response)
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
      raise Ai::ServiceError, "Claude request timed out: #{e.message}"
    end

    private

    def parse_response!(response)
      code = response.code.to_s

      case code
      when "200"
        parse_success!(response.body)
      when "429"
        raise Ai::RateLimitError, "Claude rate limit exceeded"
      when "401", "403"
        raise Ai::InvalidKeyError, "Claude API key invalid or unauthorized (#{code})"
      when "400"
        raise Ai::ServiceError, "Claude bad request (400): #{response.body}"
      else
        raise Ai::ServiceError, "Claude API returned #{code}: #{response.body}"
      end
    end

    def parse_success!(body)
      raise Ai::ServiceError, "Claude returned empty response" if body.blank?

      parsed = JSON.parse(body)

      text_blocks = Array(parsed["content"]).select { |b| b["type"] == "text" }
      raise Ai::ServiceError, "Claude response contained no text blocks" if text_blocks.empty?

      text_blocks.map { |b| b["text"] }.join
    rescue JSON::ParserError => e
      raise Ai::ServiceError, "Claude returned non-JSON response: #{e.message}"
    end
  end
end

# frozen_string_literal: true

require "net/http"
require "json"
require_relative "errors"

module Ai
  class GeminiService
    ENDPOINT = "https://generativelanguage.googleapis.com"
    MODEL    = "gemini-2.5-flash"

    def initialize(api_key:)
      @api_key = api_key
    end

    def generate(prompt:)
      uri = URI("#{ENDPOINT}/v1beta/models/#{MODEL}:generateContent")
      uri.query = URI.encode_www_form("key" => @api_key)

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate({
        "contents" => [
          { "parts" => [{ "text" => prompt }] }
        ]
      })

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30

      response = http.request(request)
      parse_response!(response)
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
      raise Ai::ServiceError, "Gemini request timed out: #{e.message}"
    end

    private

    def parse_response!(response)
      code = response.code.to_s

      case code
      when "200"
        parse_success!(response.body)
      when "429"
        raise Ai::RateLimitError, "Gemini rate limit exceeded"
      when "401", "403"
        raise Ai::InvalidKeyError, "Gemini API key invalid or unauthorized (#{code})"
      when "400"
        raise Ai::ServiceError, "Gemini bad request (400)"
      else
        raise Ai::ServiceError, "Gemini API returned #{code}"
      end
    end

    def parse_success!(body)
      raise Ai::ServiceError, "Gemini returned empty response" if body.blank?

      parsed = JSON.parse(body)
      text = parsed.dig("candidates", 0, "content", "parts", 0, "text")
      raise Ai::ServiceError, "Gemini response missing text field" if text.nil?
      text
    rescue JSON::ParserError => e
      raise Ai::ServiceError, "Gemini returned non-JSON response: #{e.message}"
    end
  end
end

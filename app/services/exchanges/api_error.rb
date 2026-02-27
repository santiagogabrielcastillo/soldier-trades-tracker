# frozen_string_literal: true

module Exchanges
  # Raised when an exchange API request fails in a retriable way (5xx, 429, timeout, JSON parse).
  # Solid Queue / Active Job can use retry_on Exchanges::ApiError to retry the job.
  class ApiError < StandardError
    attr_reader :response_code, :retry_after

    def initialize(message, response_code: nil, retry_after: nil)
      super(message)
      @response_code = response_code
      @retry_after = retry_after
    end
  end
end

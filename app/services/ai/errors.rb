# frozen_string_literal: true

module Ai
  class Error < StandardError; end
  class RateLimitError < Error; end
  class InvalidKeyError < Error; end
  class ServiceError < Error; end
end

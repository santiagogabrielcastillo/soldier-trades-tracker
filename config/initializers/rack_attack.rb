# frozen_string_literal: true

class Rack::Attack
  unless Rails.env.test?
    # Throttle login attempts by IP: 10 requests per minute
    throttle("login/ip", limit: 10, period: 1.minute) do |req|
      req.ip if req.path == "/login" && req.post?
    end

    # Throttle login attempts by email: 5 per minute per email
    throttle("login/email", limit: 5, period: 1.minute) do |req|
      if req.path == "/login" && req.post?
        req.params["email"].to_s.downcase.presence
      end
    end
  end

  # Return 429 with a plain message on throttle
  self.throttled_responder = lambda do |_req|
    [ 429, { "Content-Type" => "text/plain" }, [ "Too many login attempts. Try again in a minute." ] ]
  end
end

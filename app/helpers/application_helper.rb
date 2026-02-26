module ApplicationHelper
  def interval_hint(interval)
    case interval
    when "hourly" then "Roughly every hour."
    when "daily" then "Once per day."
    when "twice_daily" then "At 08:00 and 20:00 UTC."
    else ""
    end
  end
end

module ApplicationHelper
  # Format as $X,XXX.XX (two decimals, comma thousands separator). Returns "—" for nil.
  def format_money(amount)
    return "—" if amount.nil?
    number_to_currency(amount.to_d, precision: 2, delimiter: ",", strip_insignificant_zeros: false)
  end

  def interval_hint(interval)
    case interval
    when "hourly" then "Roughly every hour."
    when "daily" then "Once per day."
    when "twice_daily" then "At 08:00 and 20:00 UTC."
    else ""
    end
  end
end

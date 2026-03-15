module ApplicationHelper
  # Format as $X,XXX.XX (two decimals, comma thousands separator). Returns "—" for nil.
  def format_money(amount)
    return "—" if amount.nil?
    number_to_currency(amount.to_d, precision: 2, delimiter: ",", strip_insignificant_zeros: false)
  end

  # Returns a Tailwind text-color class for a signed numeric value (P&L, ROI).
  # Nil → text-slate-900 (stat/summary context). Zero treated as non-negative (green).
  def pl_color_class(value)
    return "text-slate-900" if value.nil?

    value >= 0 ? "text-emerald-600" : "text-red-600"
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

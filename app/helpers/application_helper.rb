module ApplicationHelper
  # Format as $X,XXX.XX (two decimals, comma thousands separator). Returns "—" for nil.
  def format_money(amount)
    return "—" if amount.nil?
    content_tag(:span, number_to_currency(amount.to_d, precision: 2, delimiter: ",", strip_insignificant_zeros: false), class: "font-numeric")
  end

  # Format as ARS X.XXX (Argentine peso, no decimals). Returns "—" for nil.
  def format_ars(amount)
    return "—" if amount.nil?
    content_tag(:span, number_to_currency(amount.to_d, unit: "ARS\u00A0", separator: ",", delimiter: ".", precision: 0), class: "font-numeric")
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

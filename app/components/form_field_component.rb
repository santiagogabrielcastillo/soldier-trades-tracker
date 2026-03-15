# frozen_string_literal: true

class FormFieldComponent < ApplicationComponent
  INPUT_CLASSES = "mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 shadow-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500".freeze

  def initialize(form:, attribute:, label:, type: :text, required: false, **field_options)
    raise ArgumentError, "type must be :text or :password" unless %i[text password].include?(type)

    @form = form
    @attribute = attribute
    @label = label
    @type = type
    @required = required
    @field_options = field_options
  end
end

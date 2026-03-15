# frozen_string_literal: true

class ModalComponent < ApplicationComponent
  def initialize(title:, trigger_label:, open_on_connect: false)
    @title = title
    @trigger_label = trigger_label
    @open_on_connect = open_on_connect
  end
end

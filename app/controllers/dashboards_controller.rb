# frozen_string_literal: true

class DashboardsController < ApplicationController
  def show
    @exchange_accounts = current_user.exchange_accounts
  end
end

# frozen_string_literal: true

class CedearInstrumentsController < ApplicationController
  before_action :set_instrument, only: %i[edit update destroy]

  def index
    @cedear_instruments = current_user.cedear_instruments.ordered
  end

  def new
    @cedear_instrument = current_user.cedear_instruments.build
  end

  def create
    @cedear_instrument = current_user.cedear_instruments.build(instrument_params)
    if @cedear_instrument.save
      redirect_to cedear_instruments_path, notice: t("flash.cedear_added")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @cedear_instrument.update(instrument_params)
      redirect_to cedear_instruments_path, notice: t("flash.cedear_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @cedear_instrument.destroy
    redirect_to cedear_instruments_path, notice: t("flash.cedear_removed")
  end

  # GET /cedear_instruments/lookup?ticker=AAPL
  # Returns JSON { ratio: 10.0 } or { ratio: null }
  def lookup
    ticker = params[:ticker].to_s.strip.upcase
    instrument = current_user.cedear_instruments.find_by(ticker: ticker)
    render json: { ratio: instrument&.ratio }
  end

  private

  def set_instrument
    @cedear_instrument = current_user.cedear_instruments.find(params[:id])
  end

  def instrument_params
    params.require(:cedear_instrument).permit(:ticker, :ratio, :underlying_ticker)
  end
end

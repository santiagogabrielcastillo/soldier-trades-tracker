# frozen_string_literal: true

class AddStructuredDataToStockAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_column :stock_analyses, :structured_data, :jsonb
    add_column :stock_analyses, :provider, :string, default: "gemini"
  end
end

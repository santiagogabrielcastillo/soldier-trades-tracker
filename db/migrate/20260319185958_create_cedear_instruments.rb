class CreateCedearInstruments < ActiveRecord::Migration[7.2]
  def change
    create_table :cedear_instruments do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :ticker,            null: false
      t.decimal :ratio, precision: 10, scale: 4, null: false
      t.string  :underlying_ticker
      t.timestamps
    end

    add_index :cedear_instruments, [ :user_id, :ticker ], unique: true
  end
end

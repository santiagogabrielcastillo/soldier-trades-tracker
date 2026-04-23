# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every
# environment (production, development, test). The code here should be idempotent so it can
# be executed at any point in every environment.
# Run with: bin/rails db:seed

SectorPeThreshold::DEFAULTS.each do |sector, thresholds|
  SectorPeThreshold.find_or_create_by!(sector: sector) do |t|
    t.gift_max       = thresholds[:gift_max]
    t.attractive_max = thresholds[:attractive_max]
    t.fair_max       = thresholds[:fair_max]
  end
end
puts "Seeded #{SectorPeThreshold.count} sector P/E thresholds"

if User.super_admin.none?
  User.create!(
    email: ENV.fetch("ADMIN_EMAIL") { raise "Set ADMIN_EMAIL env var before seeding" },
    password: ENV.fetch("ADMIN_PASSWORD") { raise "Set ADMIN_PASSWORD env var before seeding" },
    password_confirmation: ENV.fetch("ADMIN_PASSWORD"),
    role: "super_admin",
    active: true
  )
  puts "Super admin user created: #{ENV["ADMIN_EMAIL"]}"
end

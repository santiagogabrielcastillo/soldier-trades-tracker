# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every
# environment (production, development, test). The code here should be idempotent so it can
# be executed at any point in every environment.
# Run with: bin/rails db:seed

if User.where(admin: true).none?
  User.create!(
    email: ENV.fetch("ADMIN_EMAIL") { raise "Set ADMIN_EMAIL env var before seeding" },
    password: ENV.fetch("ADMIN_PASSWORD") { raise "Set ADMIN_PASSWORD env var before seeding" },
    password_confirmation: ENV.fetch("ADMIN_PASSWORD"),
    admin: true,
    active: true
  )
  puts "Admin user created: #{ENV["ADMIN_EMAIL"]}"
end

# db/seeds.rb
require "pg"
require "argon2"

def db_connection
  PG.connect(dbname: "Inventory")
end

conn = db_connection

# 🔄 Clear existing users (optional, comment this out if you don’t want to delete old users)
conn.exec("DELETE FROM users")

# Create a password hash for admin
password = "test123"   # <-- change this if you want a different password
hashed_pw = Argon2::Password.create(password)

conn.exec_params(
  "INSERT INTO users (username, password_hash) VALUES ($1, $2)",
  ["admin", hashed_pw]
)

puts "✅ Seed complete! You can now log in with:"
puts "   username: admin"
puts "   password: #{password}"

conn.close

require "launchy"
require "sinatra"
require "sinatra/flash"
require "pg"
require "argon2"
require "securerandom"

puts "🚀 Sinatra server starting at http://localhost:4567"

# ------------------------
# Session / Flash Setup
# ------------------------
enable :sessions
set :session_secret, ENV.fetch("SESSION_SECRET") { SecureRandom.hex(64) }
register Sinatra::Flash
set :views, File.join(__dir__, "views")

# ------------------------
# Database Connection
# ------------------------
def db_connection
  PG.connect(dbname: "Inventory")
end

# ------------------------
# Login Page
# ------------------------
get "/" do
  erb :login
end

# ------------------------
# Handle Login
# ------------------------
post "/login" do
  username = params[:username].to_s.strip
  password = params[:password].to_s

  conn = db_connection
  user = conn.exec_params("SELECT * FROM users WHERE username = $1", [username]).first
  conn.close

  # Debug output (will show in terminal)
  puts "-------------------------"
  puts "Entered username: '#{username}'"
  puts "Entered password: '#{password}'"
  puts "DB hash: '#{user ? user["password_hash"] : "nil"}'"
  match = user ? Argon2::Password.verify_password(password.strip, user["password_hash"]) : false
  puts "Password match? #{match}"
  puts "-------------------------"

  if user && match
    session[:user] = username
    flash[:success] = "Welcome, #{username}!"
    redirect "/products"
  else
    flash[:error] = "Invalid username or password."
    redirect "/"
  end
end

# ------------------------
# Logout
# ------------------------
get "/logout" do
  session.clear
  flash[:success] = "You have been logged out."
  redirect "/"
end

# ------------------------
# Protect /products routes
# ------------------------
before "/products*" do
  redirect "/" unless session[:user]
end

# ------------------------
# Show all products
# ------------------------
get "/products" do
  conn = db_connection
  @products = conn.exec("SELECT * FROM products ORDER BY id;")
  conn.close
  erb :products
end

# ------------------------
# Add a new product
# ------------------------
post "/products" do 
  name     = params["name"].to_s.strip
  quantity = params["quantity"].to_i
  price    = params["price"].to_f

  if name.empty? || quantity <= 0 || price <= 0
    flash[:error] = "⚠️ Please enter valid product details."
    redirect "/products"
  else
    conn = db_connection 
    conn.exec_params(
      "INSERT INTO products (name, quantity, price) VALUES ($1, $2, $3)",
      [name, quantity, price]
    )
    conn.close
    flash[:success] = "✅ Product added successfully!"
    redirect "/products"
  end
end 

# ------------------------
# Delete a product
# ------------------------
post "/products/:id/delete" do
  conn = db_connection
  conn.exec_params("DELETE FROM products WHERE id = $1", [params["id"].to_i])
  conn.close
  flash[:success] = "🗑️ Product deleted successfully."
  redirect "/products"
end

# ------------------------
# Show edit form
# ------------------------
get "/products/:id/edit" do
  conn = db_connection
  result = conn.exec_params("SELECT * FROM products WHERE id = $1", [params["id"].to_i])
  conn.close

  @product = result.first
  if @product
    erb :edit
  else
    flash[:error] = "Product not found."
    redirect "/products"
  end
end

# ------------------------
# Update product
# ------------------------
post "/products/:id/update" do
  id       = params["id"].to_i
  name     = params["name"].to_s.strip
  quantity = params["quantity"].to_i
  price    = params["price"].to_f

  if name.empty? || quantity <= 0 || price <= 0
    flash[:error] = "⚠️ Please enter valid product details."
    redirect "/products/#{id}/edit"
  else
    conn = db_connection
    conn.exec_params(
      "UPDATE products SET name=$1, quantity=$2, price=$3 WHERE id=$4;",
      [name, quantity, price, id]
    )
    conn.close 
    flash[:success] = "✏️ Product updated successfully!"
    redirect "/products"
  end
end

# ------------------------
# Auto-open browser
# ------------------------
Thread.new do 
  sleep 1 
  begin
    Launchy.open("http://localhost:4567/")
  rescue => e
    puts "Launchy error: #{e.message}"
  end
end

# Run Sinatra if this file is executed directly

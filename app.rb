require "dotenv/load"
require "launchy"
require "sinatra"
require "sinatra/flash"
require "pg"
require "argon2"
require "securerandom"
require "uri"
require "openai"

puts "🚀 Sinatra server starting at http://localhost:4567"

# ------------------------
# Session / Flash Setup
# ------------------------
enable :sessions
set :session_secret, ENV.fetch("SESSION_SECRET") { SecureRandom.hex(64) }
register Sinatra::Flash
set :views, File.join(__dir__, "views")

# ------------------------
# OpenAI Client Setup
# ------------------------
OPENAI_CLIENT = OpenAI::Client.new(
  access_token: ENV["OPENAI_API_KEY"],
  project: "proj_f47WaWBb6AuCPPonFBUYvBd5EhdAMYLpOi7hbcnHSG4ctDUCZ0JWKHbW3EdvJijbvgIQK6RZHjT3BlbkFJj"
)

# ------------------------
# Suggestions (round-robin fallback)
# ------------------------
SUGGESTIONS = [
  "Energy / Focus",
  "Productivity",
  "Wellness",
  "Creativity",
  "Self-Improvement"
].freeze

def next_suggested_category!
  session[:category_index] ||= 0
  value = SUGGESTIONS[session[:category_index] % SUGGESTIONS.length]
  session[:category_index] = (session[:category_index] + 1) % SUGGESTIONS.length
  value
end

# ------------------------
# Database Connection
# ------------------------
def db_connection
  PG.connect(ENV["DATABASE_URL"])
end

# ------------------------
# AI-Powered Smart Category (with Faraday handling)
# ------------------------
post "/products/suggest_category" do
  product_name = params["name"].to_s.strip

  if product_name.empty?
    flash[:error] = "Please enter a product name first."
    redirect "/products"
  end

  prompt = "Suggest a short, relevant category for a product called '#{product_name}'. " \
           "Respond with only one or two words."

  begin
    response = OPENAI_CLIENT.chat(
      parameters: {
        model: "gpt-3.5-turbo",
        messages: [{ role: "user", content: prompt }]
      }
    )

    suggestion = response.dig("choices", 0, "message", "content").to_s.strip
    suggestion = "Uncategorized" if suggestion.empty?

    flash[:success] = "⚡ Suggested category: #{suggestion}"
    redirect "/products?prefill_category=#{URI.encode_www_form_component(suggestion)}"

  rescue Faraday::TooManyRequestsError
    # Specific catch for OpenAI 429 rate limit
    flash[:error] = "⚠️ OpenAI rate limit reached — please wait a few seconds and try again."
    redirect "/products"

  rescue => e
    flash[:error] = "AI suggestion failed: #{e.message}"
    redirect "/products"
  end
end

# ------------------------
# Login Page
# ------------------------
get "/" do
  erb :login
end

# ------------------------
# Product Search (by name OR category)
# ------------------------
get "/products/search" do
  query = params[:q].to_s.strip.downcase

  if query.empty?
    redirect "/products"
  else
    @products = db_connection.exec_params(
      "SELECT * FROM products WHERE LOWER(name) LIKE $1 OR LOWER(category) LIKE $1",
      ["%#{query}%"]
    )

    @total_products = @products.ntuples
    @total_units = @products.map { |p| p["quantity"].to_i }.sum
    @total_value = @products.map { |p| p["price"].to_f }.sum.round(2)

    erb :products
  end
end

# ------------------------
# ✅ CSV Export (Stockio)
# ------------------------
get "/products/export" do
  conn = db_connection
  data = conn.exec("SELECT * FROM products ORDER BY id")
  conn.close

  content_type "text/csv"
  attachment "stockio_export.csv"

  csv = "Name,Quantity,Price,Category\n"
  data.each do |row|
    csv << "#{row['name']},#{row['quantity']},#{row['price']},#{row['category']}\n"
  end

  csv
end

# ------------------------
# Protect /products routes
# ------------------------
before "/products*" do
  redirect "/" unless session[:user]
end

# ------------------------
# Show all products + totals
# ------------------------
get "/products" do
  conn = db_connection
  @products = conn.exec("SELECT * FROM products ORDER BY id;")

  totals = conn.exec(<<~SQL)
    SELECT COUNT(*) AS total_products,
           COALESCE(SUM(quantity), 0) AS total_units,
           COALESCE(SUM(quantity * price), 0) AS total_value
    FROM products
  SQL
  @total_products = totals[0]["total_products"] || 0
  @total_units    = totals[0]["total_units"]    || 0
  @total_value    = totals[0]["total_value"]    || 0

  conn.close

  @prefill_category = params["prefill_category"].to_s
  erb :products
end

# ------------------------
# Handle Login
# ------------------------
post "/login" do
  username = params[:username].to_s.strip
  password = params[:password].to_s.strip

  conn = db_connection
  user = conn.exec_params("SELECT * FROM users WHERE username = $1", [username]).first
  conn.close

  match = user && Argon2::Password.verify_password(password, user["password_hash"])

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
# Add a new product
# ------------------------
post "/products" do
  name      = params["name"].to_s.strip
  quantity  = params["quantity"].to_i
  price     = params["price"].to_f
  category  = params["category"].to_s.strip

  if name.empty? || quantity <= 0 || price <= 0
    flash[:error] = "⚠️ Please enter valid item details."
    redirect "/products"
  else
    conn = db_connection
    conn.exec_params(
      "INSERT INTO products (name, quantity, price, category)
       VALUES ($1, $2, $3, $4)",
      [name, quantity, price, (category.empty? ? nil : category)]
    )
    conn.close
    flash[:success] = "✅ Item added!"
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
  flash[:success] = "🗑️ Item deleted."
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
  erb :edit
end

# ------------------------
# Update product
# ------------------------
post "/products/:id/update" do
  id       = params["id"].to_i
  name     = params["name"].to_s.strip
  quantity = params["quantity"].to_i
  price    = params["price"].to_f
  category = params["category"].to_s.strip

  if name.empty? || quantity <= 0 || price <= 0
    flash[:error] = "⚠️ Please enter valid item details."
    redirect "/products/#{id}/edit"
  else
    conn = db_connection
    conn.exec_params(
      "UPDATE products
         SET name=$1, quantity=$2, price=$3, category=$4
       WHERE id=$5;",
      [name, quantity, price, (category.empty? ? nil : category), id]
    )
    conn.close
    flash[:success] = "✏️ Item updated!"
    redirect "/products"
  end
end
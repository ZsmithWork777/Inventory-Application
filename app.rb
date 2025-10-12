require "dotenv/load"
require "launchy"
require "sinatra"
require "sinatra/flash"
require "pg"
require "argon2"
require "securerandom"
require "uri"
require "openai"

puts "🚀 Sinatra server running at http://localhost:4567"

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
  project:      ENV["OPENAI_PROJECT_ID"] || "proj_f47WaWBb6AuCPPonFBUYvBd5EhdAMYLpOi7hbcnHSG4ctDUCZ0JWKHbW3EdvJijbvgIQK6RZHjT3BlbkFJj"
)

# ------------------------
# Suggestion Cache (avoid hitting rate limits)
# ------------------------
AI_CACHE = {}

# ------------------------
# Database Connection
# ------------------------
def db_connection
  conn_params = ENV["DATABASE_URL"]
  conn_params += "?sslmode=require" unless conn_params =~ /sslmode=/i
  PG.connect(conn_params)
end

# ------------------------
# AI Category Suggestion Route (One-word, safe, throttled)
# ------------------------
post "/products/suggest_category" do
  product_name = params["name"].to_s.strip
  quantity     = params["quantity"].to_s.strip
  price        = params["price"].to_s.strip
  current_cat  = params["category"].to_s.strip

  unless current_cat.empty?
    flash[:success] = "⚡ Category already set — no AI needed."
    redirect request.referer || "/products"
  end

  if product_name.empty?
    flash[:error] = "⚠️ Please enter a product name first."
    redirect request.referer || "/products"
  end

  price_tier = ((price.to_f / 10).floor rescue 0)
  cache_key  = "#{product_name.downcase}-tier#{price_tier}"

  suggestion =
    if AI_CACHE.key?(cache_key)
      AI_CACHE[cache_key]
    else
      sleep 1.2

      prompt = <<~TEXT
        Suggest ONE relevant category for this product. Reply with exactly one word only.

        Name: #{product_name}
        Quantity: #{quantity}
        Price: #{price}
      TEXT

      begin
        response = OPENAI_CLIENT.chat(
          parameters: {
            model: "gpt-3.5-turbo",
            messages: [{ role: "user", content: prompt }]
          }
        )

        raw = response.dig("choices", 0, "message", "content").to_s.strip
        word = raw.split(/\s+|[,.;:|]/).first.to_s
        word = word.gsub(/[^a-zA-Z0-9\-]/, "")
        word = word.empty? ? "Misc" : word.capitalize

        AI_CACHE[cache_key] = word
      rescue Faraday::TooManyRequestsError
        flash[:error] = "⚠️ OpenAI rate limit reached. Please wait a moment and try again."
        redirect request.referer || "/products"
      rescue Faraday::ClientError => e
        if e.response && e.response[:status].to_i == 401
          flash[:error] = "⚠️ OpenAI auth error (401). Check your API key / project."
        else
          flash[:error] = "AI error: #{e.message}"
        end
        redirect request.referer || "/products"
      rescue => e
        flash[:error] = "AI suggestion failed: #{e.message}"
        redirect request.referer || "/products"
      end
    end

  target = request.referer || "/products"
  redirect "#{target}#{"?" if target && !target.include?("?")}#{target&.include?("?") ? "&" : ""}prefill_category=#{URI.encode_www_form_component(suggestion)}"
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
  redirect "/products" if query.empty?

  conn = db_connection
  @products = conn.exec_params(
    "SELECT * FROM products WHERE LOWER(name) LIKE $1 OR LOWER(category) LIKE $1",
    ["%#{query}%"]
  )
  conn.close

  @total_products = @products.ntuples
  @total_units    = @products.map { |p| p["quantity"].to_i }.sum
  @total_value    = @products.map { |p| p["price"].to_f }.sum.round(2)

  erb :products
end

# ------------------------
# CSV Export
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
# Protect Product Routes
# ------------------------
before "/products*" do
  redirect "/" unless session[:user]
end

# ------------------------
# Products Dashboard (with optional category filter)
# ------------------------
get "/products" do
  conn = db_connection
  selected_category = params[:category].to_s.strip

  if selected_category.empty?
    @products = conn.exec("SELECT * FROM products ORDER BY id;")
  else
    @products = conn.exec_params(
      "SELECT * FROM products WHERE category = $1 ORDER BY id;",
      [selected_category]
    )
  end

  totals = conn.exec_params(<<~SQL, (selected_category.empty? ? [] : [selected_category]))
    SELECT COUNT(*) AS total_products,
           COALESCE(SUM(quantity), 0) AS total_units,
           COALESCE(SUM(quantity * price), 0) AS total_value
    FROM products
    #{'WHERE category = $1' unless selected_category.empty?}
  SQL

  @total_products = totals[0]["total_products"] || 0
  @total_units    = totals[0]["total_units"]    || 0
  @total_value    = totals[0]["total_value"]    || 0

  all_cats = conn.exec("SELECT DISTINCT category FROM products WHERE category IS NOT NULL ORDER BY category;")
  @categories = all_cats.map { |r| r["category"] }

  conn.close

  @prefill_category = params["prefill_category"].to_s
  @selected_category = selected_category
  erb :products
end

# ------------------------
# Login Handling
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
# Add New Product
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
# Delete Product
# ------------------------
post "/products/:id/delete" do
  conn = db_connection
  conn.exec_params("DELETE FROM products WHERE id = $1", [params["id"].to_i])
  conn.close
  flash[:success] = "🗑️ Item deleted."
  redirect "/products"
end

# ------------------------
# Edit Product
# ------------------------
get "/products/:id/edit" do
  conn = db_connection
  result = conn.exec_params("SELECT * FROM products WHERE id = $1", [params["id"].to_i])
  conn.close
  @product = result.first
  erb :edit
end

# ------------------------
# Update Product
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

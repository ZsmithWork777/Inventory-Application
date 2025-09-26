# app.rb
require "sinatra"
require "pg"
require "launchy"

# Open browser automatically
Thread.new do
  sleep 1
  Launchy.open("http://localhost:4567/products")
end

# Tell Sinatra where to find the views folder (for ERB templates)
set :views, File.dirname(__FILE__) + "/views"

# Connect to PostgreSQL
def db_connection
  PG.connect(dbname: "Inventory")
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
  name = params["name"].to_s.strip
  quantity = params["quantity"].to_i
  price = params["price"].to_f

  if name.empty? || quantity <= 0 || price <= 0
    return "⚠️ Please enter valid product details."
  end

  conn = db_connection
  conn.exec_params(
    "INSERT INTO products (name, quantity, price) VALUES ($1, $2, $3)",
    [name, quantity, price]
  )
  conn.close
  redirect "/products"
end

# ------------------------
# Edit product form
# ------------------------
get "/products/:id/edit" do
  conn = db_connection
  @product = conn.exec_params("SELECT * FROM products WHERE id = $1", [params["id"]]).first
  conn.close
  erb :edit_product
end

# ------------------------
# Update product
# ------------------------
post "/products/:id" do
  id = params["id"].to_i
  name = params["name"].to_s.strip
  quantity = params["quantity"].to_i
  price = params["price"].to_f

  if name.empty? || quantity <= 0 || price <= 0
    return "⚠️ Please enter valid product details."
  end

  conn = db_connection
  conn.exec_params(
    "UPDATE products SET name = $1, quantity = $2, price = $3 WHERE id = $4",
    [name, quantity, price, id]
  )
  conn.close
  redirect "/products"
end

# ------------------------
# Delete product
# ------------------------
post "/products/:id/delete" do
  conn = db_connection
  conn.exec_params("DELETE FROM products WHERE id = $1", [params["id"]])
  conn.close
  redirect "/products"
end
require "launchy"
require "sinatra"
require "pg"

puts "🚀 Sinatra server starting at http://localhost:4567"
set :views, File.dirname(__FILE__) + "/views"

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

  # Prevent inserting invalid data
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
# Delete a product
# ------------------------
post "/products/:id/delete" do
  conn = db_connection
  conn.exec_params("DELETE FROM products WHERE id = $1", [params["id"].to_i])
  conn.close
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
  name = params["name"].to_s.strip
  quantity = params["quantity"].to_i
  price = params["price"].to_f
  id = params["id"].to_i

  if name.empty? || quantity <= 0 || price <= 0
    return "⚠️ Please enter valid product details."
  end

  conn = db_connection
  conn.exec_params(
    "UPDATE products SET name=$1, quantity=$2, price=$3 WHERE id=$4;",
    [name, quantity, price, id]
  )
  conn.close 
  redirect "/products"
end

# ------------------------
# Auto-open browser
# ------------------------
Thread.new do 
  sleep 1 
  Launchy.open("http://localhost:4567/products")
end
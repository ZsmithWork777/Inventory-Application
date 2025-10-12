# 🧾 Stockio — Lightweight Inventory Management (Ruby + Sinatra)

A clean, cloud-deployed inventory management app — built fully from scratch using **Ruby + Sinatra + PostgreSQL**, with:

✅ **Authentication** (secure login)  
✅ **Full CRUD Inventory Management**  
✅ **Dashboard Metrics (Total Items • Units • Inventory Value)**  
✅ **AI-Powered Category Suggestions** via OpenAI  
✅ **CSV Export for Backup / Audits**  
✅ **Mobile-Friendly UI with Tailwind Styling**

🚀 Live Demo: **https://inventory-application-aawa.onrender.com**  
📦 GitHub Repo: **https://github.com/ZsmithWork777/Inventory-Application**  
👤 Built by: **[Zachary Smith](https://www.linkedin.com/in/zacharysmith28/)**

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🔐 Login System | Password-hashed authentication using Argon2 |
| ➕ Add / Edit / Delete Items | Full CRUD for inventory products |
| 📊 Metrics Summary | Auto-calculated totals for items, units, and value |
| ⚡ Smart Category AI | One-click category suggestion using product name & price |
| 🔍 Search & Filter | Filter by name or category instantly |
| 📁 CSV Export | Exports entire database → `stockio_export.csv` |
| 🎨 Clean UI | TailwindCSS + Gradient Glassmorphism for smooth UX |

---

## 🛠️ Tech Stack

- **Backend:** Ruby + Sinatra  
- **Database:** PostgreSQL (Render-hosted)  
- **Auth:** Argon2 password hashing + session cookies  
- **AI Integration:** OpenAI API for category prediction  
- **Styling:** TailwindCSS (CDN-based)  
- **Deployment:** Render

---

## ⚙️ Setup Instructions (Local Development)

```bash
# 1. Clone the repo
git clone https://github.com/ZsmithWork777/Inventory-Application
cd Inventory-Application

# 2. Install dependencies
bundle install

# 3. Create .env file in the root folder with the following keys:
DATABASE_URL=postgresql://your_user:your_pass@localhost/inventory_db
OPENAI_API_KEY=sk-...

# 4. Run the app
ruby app.rb
Username: admin
Password: admin123

# Rosemary's Wear House — Installation & Deployment Guide
Follow the parts in order. Total time: about 60–90 minutes the first time. Everything is free tier.
Tick each box as you go. If a step does not look like what is described, stop and check Part 8 (Troubleshooting).

**What you are building**
- **Supabase** = the database and the login system (stores items, sales, users).
- **GitHub** = where the code lives.
- **Vercel** = the website host that shows the app to Rosemary and staff.

---
## Part 0 — Before you start
- [ ] A computer with internet. Commands below are for Ubuntu (Linux). Windows users: use Git Bash or ask for the Windows version.
- [ ] 4 real email addresses (developer, Rosemary, staff 1, staff 2). They don't need to receive mail; they are just login names — but use ones you control.
- [ ] A password manager or paper notebook to write down passwords.
- [ ] The project folder, unzipped. In a terminal:
  ```
  cd ~/Downloads
  unzip rosemarys-wearhouse-pos.zip -d rwh
  cd rwh
  ls
  ```
  You should see: `app.js config.js index.html styles.css logo.png supabase GUIDE.md vercel.json`

## Part 1 — Create the database (Supabase)
1. Go to **supabase.com** → **Start your project** → sign up (GitHub login is easiest).
2. Click **New project**. (Can't find it? Open **supabase.com/dashboard/projects**; the green **New project** button is at the top right of the projects list. If you are inside another project, click the project/organization name at the top-left and choose **All projects** first. Tip: use **New organization** for Rosemary's business so it stays separate from your school app. Each free organization gets 2 active projects.) Fill in:
   - Name: `rosemarys-wearhouse`
   - Database password: click **Generate a password**, then **copy it into your password manager**.
   - Region: choose the closest to your users (e.g. a Europe region is generally closest to Nigeria).
   - Plan: **Free**.
3. Click **Create new project**. Wait 1–2 minutes until the dashboard appears.
4. **Create the tables.** Left menu → **SQL Editor** → **New query**.
   - Open `supabase/01_schema.sql` in a text editor, select all, copy, paste into the SQL Editor, click **Run**.
   - Expected: "Success. No rows returned". If you see a red error, copy the message and see Part 8.
4b. **Add discounts and exchange-rate support.** New query → paste all of `supabase/04_discounts_fx.sql` → **Run**. (Run it once, after step 4 and before step 6. If you already completed the setup earlier, just run it now. It does not delete any data.)
5. **Load the SKU codes.** New query → paste all of `supabase/02_seed_codes.sql` → **Run**.
6. **Check:** left menu → **Table Editor**. The middle page says "Create a table": ignore it. In the list on the left, **click `codes`**. You should see about 72 rows: categories (Blouse = BLO …), genders and colours. (Rows only appear after you click the table. A screenshot taken before step 5 shows tables but no data.)
   - Quick count check: SQL Editor → new query → run `select kind,count(*) from codes group by kind;` Expected: category 35, colour 28, gender 5, condition 4.
   - **Two "Untitled query" entries are normal.** Supabase saves every query you run. They are harmless; you can rename (right-click) or delete them.
7. **Turn off public sign-up** (important for security): left menu → **Authentication** → **Sign In / Providers** (older UI: *Providers*) → **Email** → switch **Allow new users to sign up** OFF → Save.
8. **Create the 4 users:** **Authentication** → **Users** → **Add user** → **Create new user**.
   - Enter email + a strong password, **tick "Auto Confirm User"**, click **Create user**.
   - Repeat for all 4. Write each email/password down. Give each person only their own password.
9. **Assign roles.** Open `supabase/03_promote.sql`, replace the two example emails with the developer's and Rosemary's real emails, paste into SQL Editor, **Run**.
   - Check: Table Editor → `profiles`. Developer = `admin`, Rosemary = `owner`, the other two = `staff`.
10. **Copy your connection details:** left menu → **Project Settings** (gear) → **API** (or *Data API / API Keys*).
    - Copy **Project URL** (looks like `https://abcd1234.supabase.co`).
    - Copy the **anon / public** key (a long text starting `eyJ…`, or `sb_publishable_…` in newer projects).
    - ⚠️ **Never** use or share the **service_role** / secret key. The app does not need it.

## Part 2 — Connect the app and test it on your computer
1. Open `config.js` in a text editor. Replace the two placeholder values with what you copied. Keep the quotation marks:
   ```js
   export const SUPABASE_URL = "https://abcd1234.supabase.co";
   export const SUPABASE_ANON_KEY = "eyJ...your key...";
   ```
2. In the terminal, inside the `rwh` folder:
   ```
   python3 -m http.server 8000
   ```
3. Open a browser at **http://localhost:8000**. (Do not double-click index.html — it will stay blank.)
4. Sign in as Rosemary. You should see tabs: Dashboard, Analytics, Items, Batches, Receiving, POS.
5. **Smoke test (10 minutes)** — do these in order:
   - [ ] Batches → create "Test box", today's date. Open it, enter shipping ₦50,000, rate 1500, markup 100 → Save.
   - [ ] Items → add a Blouse / Female / Black item, cost $5, batch "Test box". A SKU like `BLO-F-BLK-1126-001` appears.
   - [ ] Batches → open Test box → you see unit cost and suggested price → **Mark shipped**.
   - [ ] Sign out, sign in as a **staff** user → Receiving → confirm the item (enter quantity received).
   - [ ] Staff → POS → search the SKU → add → Complete sale → receipt appears.
   - [ ] Sign in as Rosemary → Dashboard and Analytics show the sale.
   - [ ] Confirm staff **cannot** see Analytics or any cost columns.
6. Press `Ctrl+C` in the terminal to stop the test server.
7. **Clean up test data** (Supabase → SQL Editor → Run): 
   ```sql
   delete from sale_costs; delete from sale_lines; delete from sales;
   delete from item_costs; delete from items; delete from batches;
   alter sequence receipt_seq restart;
   ```

## Part 3 — Put the code on GitHub
1. Create an account at **github.com**. Click **+** → **New repository**.
   - Name `rosemarys-wearhouse`, choose **Private**, do **not** tick "Add a README". Click **Create repository**.
2. In the terminal (inside `rwh`), one-time setup if Git is new on this machine:
   ```
   sudo apt install -y git
   git config --global user.name "Your Name"
   git config --global user.email "you@example.com"
   ```
3. Upload the code (replace YOURNAME):
   ```
   git init -b main
   git add .
   git commit -m "First version"
   git remote add origin https://github.com/YOURNAME/rosemarys-wearhouse.git
   git push -u origin main
   ```
   GitHub asks for a login: use your username and a **Personal Access Token** as the password (GitHub → Settings → Developer settings → Personal access tokens → generate with `repo` permission).
4. Refresh the GitHub page — you should see your files. (The anon key in config.js is meant to be public; it is protected by the database rules. Still keep the repo private.)

## Part 4 — Publish the website (Vercel)
1. Go to **vercel.com** → **Sign Up** → **Continue with GitHub**.
2. **Add New… → Project** → find `rosemarys-wearhouse` → **Import**. (If missing: "Adjust GitHub App Permissions" and allow the repo.)
3. Settings screen: **Framework Preset: Other**. Leave Build Command and Output Directory **empty**. Click **Deploy**.
4. After ~30 seconds you get a URL like `https://rosemarys-wearhouse.vercel.app`. Open it and sign in.
5. **Tell Supabase the live address:** Supabase → **Authentication** → **URL Configuration** → set **Site URL** to your Vercel URL → Save.
6. **Updates in future:** edit files → `git add . && git commit -m "change" && git push` → Vercel redeploys automatically.

## Part 5 — Put it on phones and the store computer
- **Android (Chrome):** open the URL → ⋮ menu → **Add to Home screen**.
- **iPhone (Safari):** open the URL → Share → **Add to Home Screen**.
- **Windows/Linux:** open in Chrome/Edge; bookmark it, or use the install icon in the address bar.

## Part 6 — Go-live checklist
- [ ] Test data deleted (Part 2, step 7).
- [ ] Each person has signed in once and changed nothing they shouldn't. To reset a forgotten password: Supabase → Authentication → Users → ⋯ next to the user → **Send password recovery** or delete and re-create the user (then re-run the role update if it was admin/owner).
- [ ] Rosemary has her passwords written down safely, and the developer has the Supabase and Vercel logins.
- [ ] Rosemary's real data entered: first batch created before adding items.

## Part 7 — Keeping it healthy (free-tier facts)
- **Inactivity pause:** Supabase free projects are paused after about a week without activity. Opening the app and signing in regularly prevents this. If paused: Supabase dashboard → **Restore project**.
- **Backups:** the free tier does not give you reliable automatic backups. **Monthly:** Supabase → Table Editor → each table (`items`, `item_costs`, `sales`, `sale_lines`, `sale_costs`, `batches`) → **Export to CSV**, and store the files on a USB/drive. Free-tier limits change, so re-check Supabase's pricing page now and then.
- **Security:** never share the service_role key; give each person their own login; deactivate a staff member who leaves (Users tab → untick Active).

## Part 8 — Troubleshooting
| Problem | Fix |
|---|---|
| Blank page at localhost | You must use `python3 -m http.server 8000`, not double-click. |
| "Wrong email or password" | Check the user was created with **Auto Confirm** ticked; reset the password in Supabase. |
| "This account has no access" | The `profiles` row is missing or Active is unticked. Table Editor → profiles. |
| SQL error "already exists" | You ran a file twice. Safe to ignore for `02`; for `01`, delete the project and start again, or ask the developer. |
| "Unknown category/gender/colour code" | Add it: Table Editor → `codes` → Insert row (kind, name, 3-letter code). |
| Rosemary sees Analytics empty | No sales yet in that period; pick "All time". |
| Works locally but not on Vercel | Did you commit `config.js` with the real keys before pushing? Check on GitHub, then push again. |
| Staff can't see an item | It is still "sourced" (not shipped yet) — it appears to staff after Rosemary marks the batch shipped. |


---
## Part 9 — Discounts and currency: how to use them
**Discounts (owner or admin)**
1. Open **Analytics** → *Stock age*. Old stock is listed with a **Discount** button. You can also use the **Discount** button on any in-stock item in the **Items** tab.
2. Enter a percentage (0 removes the discount, maximum 90) and a reason. If the new price would be below the item's cost, the app warns you first.
3. At the POS, staff now see the discounted price, and the system **blocks staff from selling below it**. Only the owner or admin can sell at a lower price.
4. Each sale records the original price, the discount and the exchange rate. **Dashboard** and **Analytics** show discounts given, units and profit from discounted sales, and margin compared with full-price sales.

**Currency (owner or admin)**
- The **$ USD / ₦ NGN** button at the top switches everything: dashboard, analytics, items, batch costing, and the amounts you type when adding items. Staff always work in naira.
- When entering items in dollars, a live line under the form shows the naira equivalent at today's rate and the 7-day low–high range.
- Dollar views convert each sale at the rate recorded on that sale; stock value uses today's rate.
- **Rates tab:** see the rate in use, the 30-day range and history. The rate is fetched automatically whenever the owner or admin has the app open (at most every 6 hours). Official and street rates in Nigeria can differ, so you can add a **buffer %** or choose **Manual** and type your own rate.
- Free rate sources are used (open.er-api.com, with a backup). If the rate fetch fails, the last saved rate stays in use.

**Test it (5 minutes):** ship a batch and confirm it as staff → as owner, press Discount on the item (15%) → as staff, open POS: the price is lower and cannot be reduced → sell it → as owner, check Analytics → *Discount impact*, then press the currency button and watch all figures change.

---
## Part 10 — Version 2.1 update (dollar pricing, Stock tab, icons)
1. **Database first:** SQL Editor → run `supabase/05_usd_pricing.sql` once (after `04`).
2. Copy `index.html`, `app.js`, `styles.css` and `diag.js` from the new zip (keep your own `config.js`). Test with `python3 -m http.server 8000`, then `git add . && git commit -m "v2.1" && git push`.
3. **How pricing now works:** the owner enters US purchases and selling prices in **dollars**. A yellow notice above *Save & generate SKU* suggests the naira equivalent and 7-day range. When staff press **Confirm** in Receiving, the naira price is fixed at that day's rate and appears in **Stock** (owner/admin have their own **Stock** tab showing ₦ and $ prices).
4. The **Rates** tab has a two-way $ ⇄ ₦ converter. Tapping the rate chip at the top opens it.
5. Feedback: call or WhatsApp +234 905 390 3530 (links are in the app footer).

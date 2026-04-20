# Torn-scripts
Scripts ive made using Claude

📊 Torn PDA Market Scripts — Faction Guide
These two scripts work together to help you buy low, sell high, and track market prices across Torn's item market. Install both in Torn PDA's script manager.

Script 1 — Market Base (the big one)
What it does on the BUY page (Item Market):
Shows a sticky banner at the top with the item name, ID, listing count, and a suggested sell price calculated from current listings

Detects price walls — if someone has 200+ units listed below the normal price, it warns you and caps the baseline below their wall so you don't get stuck underselling them

Highlights every row with a profit badge showing +$amount • ROI%
Green outline = best single-unit buy. Gold outline + 📦 = best bulk buy (most total profit by quantity)

What it does on the SELL page (your inventory):
Shows a green price badge next to each item you own if you've viewed that item's market within 12 hours
Amber badge with age label if the data is 12–24 hours old
No badge if data is older than 24 hours (too stale to trust)

⚡ Auto-fill prices button — one tap fills every item's price AND max quantity automatically using fresh baseline data only


Script 2 — Price Tracker

What it does:
Runs silently in the background on any page that shows item cards (bazaars, trades, your inventory)

Records the daily high and low price of every item it sees, storing up to 30 days of history

Adds a small bar underneath each item card showing:
🔥 Great / ✅ Good / ➡️ Fair / ⚠️ High / 🚫 Pricey — where today's price sits in the 30-day range

A visual progress bar with a dot showing position between the all-time low and high
LOW / AVG / HIGH prices from your personal history
How many days of data you have

***This part of the script takes time to gather price info. the more you view these pages the better the script becomes. I recommend visiting pages you buy from a few times before fully trusting the data!***

How they work together?

What you see:
You browse the item market:

Script 1 calculates today's sell baseline. Script 2 records today's price into your 30-day history.


You open someone's bazaar:

Script 2 shows you instantly whether their price is a deal or overpriced based on your history.


You go to sell your items:

Script 1 fills in the optimal sell price and max quantity automatically


Prices are stale:

Script 1 turns amber and warns you — browse the market again to refresh


***The key insight: Script 2 builds up your price history passively just by browsing — the more you play, the smarter both scripts get. Script 1 uses live market data for sell decisions while Script 2 gives you the longer-term context for buy decisions.***




Setup-

Install both scripts in Torn PDA → Settings → Scripts

Browse the item market for items you trade regularly to seed your baseline data

When selling, tap ⚡ Auto-fill to price everything in one go

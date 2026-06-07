# PhoneRecon — Setup Guide

## Prerequisites

| Tool | Version |
|---|---|
| Node.js | 18+ |
| Android Studio | Ladybug+ |
| JDK | 17 |
| React Native CLI | latest |

---

## Step 1 — API Keys (30 min)

### Twilio
1. Go to **twilio.com/try-twilio** — free $15 credit, no card required initially
2. Copy **Account SID** and **Auth Token** from the console dashboard
3. The Lookups v2 API is included — no extra setup

### NumLookup
1. Go to **numlookupapi.com** → Sign Up (free tier: 500 req/month)
2. Copy your **API Key** from the dashboard

### HaveIBeenPwned
1. Go to **haveibeenpwned.com/API/Key** ($3.50/month)
2. Enter your email, pay, copy the key from your inbox

---

## Step 2 — Backend (20 min)

```bash
cd phone-recon
cp .env.example .env
```

Edit `.env` — fill in all five values:
```
PORT=3000
API_SECRET=<make a random 32-char string>
TWILIO_ACCOUNT_SID=AC...
TWILIO_AUTH_TOKEN=...
NUMLOOKUP_API_KEY=...
HIBP_API_KEY=...
```

Install and run:
```bash
npm install
node server.js
# → PhoneRecon server running on port 3000
```

Test it:
```bash
curl -s -X POST http://localhost:3000/lookup \
  -H "Content-Type: application/json" \
  -H "x-api-secret: YOUR_SECRET_HERE" \
  -d '{"number": "+15555550100"}' | jq .
```

You should get a JSON object with `twilio`, `numLookup`, and `hibp` keys.

---

## Step 3 — Android App (45 min first time)

### Install toolchain
1. Download **Android Studio** → install with default settings
2. Open Android Studio → More Actions → SDK Manager → SDK Tools tab → check **Android SDK Command-line Tools** → Apply
3. Install **JDK 17**: `brew install openjdk@17` (Mac) or download from adoptium.net

### Set environment variables (add to `~/.bashrc` or `~/.zshrc`)
```bash
export ANDROID_HOME=$HOME/Library/Android/sdk           # Mac
# export ANDROID_HOME=$HOME/Android/Sdk                 # Linux
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools
```

### Create the React Native project
```bash
npx react-native@latest init PhoneRecon
cd PhoneRecon
```

### Drop in the app
Copy `App.js` from this repo into the project root (overwrite the generated one):
```bash
cp /path/to/phone-recon/App.js .
```

Open `App.js` and update these two lines at the top:
```js
const SERVER_URL = 'http://192.168.1.XX:3000'; // your machine's LAN IP
const API_SECRET = 'your_secret_from_.env';
```

Find your LAN IP:
- Mac/Linux: `ifconfig | grep "inet " | grep -v 127`
- Windows: `ipconfig`

Your phone and computer must be on the **same WiFi network**.

### Run on device or emulator
```bash
# Start an emulator first (or plug in a phone with USB debugging on)
npx react-native run-android
```

The app installs and launches automatically.

---

## Costs

| Service | Free Tier | Paid |
|---|---|---|
| Twilio Lookups | $0.018/query | Pay as you go |
| NumLookup | 500 req/month free | $9.99/mo for 5k |
| HaveIBeenPwned | None | $3.50/month flat |

At $0.018/lookup with Twilio, you'd need **~2,800 lookups** to spend $50.

---

## Troubleshooting

**"Network request failed" in app**
- Make sure the server is running and reachable: `curl http://192.168.1.XX:3000/health`
- Phone and computer must be on the same WiFi
- Check your firewall — allow port 3000

**Twilio 401 error**
- Double-check ACCOUNT_SID and AUTH_TOKEN in `.env`
- Make sure you're not using test credentials for Lookups

**HIBP 429 Too Many Requests**
- HIBP rate-limits to 1 req/1500ms — fine for manual lookups, don't script rapid-fire queries

**Metro bundler port conflict**
```bash
npx react-native start --port 8082
# then in another tab:
npx react-native run-android --port 8082
```

---

## What's Next

This is Module 1. Same architecture, new tabs:
- **Module 2** — Email OSINT (Hunter.io + HIBP email endpoint)
- **Module 3** — Name search (Pipl, Whitepages API)
- **Module 4** — License plate (state DMV APIs vary)

# PhoneRecon — Android App Setup

Everything runs on the phone. No server needed.

---

## Step 1 — API Keys (30 min)

### Twilio
1. **twilio.com/try-twilio** — free $15 credit, no card required initially
2. Dashboard → Account Info → copy **Account SID** and **Auth Token**

### NumLookup
1. **numlookupapi.com** → Sign Up (free: 500 req/month)
2. Dashboard → copy **API Key**

### HaveIBeenPwned
1. **haveibeenpwned.com/API/Key** → $3.50/month flat rate
2. Enter email, pay, copy key from confirmation email

---

## Step 2 — Android toolchain (first time only, ~30 min)

1. Install **Android Studio** (android studio download)
   - During setup, check: Android SDK, Android SDK Platform, Android Virtual Device
2. In Android Studio → More Actions → SDK Manager → SDK Tools tab →
   check **Android SDK Command-line Tools (latest)** → Apply
3. Install **JDK 17**:
   - Mac: `brew install openjdk@17`
   - Linux: `sudo apt install openjdk-17-jdk`
   - Windows: download from adoptium.net

4. Add to `~/.bashrc` or `~/.zshrc`:
```bash
export ANDROID_HOME=$HOME/Library/Android/sdk   # Mac
# export ANDROID_HOME=$HOME/Android/Sdk         # Linux
# export ANDROID_HOME=%LOCALAPPDATA%\Android\sdk  # Windows (use System Properties)
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools
```
Then `source ~/.bashrc` (or restart terminal).

---

## Step 3 — Create the React Native project (10 min)

```bash
npx react-native@latest init PhoneRecon
cd PhoneRecon
```

Copy both files from this repo into the project root:
```bash
cp /path/to/phone-recon/App.js .
cp /path/to/phone-recon/config.js .
```

---

## Step 4 — Fill in your API keys

Open `config.js` and paste your keys:

```js
export const CONFIG = {
  TWILIO_ACCOUNT_SID: 'ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
  TWILIO_AUTH_TOKEN:  'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
  NUMLOOKUP_API_KEY:  'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
  HIBP_API_KEY:       'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
};
```

---

## Step 5 — Run on device or emulator

```bash
# Option A — physical device: plug in via USB, enable USB Debugging in dev options
# Option B — emulator: open Android Studio → Device Manager → launch an AVD

npx react-native run-android
```

Metro bundler starts automatically. The app installs and launches on the device.

---

## Costs

| Service | Free Tier | Paid |
|---|---|---|
| Twilio Lookups | $0.018/query | Pay as you go |
| NumLookup | 500 req/month | $9.99/mo for 5k |
| HaveIBeenPwned | None | $3.50/month flat |

---

## Troubleshooting

**`CLEARTEXT communication not permitted`**
All three APIs use HTTPS, so this shouldn't occur. If it does, confirm
the URLs in App.js start with `https://`.

**Twilio 401**
Double-check Account SID and Auth Token — don't mix up the two values.

**HIBP 429**
HIBP rate-limits to 1 req/1500ms. Fine for manual use; don't run it in a loop.

**`btoa is not defined`**
Upgrade to React Native 0.71+ (uses Hermes by default, which has btoa).

**Metro port conflict**
```bash
npx react-native start --port 8082
# new tab:
npx react-native run-android --port 8082
```

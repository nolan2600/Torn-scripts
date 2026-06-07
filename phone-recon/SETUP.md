# PhoneRecon — Android App Setup

Standalone Android app. No server. API keys are entered inside the app
and stored on-device via AsyncStorage.

---

## Step 1 — API Keys (30 min)

You'll enter these inside the app — just have them ready.

| Key | Where to get it | Cost |
|---|---|---|
| Twilio Account SID | twilio.com/try-twilio → Console | Free ($15 credit) |
| Twilio Auth Token | twilio.com/try-twilio → Console | Free ($0.018/lookup) |
| NumLookup API Key | numlookupapi.com → Dashboard | Free (500 req/mo) |
| HaveIBeenPwned Key | haveibeenpwned.com/API/Key | $3.50/month |

---

## Step 2 — Android toolchain (first time only, ~30 min)

1. Install **Android Studio** (android.com/studio)
   - Include: Android SDK, Android SDK Platform, Android Virtual Device
2. Android Studio → More Actions → SDK Manager → SDK Tools →
   check **Android SDK Command-line Tools (latest)** → Apply
3. Install **JDK 17**:
   - Mac: `brew install openjdk@17`
   - Linux: `sudo apt install openjdk-17-jdk`
   - Windows: adoptium.net

4. Add to `~/.bashrc` or `~/.zshrc`:
```bash
export ANDROID_HOME=$HOME/Library/Android/sdk   # Mac
# export ANDROID_HOME=$HOME/Android/Sdk         # Linux
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools
```
Restart terminal (or `source ~/.bashrc`).

---

## Step 3 — Create React Native project (10 min)

```bash
npx react-native@latest init PhoneRecon
cd PhoneRecon
```

Install AsyncStorage:
```bash
npm install @react-native-async-storage/async-storage
```

Copy `App.js` from this repo into the project root:
```bash
cp /path/to/phone-recon/App.js .
```

---

## Step 4 — Run on device or emulator

```bash
# Physical device: plug in via USB, enable USB Debugging in developer options
# Emulator: Android Studio → Device Manager → launch an AVD

npx react-native run-android
```

---

## Step 5 — Enter your keys in the app

1. First launch shows **"API keys not configured"** banner
2. Tap **⚙ KEYS** in the top-right corner
3. Paste your 4 keys — each field has a SHOW/HIDE toggle
4. Tap **SAVE KEYS** — stored locally via AsyncStorage, never leaves device
5. Tap **← BACK** to return to the lookup screen

Green dot next to each field = key is set. Orange dot in header = incomplete.

---

## Troubleshooting

**"API keys not configured" after saving**
Force-close the app and reopen — AsyncStorage writes are async and
occasionally need a fresh mount to reflect.

**Twilio 401**
Account SID starts with `AC`. Auth Token is the second value. Don't mix them up.

**HIBP 429**
Rate-limited to 1 req/1500ms — fine for manual lookups.

**`btoa is not defined`**
Upgrade to React Native 0.71+ (Hermes is the default from 0.70+).

**Metro port conflict**
```bash
npx react-native start --port 8082
npx react-native run-android --port 8082
```

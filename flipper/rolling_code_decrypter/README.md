# Rolling Code Decrypter — Flipper Zero (Unleashed Firmware)

A Flipper Zero external application that decodes and decrypts **KeeLoq / HCS-family**
rolling-code transmissions captured by the Sub-GHz radio.

> **Legal notice** — Only analyse signals from devices you own or have explicit written
> permission to test. Unauthorised interception of radio transmissions is illegal in
> most jurisdictions. This tool is provided for security research and education only.

---

## What it does

| Feature | Detail |
|---------|--------|
| Frame decode | Parses 66-bit HCS200 / HCS300 / HCS301 OTA frames |
| Field extraction | Serial number, button code, repeat flag, low-battery flag |
| KeeLoq decrypt | Decrypts the 32-bit hop code when the key is known |
| Key derivation | Derives per-device key from a manufacturer key + serial |
| Known-key scan | Tries a built-in list of published manufacturer keys |
| RAW signal decode | Reads Flipper RAW `.sub` captures and decodes PWM timing |
| Decoded file parse | Reads Flipper decoded KeeLoq `.sub` files directly |

---

## How rolling codes work (brief)

Each button press transmits a 66-bit frame:

```
[ Ciphertext 32b ][ Serial 28b ][ Button 4b ][ S1 ][ S0 ]
```

The **ciphertext** is produced by KeeLoq-encrypting a 32-bit plaintext:

```
[ Function 4b ][ OVR counter 12b ][ SYNC counter 16b ]
```

The counter increments on every press. The receiver decrypts and accepts codes
within a window ahead of the last-seen counter, blocking replays.

KeeLoq uses a 64-bit key that is unique per device. The key is derived from the
manufacturer's 64-bit secret and the device serial using the "Normal Learning"
algorithm (Microchip AN636).

---

## File structure

```
rolling_code_decrypter/
├── application.fam        Flipper app manifest
├── keeloq.h / .c         KeeLoq block cipher (encrypt, decrypt, key derive)
├── hcs_protocol.h / .c   HCS301 frame structure and formatting
├── signal_decoder.h / .c PWM timing decoder for RAW .sub files
├── known_keys.h           Published manufacturer-key database
├── rolling_code_app.h     App state and view IDs
├── rolling_code_app.c     Main entry point, UI, file loading
└── keeloq_test.c          Standalone unit tests (gcc, no SDK needed)
```

---

## Building

### Option A — Flipper Zero Unleashed firmware (on-device)

1. Clone [Unleashed firmware](https://github.com/DarkFlippers/unleashed-firmware).
2. Copy this directory into `applications_user/rolling_code_decrypter/`.
3. Build:
   ```sh
   ./fbt fap_rolling_code_decrypter
   ```
4. The `.fap` file appears under `dist/`. Copy it to `SD:/apps/Sub-GHz/`.

### Option B — Unit tests (no Flipper SDK)

```sh
gcc -O2 -o keeloq_test keeloq.c keeloq_test.c && ./keeloq_test
```

---

## Using the app

1. Capture a signal with **Sub-GHz → RAW** or the KeeLoq decoder and save the `.sub` file.
2. Place the `.sub` file on the SD card under `SD:/subghz/`.
3. Launch **Rolling Code Decrypter** from `Apps → Sub-GHz`.

### Menu options

| Option | What it does |
|--------|--------------|
| **Decode .sub File** | Browse `SD:/subghz/`, select a file, decode the frame |
| **Try Known Keys** | Attempt decryption using the built-in key database |
| **About** | Version and path info |

### Controls

| Button | Action |
|--------|--------|
| Up / Down | Navigate lists / scroll text |
| OK | Select / confirm |
| Back | Go back / exit |

---

## Adding manufacturer keys

Edit `known_keys.h` and add an entry to the `KNOWN_KEYS[]` array:

```c
{
    .name  = "My OEM Remote",
    .key   = 0xAABBCCDDEEFF0011ULL,
    .notes = "Key recovered from public research paper DOI:...",
},
```

Rebuild and reflash. The "Try Known Keys" screen will include your key.

---

## Algorithm notes

### KeeLoq cipher

- 32-bit block / 64-bit key
- 528-round NLFSR
- NLF constant: `0x3A5C742E`
- NLF inputs: state bits 1, 9, 20, 26, 31
- Linear feedback: state bits 0 ⊕ 16

### Key derivation ("Normal Learning")

```
seed_lo  = serial & 0xFFFF
seed_hi  = (serial >> 16) & 0x0FFF
k_lo     = KeeLoq_Enc(seed_lo,  manuf_key)
k_hi     = KeeLoq_Enc(seed_hi,  manuf_key)
dev_key  = interleave(serial, k_lo, k_hi)   // see keeloq.c
```

### Signal timing (HCS301, 455 kHz resonator)

```
TE ≈ 400 µs
Preamble : 12 × TE pulses
Header   : ≥ 4 × TE gap
"0" bit  : 1×TE pulse + 2×TE gap
"1" bit  : 2×TE pulse + 1×TE gap
Total frame ≈ 90 ms
```

---

## References

- Microchip AN636 — *KeeLoq Code Hopping Decoder*
- Microchip HCS301 Data Sheet (DS21227E)
- Courtois et al., *"Efficient Algorithms for the Implementation of 4th Order DPA Attacks on KeeLoq"* (2008)
- Kasper, Oswald, Paar — *"Side-Channel Analysis of Cryptographic RFIDs"* (2009)
- [Flipper Zero Unleashed Firmware](https://github.com/DarkFlippers/unleashed-firmware)

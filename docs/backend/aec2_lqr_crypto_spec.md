# AEC v2 — lqr Crypto Spec (Backend Reference)

**Purpose.** The mobile app only *decrypts* location-QR (`lqr`) codes; it has **no**
`aec2Encrypt`. The QR generator lives on the backend (currently a Google Sheet).
This document is the **source-of-truth decrypt algorithm** as shipped in the app,
plus the **derived encrypt algorithm** the backend must implement so its output
decrypts correctly on-device.

Source of truth: `lib/crypto/auth_crypto.dart`
- `lqrVerify` (envelope / URL strip)
- `aecDecrypt` (version + key-type dispatch)
- `aec2Decrypt` (the core cipher) — **this is what encrypt must invert**
- `a64` alphabet: `lib/global.dart:549`
- `base64ToDec` (char→index): `auth_crypto.dart:1051`

> If `aec2Decrypt` ever changes, this doc and the backend generator must change with it.
> Cross-validate the backend against the *actual* `aec2Decrypt` before shipping (see §9).

---

## 1. Envelope (what the QR literally contains)

Scan flow on device: `lqrVerify(p, q, rawQrText)` → `aecDecrypt(qrText, 'l')`.

A scanned `lqr` value is **either**:

| Form | Example | Device handling |
|------|---------|-----------------|
| Bare | `2<ciphertext>` | used as-is |
| URL  | `https://<host>/qr/2<ciphertext>` | `lqrVerify` keeps substring **after the last `/qr/`** |

First char = **encryption version**:

| Version | Meaning | Decrypt |
|---------|---------|---------|
| `0` | plaintext, no crypto (`makeLqrCode` output: `0l<sha1hex>`) | payload = everything after the `0` |
| `2` | **AEC v2** (this spec) | `aec2Decrypt(key, ciphertext)` |

Backend target = **version `2`**. Emit `"2" + ciphertext`.

### Key selection

`aecDecrypt` maps input-type → key-type → key:

```
inputType 'l' (location)  →  keyType '6'  →  getAecKey('6') = ftzSecretSixCode
```

`ftzSecretSixCode` is a **shared hex-string secret** (gitignored; already held by both
app and backend). Both sides MUST use the identical value. Let `keyByte = key.length / 2`.

> Decrypt-side robustness: if the type-`6` key fails, `aecDecrypt` retries with the
> first cipher char as a key-type, then every known key. Backend does not need this —
> just always encrypt with the `6` key.

---

## 2. Constants (must match exactly)

```
m               = [0, 13, 17, 19, 23, 29]     // multipliers; m[0] unused
MOD             = 4096                          // encryptionModulo = 64*64
BASE            = 64                            // inputBase
NONCE_SYMBOLS   = 24                            // symbols dropped by decrypt
a64  = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
```

`a64` is the **index→char** table. `base64ToDec` is its exact inverse (**char→index**):

| chars | index |
|-------|-------|
| `A`–`Z` | 0–25 |
| `a`–`z` | 26–51 |
| `0`–`9` | 52–61 |
| `-` | 62 |
| `_` | 63 |

**This ordering is load-bearing** — it is NOT standard base64 (`+`/`/`), and digits come
*after* letters. Use `a64` / this table, never a stock base64 lib.

---

## 3. Data model

- **Plaintext** = a string of `a64` symbols. Each symbol → one index in `[0,63]`.
- **Ciphertext** = **2 `a64` chars per plaintext symbol** → a 12-bit value in `[0,4095]`
  (`hi = value>>6`, `lo = value & 63`). So ciphertext length = `2 × (24 + payloadLen)`.
- A random **24-symbol nonce** is prepended to the payload before encryption and
  **dropped** on decrypt.

Reading a ciphertext unit: `value = base64ToDec(c0)*64 + base64ToDec(c1)` (big-endian: c0 high).

---

## 4. Key schedule

```
keyByte  = key.length / 2                       // number of key bytes
keyVec   = [0]                                  // 1-indexed; keyVec[0] is a sentinel
for j in 0 .. keyByte-1:
    keyVec.push( parseHexByte(key[2j .. 2j+2]) )  // keyVec[1..keyByte]
```

Key byte used at step `i`: `keyVec[(i mod keyByte) + 1]`.

---

## 5. Decrypt (source of truth — `aec2Decrypt`)

Input `cipher` = ciphertext **after** the version byte. `n = cipher.length / 2`.

```
state: lastPass=0, lastXor=0, keyCursor=0, inputVec=[0], out=""

for i in 0 .. n-1:
    value = base64ToDec(cipher[2i]) * 64 + base64ToDec(cipher[2i+1])   // 0..4095
    inputVec.push(value)                                              // inputVec[i+1]=value

    if i == 0:
        value2 = (keyVec[1] * m[1] * m[2]) % MOD          // == keyVec[1]*221 ; SPECIAL first step
    else:
        value2 = ( lastPass          * m[1]
                 + keyVec[keyCursor+1]* m[2]
                 + lastXor           * m[3]
                 + inputVec[i]        * m[4] ) % MOD       // inputVec[i] = PREVIOUS ciphertext value

    xor = value XOR value2                                 // 0..63 for valid ciphertext

    lastPass  = value2
    lastXor   = xor
    keyCursor = (keyCursor + 1) % keyByte
    out += a64[xor]                                        // NO bounds check — see §8

return out.substring(24).toLowerCase()                    // drop 24-symbol nonce, then lowercase
```

Notes that matter for the inverse:
- **Step 0 is special**: `keyVec[1]*m[1]*m[2]` (product of *two* multipliers), not the general form.
- Keystream `value2` feeds back on **previous ciphertext value** (`inputVec[i]`), **previous
  keystream** (`lastPass`), and **previous plaintext symbol** (`lastXor`) — a self-chaining
  (CFB-like) mode. Order of state updates is fixed; replicate exactly.
- Post-processing: **strip 24**, **lowercase**. (Consequence: payload is effectively
  case-insensitive — see §8.)

---

## 6. Encrypt (what the backend implements — inverse of §5)

Since decrypt yields `xor = value XOR value2` and requires `xor == plaintextSymbol`,
the encryptor sets **`value = plaintextSymbol XOR value2`** using the *same* keystream
recurrence, then emits `value` as 2 `a64` chars.

```
input: key (hex), payload (string over a64; see §8 for allowed chars)

keyByte, keyVec  = schedule(key)                          // §4

plain = randomNonce(24) + payload                         // 24 random a64 symbols, then payload

state: lastPass=0, lastXor=0, keyCursor=0, inputVec=[0], out=""

for i in 0 .. plain.length-1:
    sym = base64ToDec(plain[i])                           // 0..63  (this is decrypt's `xor`)

    if i == 0:
        value2 = (keyVec[1] * m[1] * m[2]) % MOD          // SAME special first step
    else:
        value2 = ( lastPass          * m[1]
                 + keyVec[keyCursor+1]* m[2]
                 + lastXor           * m[3]
                 + inputVec[i]        * m[4] ) % MOD

    value = sym XOR value2                                 // 0..4095 (12-bit ciphertext unit)
    out  += a64[value >> 6] + a64[value & 63]             // hi char, lo char

    inputVec.push(value)                                  // becomes inputVec[i+1] = this value
    lastPass  = value2
    lastXor   = sym                                       // == decrypt's xor at this step
    keyCursor = (keyCursor + 1) % keyByte

return "2" + out                                          // version-2 lqr payload
```

`randomNonce(24)` = 24 chars each `a64[random 0..63]`, from a CSPRNG. The nonce is
security-relevant (prevents identical payloads producing identical ciphertext); do **not**
hard-code or reuse it.

To ship as a URL: `https://<host>/qr/` + the returned `"2" + out`.

---

## 7. Reference implementation (JavaScript — Apps Script / Cloud Functions)

```js
const A64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
const M = [0, 13, 17, 19, 23, 29];
const MOD = 4096;
const dec = ch => A64.indexOf(ch);              // char -> index (matches base64ToDec)

function schedule(keyHex) {
  const keyByte = keyHex.length >> 1;
  const keyVec = [0];
  for (let j = 0; j < keyByte; j++) keyVec.push(parseInt(keyHex.substr(j * 2, 2), 16));
  return { keyByte, keyVec };
}

// payload: use only [a-z0-9-_] so it survives decrypt's toLowerCase() unchanged (§8)
function aec2Encrypt(keyHex, payload, nonce /* optional: 24 a64 chars, for deterministic tests */) {
  const { keyByte, keyVec } = schedule(keyHex);
  if (!nonce) {
    nonce = "";
    for (let n = 0; n < 24; n++) nonce += A64[Math.floor(Math.random() * 64)]; // use CSPRNG in prod
  }
  const plain = nonce + payload;
  let out = "", lastPass = 0, lastXor = 0, keyCursor = 0;
  const inputVec = [0];
  for (let i = 0; i < plain.length; i++) {
    const sym = dec(plain[i]);
    const value2 = (i === 0)
      ? (keyVec[1] * M[1] * M[2]) % MOD
      : (lastPass * M[1] + keyVec[keyCursor + 1] * M[2] + lastXor * M[3] + inputVec[i] * M[4]) % MOD;
    const value = sym ^ value2;
    out += A64[value >> 6] + A64[value & 63];
    inputVec.push(value);
    lastPass = value2; lastXor = sym; keyCursor = (keyCursor + 1) % keyByte;
  }
  return "2" + out;
}

// Mirror of aec2Decrypt (cipher = value WITHOUT the version byte). For self-test only.
function aec2Decrypt(keyHex, cipher) {
  const { keyByte, keyVec } = schedule(keyHex);
  let out = "", lastPass = 0, lastXor = 0, keyCursor = 0;
  const inputVec = [0], n = cipher.length >> 1;
  for (let i = 0; i < n; i++) {
    const value = dec(cipher[2 * i]) * 64 + dec(cipher[2 * i + 1]);
    inputVec.push(value);
    const value2 = (i === 0)
      ? (keyVec[1] * M[1] * M[2]) % MOD
      : (lastPass * M[1] + keyVec[keyCursor + 1] * M[2] + lastXor * M[3] + inputVec[i] * M[4]) % MOD;
    const xor = value ^ value2;
    lastPass = value2; lastXor = xor; keyCursor = (keyCursor + 1) % keyByte;
    out += A64[xor];                              // xor MUST be < 64 (see §8)
  }
  return out.slice(24).toLowerCase();
}
```

---

## 8. Constraints & gotchas (do not skip)

1. **Payload alphabet.** Every payload char MUST be in `a64`. Decrypt indexes `a64[xor]`
   with **no bounds check**; a payload symbol out of `[0,63]` is impossible by construction
   *only if* you encrypt real `a64` chars. Non-`a64` input to `dec()` yields `-1` → garbage.
2. **Case folding.** Decrypt calls `.toLowerCase()`. Uppercase `A–Z` (indices 0–25) fold to
   `a–z`. To make the payload round-trip **exactly**, restrict payload to `[a-z0-9-_]`.
   (`lqr` ids are lowercase hex today, so this is natural.) The **nonce** may use any `a64`
   char — it is discarded.
3. **Even ciphertext length.** Always 2 chars per symbol; never emit an odd-length body.
4. **Nonce = exactly 24 symbols.** Decrypt strips 24. Fewer/more → payload misaligned.
   Nonce must be CSPRNG-random and single-use.
5. **Key identity.** Same `ftzSecretSixCode` on both sides. There is no MAC — the cipher
   does not authenticate. A wrong key does **not** return silent garbage: the keystream
   drifts, `xor` exceeds 63, and `a64[xor]` **throws `RangeError`** (verified — see the test
   in §9). `aecDecrypt` wraps every attempt in try/catch, so on-device a bad key surfaces as
   a failed/`errorString` result, not a crash. Real validation is downstream: the decrypted
   payload must match a registered code (see §10).
6. **No integrity/auth.** AEC v2 is confidentiality-only. Anyone with the shared key can
   forge codes. Treat the shared key as a real secret. (Asset QR uses a separate AES path,
   `assetVerify`/`aesDec`, out of scope here.)

---

## 9. Golden test (mandatory before ship)

The runnable check: **round-trip**, and **cross-validate against the app's Dart**.

```js
// (a) self round-trip — with a FIXED nonce so it's deterministic
const KEY = /* the real ftzSecretSixCode hex */;
const nonce = "AAAAAAAAAAAAAAAAAAAAAAAA";          // 24 chars, test-only
const ct = aec2Encrypt(KEY, "l0a1b2c3", nonce);    // -> "2...."
console.assert(aec2Decrypt(KEY, ct.slice(1)) === "l0a1b2c3", "JS round-trip failed");
```

```
// (b) cross-check against the real cipher (authoritative)
//     Paste ct.slice(1) into a Dart test that calls aec2Decrypt(getAecKey('6')!, ct)
//     and assert it equals "l0a1b2c3". If (a) passes but (b) fails, the JS port
//     diverged from auth_crypto.dart — fix the JS, not the Dart.
```

Also verify a **real scan**: generate `"2"+out` (or the `/qr/` URL), scan on-device, confirm
`lqrVerify` returns the payload (non-error) and it resolves against `#LQR_LIST` / `#TABLE<code>`.

---

## 10. Payload semantics (backend-owned)

Decrypt returns the raw payload string; the app then matches it against a registered
location code (`#LQR_LIST`, or `#TABLE<code>`). The exact payload format (e.g. a leading
`l` tag like `makeLqrCode`, an id length, checksums) is **defined by the backend/Sheet**,
not by the cipher. Whatever you encrypt is whatever the app must find in its registry —
keep them in sync.

# Profile exchange between iPhone and Android

Status (19 November 2026): the radio-independent half is built and tested
(`Features/Match/Exchange/ExchangeWire.swift`, `InteropVectorsTests`). The
iPhone still exchanges over MultipeerConnectivity; the Bluetooth LE transport
below is the remaining step and needs two real phones to test.

## Why a new transport

| Today (iPhone ↔ iPhone) | Works with Android? |
| --- | --- |
| MultipeerConnectivity finds the other phone and encrypts the link | No: Apple only. |
| NearbyInteraction (UWB) measures 15 cm | No: iPhone-to-Android UWB is not available to apps. |
| QR code (`ProfileCode`) | Yes, one way. Already cross-platform. |

Bluetooth LE is the one radio both platforms let apps use to find and talk to
a phone nearby. It is slow (tens of kB/s) and its own pairing isn't something
an app can rely on, so the app encrypts and frames everything itself.

## Protocol v2

Everything in this section is implemented in `ExchangeWire` and pinned in
`interop/vectors.json` (section `exchange`).

1. **Discovery.** Each phone advertises a GATT service with a fixed 128-bit
   UUID (to be chosen once, never changed) and scans for it. RSSI above a
   tuned threshold stands in for "held together"; tapping **Exchange** on both
   phones remains the fallback, exactly as today. Between two iPhones, UWB may
   still confirm the distance.
2. **Characteristics.** One writable characteristic per direction
   (`write without response`), one notify characteristic for the reply.
3. **Hello (49 bytes).** `0x02` ‖ X25519 public key (32) ‖ random nonce (16).
   A different first byte is another protocol version and is refused.
4. **Keys.** `shared = X25519(own private, their public)`. Order the two
   public keys bytewise; "first" is the smaller. Then
   `HKDF-SHA256(shared, salt = firstNonce ‖ secondNonce,
   info = "stopswiping-exchange-v2" ‖ firstKey ‖ secondKey, 72 bytes)`:
   bytes 0–31 encrypt first→second, 32–63 second→first, 64–71 (big-endian,
   mod 1 000 000, six digits) are the confirmation code both screens can show.
5. **Messages.** ChaCha20-Poly1305 per direction, nonce = 4 zero bytes ‖
   64-bit big-endian counter starting at 0, associated data
   `"stopswiping-exchange-v2"`. Wire form: ciphertext ‖ 16-byte tag.
   A message out of order, repeated or altered fails and ends the session.
6. **Framing.** 4-byte big-endian length ‖ sealed message, cut into pieces of
   the negotiated MTU (at least 20 bytes). Messages above 256 KiB + tag are
   refused before anything is buffered.
7. **Content.** The same `ProfileExchangeMessage` sequence as today (`hello`,
   `ready`, `photo`, `profile`, `decline`, message version 2) and the same rules
   (`ProfileExchangeNegotiation`): a profile only travels after both sides are
   ready, and only sealed (`ProfileCode.sealed`, the same bytes as a QR code;
   see [match privacy](match-privacy.md)). With Skip the Android app runs this
   exact Swift, so its JSON is identical. A photo (≤ 180 kB) takes a few seconds over BLE; the screen
   should say so.

## What changes on the iPhone

Nothing yet. When the BLE transport is added:

- `ProfileExchangeSession` gets a transport protocol; MultipeerConnectivity and
  BLE both implement it, and the negotiation stays as it is.
- iPhones keep MultipeerConnectivity + UWB between themselves (faster, measured
  distance) and use BLE when the other phone is Android, or advertise both.
- `Info.plist` needs `NSBluetoothAlwaysUsageDescription` (Dutch and English).
- The privacy text should mention Bluetooth (check the consent version rule in
  `PrivacyConsent.swift` before changing that copy).

## Tests

- `InteropVectorsTests`: RFC 7748 X25519 check, both phones derive the same
  channel and code, replay/reorder/tamper refused, framing at MTU 20/182/512,
  and the pinned bytes in `interop/vectors.json`.
- Still to test on devices: discovery, RSSI threshold, throughput, background
  behaviour, iPhone ↔ Android.

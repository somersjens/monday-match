# What a match shows about the other person

Decided 19–20 November 2026, before launch. Seeing every answer of the other
person let anyone copy what someone looks for and fake a 100% match. Now a
match shows **scores per category with their weights**, never a single answer,
and manual matching still works between two phones only, without the server.

## What the screens show

The score sheet (`MatchScoreDetailView`) has three views: **Together**,
**You → them** and **Them → you**. Each lists the seven categories of the
question catalog (`CompatibilityCategory`, the sections of
`CompatibilityScaleQuestion`) with a score and a weight:

* **score**: Σ weight × closeness ÷ Σ weight over that category's questions,
  exactly as the total score is computed (`MatchWeighting`: importance
  1–5 counts 0/1/2/4/8; closeness falls linearly over the 1–5 scale);
* **weight**: that category's share of all weight in that direction;
* Σ weight × score over the categories **is** the total score, so the server's
  formula (`matching_private.compatibility_score`) is unchanged;
* **Together**: each category weighs the average of its two shares, and its
  score is the two scores weighed by those shares. Σ is the average of the two
  totals, the number in the heart. Rounding to whole percents can make the
  visible sum differ by 1%, which the sheet says.

A category whose questions all have importance 1 has no score ("–") and weight
0. When nothing matters to someone at all, their score is 100 and each category
counts by its number of questions.

The profile sheet and the PDF export show name, age, area, distance and the
basic answers (height, gender, religion, languages, children, substances…),
no longer the 1–5 answers.

What the categories still reveal: the other person's weight per category (you
know your own share, so theirs follows from the shared weight). That is seven
coarse numbers and was accepted.

## Frozen when matched

`MatchSnapshot` stores a `MatchResult`, computed **once** when the profiles
meet: both scores, every category's fit and share per direction, and the
requirements either side fails (as `MatchIssue` values, worded on display so a
rename or a language switch still works). It is never computed again: a later
profile edit, a new question catalog or a new formula leaves a kept match as it
was. Of the other person only `ProfileCreationState.shownCopy()` is stored:
what the screens show, without their 1–5 answers, wishes, importance, age and
height ranges or search radius.

* Saved matches: `savedMatches.v2` (the old `v1`, which held whole profiles,
  is removed on launch and on profile deletion). Same for `openDemoChat.v2`.
* Server matches: `LiveMatchCenter` works the result out the first time the
  partner's card is on the phone, with the server's two scores, and keeps it
  under `liveMatch.result.<id>`.

## Sealed profiles (`ProfileSeal`, `ProfileCode` v3)

The whole profile still goes to the other phone (both directions need it),
but sealed: QR code, radio exchange and the server's match card all carry the
same bytes.

    sealed    = version 3 (1) ‖ key number (1) ‖ nonce (12) ‖ ciphertext ‖ tag (16)
    plaintext = minutes since 2026-01-01 UTC (3) ‖ holder (6) ‖ packed profile

ChaCha20-Poly1305 with the first two bytes as associated data; any changed byte
is refused. The packed profile is the bit layout of `ProfileCode.encoded`
(packing version 3: no `completedAt`, 1–5 answers in 7 bits each). The camera
link is unchanged: `https://www.hakketjak.com/stop-swiping/code#<base64url>`.

**The key** lives in the app; phones that meet without a server can't do
otherwise. It is never stored as one value: it is derived at run time (HKDF) from
tables that don't look like a key, and each key number gives another key. To
rotate, add a number, seal with it, and drop the old one from
`readableKeyNumbers` once old versions no longer matter. **Accepted**: someone
who takes the app apart (or reads this repository's source) can unseal codes.
The goal is that nobody sees another person's answers in the app, in a QR
reader, on the website or in the database.

## Rules for QR and radio

| | QR code / link | Phone to phone | Server match card |
| --- | --- | --- | --- |
| One-way | Yes: whoever scans sees the match | Both sides | — |
| Expires | 24 h after it was made (a code on screen is made afresh each time it opens), up to 1 h of clock skew | Never | Never |
| Server involved | No | No | It stores the sealed card only |

An expired or otherwise unreadable profile code makes the in-app scanner say
the code has expired and to ask for a fresh one; any other QR code still reads
as "not a Stop Swiping code".

**Speed dates**: one code can be scanned by many people all evening, and two
people who each scan the other both see the match.

**Scanning someone again** (`ScannedMatchMemory`): each phone has a random
6-byte `ProfileHolder`, sealed into every code and exchange. For 24 hours, the
same person again (same or fresh code, same or changed own answers) brings
back the first outcome. Changing your own answers and rescanning therefore
reveals nothing about what they look for. Deleting the profile clears the memory
and makes a new holder.

**QR density**: sealing makes codes longer. A usual profile is version 11
(61 modules). The longest possible profile would be version 12 at medium error
correction, which didn't scan at every moment of the light's sway, so
`WelcomeLightCode.Matrix(profileLink:)` switches to low error correction
whenever medium would exceed 61 modules. `ProfileCodeTests` renders both
profiles at three moments and reads them back.

## Android

Nothing here is Apple-only: CryptoKit's ChaCha20-Poly1305 and HKDF (like
`ExchangeWire`), plain bit packing, JSON messages. `interop/vectors.json` pins
a sealed code (fixed nonce and holder), its packed bits and the per-category
scores both ways; the Android build must reproduce them.

## Tests

`MatchPrivacyTests` (categories add up, nothing stored, frozen results, live
matches computed once, scanning again), `ProfileCodeTests` (sealing, tampering,
expiry, holder, scanning the light), `ProfileExchangeTests` (only sealed bytes
on the wire), `InteropVectorsTests`, `MatchReportExportTests` (no single answers
in the PDF).

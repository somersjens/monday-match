# Asking for a review

Set up 20 November 2026. Before that the app never asked for a review and had
no link to the store page.

## When the store's review sheet may appear

Only right after a moment someone is plainly glad about, and only once the
home screen is calm again:

| Moment | When it counts |
| --- | --- |
| A match in person | A scanned code or two phones together give a **match**, and it isn't a repeat of a comparison from the last 24 hours. |
| A real conversation | An automatic match where **both** people wrote at least 3 messages, the match is still on, and the person closes the chat. |

Each match counts once, however often it is reopened. The demo never counts.

The app then waits until the match has closed and the helix is back home
(about 3.4 seconds, 1 second with Reduce Motion), and asks only if by then
nothing else is going on: the app is in front, no other screen, sheet, paywall,
demo or match is open, no report thank-you or moderation notice is on the home
screen, and the account isn't suspended. Otherwise the moment passes and is
**not** asked about later, out of context.

On top of that, all of these must hold (`ReviewPromptLedger`):

- the app was first opened at least **3 days** ago, on at least **3 different days**;
- nothing went wrong in the last **7 days**: no match, a match that ended
  (by either person), a report sent, or a moderation notice;
- the app hasn't asked in **this version**, nor in the last **120 days**.

Apple shows its sheet at most three times in 365 days and decides itself
whether it appears; Google uses its own, undisclosed quota. Neither tells the
app what happened, so the ledger counts every request as asked.

What the app never does, because both stores forbid it or it backfires:

- ask its own "Do you like Stop Swiping?" first and send only happy people to
  the store (review gating);
- offer anything in return for a review;
- call the review sheet from a button (it may not appear, so the tap would
  seem broken);
- ask during onboarding, the paywall, a chat, a match animation, or after a
  no match, a report or a strike.

## Always available

**Rate Stop Swiping** in the profile overview (above Delete profile) opens the
App Store straight on the review form
(`https://apps.apple.com/app/id6830641479?action=write-review`). On Android it
opens the Play listing on its reviews; Google has no link to the form itself.
The row hides on Android until the package name is filled in.

## Where it lives

| What | Where |
| --- | --- |
| Rules, ledger (UserDefaults `reviewPrompt.ledger.v1`, never leaves the phone), the platform request | `Stop Swiping/Core/Reviews/ReviewPrompt.swift` |
| Store links, App Store id, Play package name | `Stop Swiping/Core/Reviews/StoreListing.swift` |
| Good moments, setbacks, the calm-screen check | `Features/Welcome/WelcomeView.swift` (`presentScanned`, `closeMatch`, `askForReviewWhenCalm`, `breakMatch`, `reportMatch`) |
| The row | `Features/ProfileCreation/ProfileOverviewView.swift` |
| Tests | `Stop SwipingTests/ReviewPromptTests.swift` |

## Testing it

- In a **debug build** from Xcode, iOS shows the sheet every time it is asked
  (nothing is submitted). Delete the app or the `reviewPrompt.ledger.v1` key
  to start over; the 3-day rule means a fresh install won't ask on day one.
- In **TestFlight** the sheet never appears. In the App Store build Apple decides.
- Unit and UI test runs never ask.

## Google Play (Android via Skip)

The rules and the ledger are plain Swift and work unchanged under Skip. Two
things are Android-specific:

1. **The sheet.** `ReviewRequesting` gets an Android implementation using
   Google's [Play In-App Review API](https://developer.android.com/guide/playcore/in-app-review):
   add `com.google.android.play:review` (and `review-ktx`) to the Android
   module, then:

   ```kotlin
   val manager = ReviewManagerFactory.create(activity)
   manager.requestReviewFlow().addOnCompleteListener { request ->
       if (request.isSuccessful) manager.launchReviewFlow(activity, request.result)
       // On failure: do nothing. Never fall back to opening the store.
   }
   ```

   Call `requestReviewFlow()` only when `ReviewPromptCenter` decides to ask,
   not ahead of time; the `ReviewInfo` it returns expires.
2. **The store link.** Set `StoreListing.playPackageName` once the package
   name is chosen (see [Android readiness](android-readiness.md)).

Testing on Android: the sheet only appears for an app installed **from Google
Play**. Use internal app sharing or an internal testing track; a sideloaded
debug build gets nothing. `FakeReviewManager` exercises the flow in tests.
Google's quota is stricter than Apple's, which the 120-day spacing already
respects.

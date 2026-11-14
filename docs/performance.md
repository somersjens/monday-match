# Performance checks — 13 November 2026

Tapping a compatibility answer rebuilt all compatibility questions and their localized
strings multiple times while SwiftUI refreshed the header, controls and footer.
Questions and step lookups now use an immutable catalog cached per language.
Changing language still invalidates visible text through Observation.

Answer setters publish one consistent update and skip unchanged values. Selection
colors update immediately; the small scale animation takes 160 ms. The previous
450 ms animation on the entire compatibility form has been removed.

Other changes:

- Profile reads reuse the decoded in-memory draft, including photo bytes. The
  shared file repository updates its cache only after a successful save/delete.
- The profile overview creates sections as they come into view.
- Labels without interpolation skip the regular-expression formatting path.
- The dimmed background light uses 30 fps during onboarding; the main artwork
  keeps 60 fps. Both Metal and Canvas use the same policy.
- Photo decoding downsamples directly to at most 1600 pixels with orientation
  applied. It previously resized using display-scale points, allowing 4800-pixel
  output on a 3× display. Both photo pickers process images off the main actor.

## Before/after measurements

Same iOS 27 simulator, same Debug build settings, ten measurement iterations.
Times below are means per complete benchmark, not end-to-end tap-to-display
latency. GPU rendering, touch delivery and animation duration are not included.

| Benchmark | Work per iteration | Before | After |
| --- | --- | ---: | ---: |
| Answer updates and visible screen data | 100 answer changes plus header/footer reads | 149.74 ms | 0.68 ms |
| Profile overview data | 10 passes over all profile steps | 238.83 ms | 5.25 ms |
| Repeated profile reads | 20 reads with 512 KiB photo data | 11.30 ms | 0.01 ms |
| Static localization | 6000 label lookups | 9.89 ms | 6.86 ms |

Run the repeatable benchmarks with:

```sh
xcodebuild test -project 'Stop Swiping.xcodeproj' -scheme 'Stop Swiping' \
  -destination 'platform=iOS Simulator,id=D565F7A3-F156-49F0-8F9E-E7D1C573D4AE' \
  -only-testing:'Stop SwipingTests/AppPerformanceTests' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

`PerformanceRegressionTests` checks atomic selection updates, unchanged selections,
cached language changes, file-cache consistency after successful and failed
writes, photo capacity, pixel limits, orientation and background processing.
The complete unit/rendering suite passed: **160 tests, zero failures**.


## Name field — 14 November 2026

The home name field previously stored keyboard focus in `WelcomeView`. Tapping
it invalidated the entire welcome layout, including the live artwork. Keyboard
size changes could also feed back into the geometry state. Focus now belongs to
`ProfileNameCard`, and its focus change no longer applies an implicit animation
to the whole input card. The light retains its largest canvas size at the current
width while the keyboard resizes the controls, avoiding drawable/texture resizing.
Name text stays local to the card until submission.

This removes avoidable layout work from the focus path. Simulator builds and
regression tests pass; cold keyboard startup latency still needs observation on
a physical iPhone and is not covered by the benchmark timings above.

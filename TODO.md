# TODO

## Known issue: Back button leaves FLauncher when opened via the Home-button override

Since the Home-button-override introduced in `HomeButtonAccessibilityService.kt`, FLauncher is
launched as a regular Activity on top of the existing task stack rather than being registered as
the actual system default launcher (that's the whole point — it avoids disabling the stock
launcher, which keeps things like the remote's YouTube button working, see README).

Consequence: while sitting at FLauncher's home screen, pressing the remote's Back button pops
FLauncher off the stack and reveals whatever was underneath — the stock launcher — instead of
staying put, which is what a "real" default launcher does (Back does nothing on an actual home
screen).

This happens because `AppsService.isDefaultLauncher()` (via `MainActivity.isDefaultLauncher()`)
checks the system's actual resolved default HOME activity, which is genuinely not FLauncher in
this setup, so `shouldPopScope()` in `flauncher_app.dart` always allows the pop.

Possible fixes to explore, if this turns out to matter in daily use:
- Intercept Back the same way Home is intercepted, in `HomeButtonAccessibilityService`, and just
  no-op it while FLauncher is in the foreground.
- Or: give `flauncher_app.dart` a way to know "I was opened via the Home-button override" (e.g. a
  platform channel flag from the accessibility service) and treat that the same as
  `isDefaultLauncher() == true` for purposes of `shouldPopScope()`.

Not fixed for now — acceptable as-is.

## Other open items

- Upgrade Flutter from 3.7.5 (current pinned version, see `.fvmrc`) to the latest stable release.
- Test the Home-button-override approach on the real Google TV Streamer 4K, not just the
  `GoogleTV_API31` emulator — confirm accessibility-service key interception behaves the same on
  real hardware/remote as it does with adb-injected key events on the emulator.

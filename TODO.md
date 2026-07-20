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

- The YouTube-button keycode in `HomeButtonAccessibilityService.kt` (190 / `KEYCODE_BUTTON_3`) was
  identified empirically on one specific Google TV Streamer 4K remote. Other Google TV
  devices/remotes may send a different code for that button, in which case it won't do anything
  until re-identified (temporarily log all key events in `onKeyEvent` and press the button again).

~~Test the Home-button-override approach on the real Google TV Streamer 4K, not just the
`GoogleTV_API31` emulator~~ — done: confirmed working on real hardware, including the YouTube
button override.

- **Revisit the dormant Unsplash wallpaper source** (`unsplashEnabled` hardcoded `false` in
  `lib/providers/settings_service.dart`, see `DRIFT.md`). Decided during `UPGRADE_PLAN.md`'s
  Phase 3 (2026-07-20) to leave `unsplash_client` on its current `^2.1.0+3` pin rather than bump
  to the breaking 3.0.0 release, since the code path doesn't run — but flagged for an actual
  decision later: get a real Unsplash API key and re-enable it, or remove the dependency and UI
  entirely if it's not worth reviving.

- **Focus jumps to "Add Category" after reordering with exactly 2 categories**
  (`lib/widgets/settings/categories_panel_page.dart`). Each row's up/down arrow `IconButton` is
  disabled (`onPressed: null`) once the row is first/last. With exactly 2 categories, moving either
  one always lands it at the opposite extreme in a single step, so the arrow button the user just
  pressed becomes disabled immediately after the move — Flutter then hands focus to the next
  focusable widget in traversal order, which happens to be the "Add Category" button below the
  list, instead of somewhere less jarring (e.g. the row's other, still-enabled arrow, or the row
  itself). With 3+ categories a single-step move usually doesn't land on an extreme, so the pressed
  button stays enabled and focus doesn't jump — which is why this only reproduces at exactly 2.
  Found during Phase 4 manual testing (2026-07-20), pre-existing behavior unrelated to the upgrade.
  Possible fix: after `_move()`, explicitly request focus on the moved row's remaining enabled
  arrow (or the row itself) instead of leaving it to Flutter's default disabled-widget fallback.

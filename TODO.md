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

**Decided (2026-07-20): not fixing this in-app.** The advised path for anyone who cares about
correct Back-button behavior is to actually set PitchforkLauncher as the real default launcher
(`adb shell cmd package set-home-activity`, or README's "Option A: make it the real default
launcher") rather than relying on the Home-button-override for that specific case —
`isDefaultLauncher()` then genuinely returns `true` and `shouldPopScope()` behaves correctly with
no code changes needed. This project
isn't published on the Play Store; anyone sideloading it who hits this and doesn't set themselves
up as real default launcher is an accepted edge case, not worth building around.

## Other open items

~~The YouTube-button keycode in `HomeButtonAccessibilityService.kt` (190 / `KEYCODE_BUTTON_3`) was
  identified empirically on one specific Google TV Streamer 4K remote. Other Google TV
  devices/remotes may send a different code for that button, in which case it won't do anything
  until re-identified.~~ — non-issue: it's just the default/example mapping, seeded once; any user
  can remap it themselves in Settings → Remote buttons regardless of what code their own remote's
  button actually sends.

~~Test the Home-button-override approach on the real Google TV Streamer 4K, not just the
`GoogleTV_API31` emulator~~ — done: confirmed working on real hardware, including the YouTube
button override.

- **Revisit the dormant Unsplash wallpaper source** (`unsplashEnabled` hardcoded `false` in
  `lib/providers/settings_service.dart`, see `DRIFT.md`). Decided during `UPGRADE_PLAN.md`'s
  Phase 3 (2026-07-20) to leave `unsplash_client` on its current `^2.1.0+3` pin rather than bump
  to the breaking 3.0.0 release, since the code path doesn't run. **Decided (2026-07-20): yes,
  re-enable it, but user-supplied key only** — bump `unsplash_client` to 3.0.0 and add a settings
  UI where the user pastes in their own Unsplash API key, stored locally; no key ever gets bundled
  in or shipped with the app itself, full stop, regardless of build/distribution channel. Also
  still need a test plan before starting: this is the one wallpaper source that can't be exercised
  without live API credentials, and now specifically needs testing the "no key entered yet" /
  "invalid key" states too, not just the happy path with a working key.

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

- **No confirmation dialog before deleting a category** (`lib/widgets/settings/category_panel_page.dart`,
  the "Delete" `ElevatedButton`'s `onPressed`) — calls `AppsService.deleteCategory(category)`
  immediately, no "are you sure?" step. On a D-pad remote this is one accidental press away from
  irreversible data loss (the category and its app assignments are gone, not just hidden). Checked
  the other destructive actions for comparison: "Uninstall" (`application_info_panel.dart`) is
  guarded by Android's own system confirmation dialog since it goes through
  `REQUEST_DELETE_PACKAGES`, and "Hide" is low-stakes/reversible — category deletion is the one
  genuinely unguarded destructive action. Add a confirmation dialog before calling
  `deleteCategory`. Found 2026-07-20, not yet fixed.

- **Add a grayscale option for the Picsum wallpaper source** (`lib/picsum_service.dart`,
  `lib/providers/wallpaper_service.dart`, `lib/widgets/settings/wallpaper_panel_page.dart`).
  Blur is already implemented (`randomPhoto({int? blur})`, exposed as the "Random photo (blurred)"
  button), and picsum.photos supports a `?grayscale` query parameter the same way it supports
  `?blur=`, so this would be a small, near free addition following the exact same pattern. Not
  urgent, just a nice easy win if picked up. Suggested 2026-07-20.

- **Migrate off `sqlite3_flutter_libs` to `sqlite3` v3.x** (`pubspec.yaml`, `lib/database.dart`).
  Renovate PR #7 wanted to bump `sqlite3_flutter_libs` to `0.6.0+eol` — upstream has deprecated
  the package, since `sqlite3` v3.x native binary bundling moved to Dart's build hooks system and
  `sqlite3_flutter_libs` is no longer needed at all; `0.6.0+eol` strips all code from the package.
  Taking that bump as-is would leave the dependency pinned to a version that does nothing without
  actually adopting the replacement mechanism, risking loss of native SQLite bundling on Android.
  `lib/database.dart` doesn't call any of `sqlite3_flutter_libs`'s APIs directly (no
  `DynamicLibrary.open`, `open.overrideFor`, or `applyWorkaroundToOpenSqlite3OnOldAndroidVersions`),
  it's purely there to bundle the native lib, and drift already requires `sqlite3 ^3.4.0`
  transitively, so most of the groundwork is already in place. The fix: drop
  `sqlite3_flutter_libs` from `pubspec.yaml` entirely and depend on `sqlite3` v3.x directly. Small,
  self-contained change, but do it in its own branch with a real device check (Google TV Streamer)
  rather than riding along on the Renovate bump. PR #7 closed/skipped, not merged. Found 2026-07-21.

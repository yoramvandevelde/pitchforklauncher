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
  to the breaking 3.0.0 release, since the code path doesn't run. Was tentatively decided
  2026-07-20 to re-enable it with a user-supplied API key, but **on hold as of 2026-07-22**: now
  that the Picsum live full-screen preview covers "quickly get a nice random photo" well, Unsplash
  (which needs the user to go create a developer account/API key just to unlock it) looks like it
  wouldn't add much real value. Not picking this up for now; revisit if that assessment changes.
  If it does get picked up: user-supplied key only, no key ever bundled with the app; and it's the
  one wallpaper source that can't be exercised without live API credentials, so budget for testing
  the "no key entered yet" / "invalid key" states specifically, not just the happy path.

~~Focus jumps to "Add Category" after reordering with exactly 2 categories
  (`lib/widgets/settings/categories_panel_page.dart`)~~ — fixed: each up/down arrow `IconButton`
  now gets an explicit, per-category `FocusNode`, and after `_move()` the row's remaining enabled
  arrow is refocused via `addPostFrameCallback` instead of leaving it to Flutter's default
  disabled-widget fallback. Covered by a regression test in `categories_panel_page_test.dart`.

- **Focus-snap on the categories reorder fix feels a bit abrupt.** Confirmed working on the
  `GoogleTV_API34` emulator (2026-07-21), but the corrective refocus lands a frame after Flutter's
  own disabled-widget fallback already moved focus away, so there's a brief hard cut instead of a
  smooth transition. Not a functional bug — just visually a little wonky. Possible follow-up: a
  quick fade-out/fade-in on the focus highlight (fast enough to not feel sluggish) instead of the
  instant snap.

~~No confirmation dialog before deleting a category~~ — fixed (PR #16, 2026-07-22):
`CategoryPanelPage`'s "Delete" button now shows an `AlertDialog` ("Delete category?" / Cancel /
Delete) before calling `deleteCategory`, with focus defaulting to Cancel rather than Delete.

~~Migrate off `sqlite3_flutter_libs` to `sqlite3` v3.x~~ — done (PR #11, 2026-07-21): dropped
  `sqlite3_flutter_libs` from `pubspec.yaml` entirely, depend on `sqlite3` v3.x directly. See
  `DRIFT.md`.

- **Migrate off the Kotlin Gradle Plugin (KGP) to Flutter's "Built-in Kotlin"** before it becomes a
  hard build failure. Surfaced as a WARNING starting with Renovate PR #10 (AGP 8.13.2 -> 9.3.0):
  Flutter's own Gradle tooling (`FlutterPluginUtils.kt`) only emits this check once
  `agpVersion.major >= 9`, which is why it never showed up on `main` (still AGP 8.x) but appears as
  soon as a project bumps past AGP 9 — not something PR #10 broke, just the threshold where
  Flutter's early-warning switches on. Affected plugins in this project: `image_picker_android`,
  `shared_preferences_android`, `webview_flutter_android` — they still apply KGP the old way, and
  need to ship a version that supports Built-in Kotlin before this becomes a real build failure
  (guide: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers).
  Not actionable from this repo alone — depends on upstream plugin authors — so just keep an eye on
  their changelogs when doing routine dependency bumps. Found 2026-07-21.

~~Concept: live full-screen preview for the Picsum wallpaper picker~~ — done (2026-07-21):
`WallpaperPanelPage`'s "Random photo" now closes the Settings panel and pushes
`WallpaperControlBar`, a bottom bar with Random/Black & White/Blur controls, live over the actual
home screen (`PageRouteBuilder(opaque: false)`). Subsumes the earlier "Add a grayscale option"
item. See `DRIFT.md` if a short writeup gets added there; implementation is
`lib/widgets/wallpaper_control_bar.dart` + `lib/picsum_service.dart`'s id-capturing rewrite.

~~B&W/Blur toggles were interactive even when there's no current Picsum photo to apply them to~~
— fixed (2026-07-21): `WallpaperService.hasCurrentPicsumPhoto` exposes whether a photo is
currently set, and `WallpaperControlBar` disables (grays out) both switches until it's true.
`_currentPicsumPhotoId` is also now cleared whenever the wallpaper source changes away from Picsum
(`pickWallpaper`, `setGradient`, `randomFromUnsplash`, `setFromUnsplash`).

~~No transition when the photo changes under a filter toggle~~ — fixed (2026-07-21):
`WallpaperService.wallpaperVersion` bumps on every wallpaper/gradient change, keying an
`AnimatedSwitcher` around the background in `FLauncher` so it cross-fades (200ms) between the old
and new wallpaper. Applies to every wallpaper source, not just Picsum toggles.

~~The cross-fade visibly dips in brightness partway through~~ — fixed (2026-07-22), confirmed gone
on real hardware: was a genuine artifact of the naive two-layer alpha crossfade (old 100%→0%, new
0%→100% simultaneously means both are ~50% opaque at the midpoint, letting the dark canvas
underneath bleed through). Fixed by confining `switchInCurve`/`switchOutCurve` to
`Interval(0.0, 0.5, ...)` each on `FLauncher`'s `AnimatedSwitcher` — since the outgoing entry's
controller runs in reverse, this makes the incoming photo reach full opacity by the midpoint and
the outgoing one only start fading (invisibly, now hidden under the opaque new layer) after that,
so at least one layer is always fully opaque and the background never shows through.

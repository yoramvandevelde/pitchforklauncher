# TODO

## Open

- **Migrate this app's own `android/app/build.gradle` to Built-in Kotlin.** Follows directly from
  the KGP fix below: with both plugins fixed, the *only* remaining KGP warning is our own module
  still applying `id "org.jetbrains.kotlin.android"` directly. See
  https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers.
  **Blocked on Flutter 3.47 (2026-07-30):** tried it (drop the plugin line, flip
  `android.builtInKotlin=true` in `gradle.properties`, declare KGP in `settings.gradle`'s plugins
  block, replace `kotlinOptions { }` with the `kotlin { compilerOptions { } }` DSL) and it fails at
  build time regardless of correct config: `flutter_tools/gradle`'s
  `FlutterPluginUtils.detectApplyingKotlinGradlePlugin` (in the pinned 3.44.8 SDK) unconditionally
  force-applies `kotlin-android` onto every AGP subproject that doesn't declare KGP itself —
  including plain-Java plugins like `flutter_plugin_android_lifecycle` — with no gating on the
  `android.builtInKotlin` flag. That directly conflicts with AGP 9's built-in Kotlin, which refuses
  the old plugin ID once applied elsewhere in the same build, so `assembleDebug` fails inside AGP's
  own `com.android.internal.library` plugin application. Confirmed via the official migration doc:
  "Enabling built-in Kotlin requires Flutter 3.47 or later". As of 2026-08-06, 3.47 is in active
  beta (`3.47.0-0.4.pre`, landing roughly weekly since the 2026-07-07 branch cutoff, Flutter's own
  schedule targets "August 2026" for stable) — getting close, revisit in a couple of weeks.

- **Add `dart format --set-exit-if-changed` as a CI gate.** Recommended by the 2026-08-07 Kimi
  review pass (`REVIEW.md`). Not as simple as adding the CI step: running it today would reformat
  **65 files**, mostly tests. Not a line-length issue (tried `analysis_options.yaml`'s
  `formatter: page_width: 120` first, no effect) -- it's Dart's newer "tall style" formatter
  (current pin: Dart 3.12.2 via Flutter 3.44.8) wanting different indentation/nesting for
  `when(...).thenAnswer((_) => ...)`-shaped test code that was last formatted under an older
  style. E.g. `when(x).thenAnswer((_) => Future.value([...]))` currently keeps the callback and
  its body inline; the new style breaks the callback onto its own line and adds trailing commas
  throughout, which in turn keeps list/map literals multi-line instead of sometimes collapsing
  them. Purely stylistic, no functional change, but it touches most of `test/` at once -- worth
  doing as its own dedicated reformat pass (one big, boring, easy-to-review diff) before adding
  the CI gate on top of it, not bundled into something else. Noted 2026-08-08, not yet done.

- **At leisure, from the same review:** the accessibility service only consumes `ACTION_UP`
  (`HomeButtonAccessibilityService.kt`) -- for Home and mapped buttons the `ACTION_DOWN` falls
  through to the foreground app/system while `UP` is hijacked, the classic shape of a
  both-things-fire bug on other firmware even though it works fine on this hardware; standard fix
  is to also consume `DOWN` for any keycode being claimed, tracked until its matching `UP`. The
  `AppsService` `EventChannel` listener for `PACKAGE_ADDED`/`PACKAGE_CHANGED` is async and
  unserialized, so two events arriving close together (an app update) can interleave
  persist/reload and briefly publish stale state -- self-healing on the next event, but a one-line
  queue/dirty-flag would close it. `CandidateNode` in `lib/custom_traversal_policy.dart` is a pure
  ceremony wrapper around `FocusNode` that's immediately unwrapped elsewhere -- would read better
  as `List<FocusNode>` end to end.

- **`AppsService` micro-inefficiencies, all currently harmless at this app's data sizes.** From the
  2026-08-07 Kimi review pass, unverified against the running app: `_refreshState()`'s
  `Future.forEach` over `appsRemovedFromSystem`'s `applicationExists` checks runs one
  platform-channel round-trip at a time (list is almost always empty, but `Future.wait` would
  collapse the round-trips when it isn't); `categoriesWithApps` allocates a fresh list +
  `UnmodifiableListView` per category on every access, so `Selector`s reading it
  (`categories_panel_page.dart`, `add_to_category_dialog.dart`) always see a new instance and
  rebuild on every notification regardless of whether anything relevant changed -- a cached wrapper
  invalidated on mutation would make them properly selective; the system-vs-database diff is an
  O(n·m) linear scan that a `Set` of package names would make O(n).

## Done

~~**PitchforkLauncher may list itself.**~~ — fixed (2026-08-09), confirmed on-device first (it did,
via a mountain-photo banner card matching the app's own `@drawable/banner` exactly). Went through
two wrong shapes before landing here -- worth recording why, since both looked reasonable in
isolation:
- First attempt: filter it out of `MainActivity.queryIntentActivities` entirely
  (`it.packageName != packageName`). Too broad -- this also removed it from `getApplications()`'s
  result, so it stopped showing up in the Applications panel too, not just off the home screen.
  Nobody should be *unable* to have it there if they want it.
- Second attempt (still too much): keep it out of `queryIntentActivities`, but also force-delete
  any already-synced stale entry from the database via a new `_refreshState()` special case. Wrong
  on principle, not just scope -- this app doesn't remove things from a user's database as a side
  effect of a code change, ever. The database isn't ours to edit once it exists.
- **What actually shipped:** `queryIntentActivities` is unchanged -- PitchforkLauncher's own
  package still flows through `getApplications()` normally, gets persisted like any other app, and
  shows up in the Applications panel same as before. The only change is in
  `AppsService._initDefaultCategories()` (the one-time seed that only runs on a genuinely fresh
  install/database): its own package is excluded from the automatic TV/Non-TV sort, so it doesn't
  land in a default category by itself. Nothing stops anyone from adding it to a category manually
  from the Applications panel afterward, exactly like any other app -- this only skips the
  *automatic* placement, it doesn't block the outcome. Added a regression test
  (`apps_service_test.dart`: "excludes PitchforkLauncher's own package from the default category
  seed") asserting both halves: it's still `persistApps`'d, but never `insertAppsCategories`'d by
  the seed. Verified on a genuinely fresh emulator install (`just uninstall` + `just build-install`):
  no self-entry on the home screen.

~~**Fetch `versionName` lazily instead of in the bulk sync.**~~ — decided (2026-08-09): not doing
this. At this app's actual scale (a personal launcher, a few dozen installed apps at most) the
extra binder round-trip per app is genuinely negligible, and the real cold-start costs in this area
(icon/banner encoding and decoding) were already addressed separately (see the two entries above).
Moving `versionName` to an on-demand channel method would still be a reasonable change in the
abstract, just not worth the added surface for a cost that isn't actually being felt.

~~**`app_card.dart`'s `_animation.forward()`/`.stop()` calls living inside a `Selector` builder.**~~
— decided (2026-08-09): not doing this. Both calls are idempotent, so calling them from a `build`
method causes no observable bug -- moving them to a focus-change listener would be marginally more
idiomatic, but that's a stylistic preference, not a fix for anything broken. Leaving as-is.

~~**Add the GPL header to `lib/widgets/color_helpers.dart`.**~~ — done (2026-08-09): added, with
both Fesser's and this project's copyright lines, matching every other source file.

~~**`FilterQuality.high` + codec-side target size in `_resizeToScreen`.**~~ — landed half of this
(2026-08-09), the other half turned out to be a latent bug, not a one-liner. **Shipped:**
`Canvas.drawImageRect`'s one-time crop-and-scale bake now uses `Paint()..filterQuality =
FilterQuality.high` instead of the default nearest-neighbor, fixing visible aliasing/moiré on a
downscaled photo. **Rejected: codec-side target size on `instantiateImageCodec`.** The suggestion
was to pass the already-computed cover-scaled `targetWidth`/`targetHeight` so the codec
sample-decodes instead of decoding at full resolution first. Verified empirically (a throwaway
test, not kept) before implementing, since this is exactly the kind of thing worth checking against
the real SDK rather than trusting a review's phrasing: an 800x400 (2:1) source decoded with *both*
`targetWidth: 100` and `targetHeight: 100` came back as exactly 100x100 -- `instantiateImageCodec`
does not letterbox or preserve aspect when both dimensions are given, it distorts to fill them
exactly. That would silently stretch/squash almost every real photo (only ones that already happen
to share the screen's exact aspect ratio would be unaffected), since the whole reason `_resizeToScreen`
does its own crop-then-scale afterward is that source photos generally *don't* match the target
aspect ratio. The safer-looking alternative -- pass only *one* target dimension, which
`instantiateImageCodec` does scale proportionally (confirmed: the same 800x400 source with only
`targetWidth: 200` correctly came back 200x100) -- isn't safe either: capping only the width means
an extreme-aspect-ratio source (e.g. a wide panorama-style crop) can end up with the *other*
dimension shrunk below what the final cover-crop needs, forcing `drawImageRect` to upscale that
undersized crop region back up to the target size -- reintroducing, via the "optimization" itself,
exactly the blur the crop code exists to avoid. Doing this correctly needs to know the source's
aspect ratio *before* deciding which dimension (if either) is safe to constrain, which means reading
its dimensions cheaply (e.g. an image header parse) ahead of the real decode -- meaningfully more
machinery than a one-line codec hint, for a one-time cost on a user-initiated wallpaper pick (not a
recurring cold-start cost like the banner/icon decode work above). Not worth it at this scope;
left as a plain full-resolution decode.

~~**Downscale icons before PNG-encoding them in `drawableToByteArray`.**~~ — fixed (2026-08-09):
`MainActivity.buildAppMap()` was encoding `loadIcon()` output at full intrinsic resolution
(adaptive icons can be 432x432 or larger) for every installed app on every sync, even though the
largest place an icon is ever displayed is 48 logical px (`applications_panel_page.dart`).
`drawableToByteArray` now takes an optional `maxSize` (aspect ratio preserved, never upscaled past
the source), passed as 192 (still 2-4x oversampled at every display site) only for icons -- banners
are left uncapped, since they're legitimately displayed larger and already downscaled at decode
time on the Flutter side (see the banner-pop-in fix directly below). Cuts PNG-encode CPU on the
background executor, `MethodChannel` payload size, SQLite blob size (stored forever), and later
decode memory pressure. Verified: `flutter analyze --fatal-infos`/`flutter test` (unaffected, no
Dart-side change), a clean emulator install (`just uninstall` + `just build-install`, needed since
the emulator had a version-code mismatch from an earlier debug build) with no crashes and banners
rendering correctly, plus the persisted PNG's own `IHDR` chunk (visible in the debug SQL log)
confirming the encoded size actually landed within the 192 cap. None of the currently-installed
test apps have a bannerless (icon-fallback) card to visually re-check, so that specific path is
verified by code review, not an on-device look.

~~**App-card banners visibly pop in/"blink" on cold start (~100-250ms, noticeable).**~~ — landed
(2026-08-09, PR #65) as two independent fixes, after the originally-planned per-card `frameBuilder`
fade-in (see history below) turned out not to work:

1. **Decode banners/icons at card size, not native resolution.** `Ink.image` was decoding every
   banner/icon at its full intrinsic size (see `MainActivity.drawableToByteArray`) regardless of
   how small the card displays it -- `app_card.dart` now wraps the image provider in
   `ResizeImage.resizeIfNeeded`, targeting an estimate of the card's actual on-screen width derived
   from the category's own layout settings (grid columns / row height), scaled to physical pixels.
   Deliberately approximate (ignores `GridView`/`ListView` padding) since a decode-size hint
   doesn't need to be pixel-exact, and `ResizeImage` never upscales past the source, so an
   over-estimate just means slightly-less-aggressive downscaling, never blur.
2. **Cross-fade the loading-to-grid handoff instead of popping in.** The spinner-to-content swap
   (`FLauncher`'s `Consumer<AppsService>`) was an instant `Consumer` rebuild -- the same kind of
   pop as the per-banner one, just at the whole-screen level. Replaced with an `AnimatedSwitcher`
   cross-fade, reusing the existing wallpaper switcher's curve-confinement trick (`Interval(0.0,
   0.5, ...)` on both `switchInCurve`/`switchOutCurve`, so the wallpaper never shows through
   mid-transition). **The spinner itself was removed, not delay-shown.** A delay-show variant was
   built and measured first (only render `_emptyState()` if still loading after 300ms) -- while
   testing it, logging the grid's actual on-screen Y position over time (not screenshots, which
   turned out unreliable here: Android's own "starting window" task-snapshot can make a cold
   relaunch look instantly fully-rendered for the first frame or two) showed the grid sitting a
   measured, exact 47px lower for the whole transition whenever the spinner was present as an
   `AnimatedSwitcher` sibling. Root cause: `AnimatedSwitcher`'s default `layoutBuilder` centers
   non-positioned children in a `Stack`; the loading slot (small) and the grid (fills the viewport)
   were both non-positioned, so the pair got centered in a box sized to fit both, shifting the
   taller one down for as long as the outgoing loading slot was still a transition sibling. A
   `layoutBuilder` forcing `Alignment.topCenter` fixed it (confirmed: 72.0px steady throughout, no
   jump) and is worth keeping regardless -- but with the spinner gone entirely, there's nothing of
   consequence left to misalign in the first place, and a launch is normally fast enough
   (single-digit ms range) that a spinner would only ever flash anyway. The rare genuinely slow
   load (fresh install seeding default categories, or a device with many more apps) doesn't
   currently get any loading feedback -- accepted trade-off for the simpler, now-provably-correct
   version; revisit if that ever actually bites in practice.

**History: what was tried and rejected before landing on the above.** Root cause was originally
traced to image decode, not staggered data (`AppsService._init()` awaits the full native
`getApplications()` call, banner bytes included, before flipping `initialized`/`notifyListeners()`
-- so every visible category's `AppCard`s mount and start decoding their own banner independently
in the same layout pass, and dozens resolving within a short window reads as one collective
flicker). Considered and rejected reverting the "icon/banner encoding blocks the platform thread"
fix (Done, below) -- that fix prevents real ANRs as installed-app count grows, an orthogonal and
more serious problem; the decode gap predates it and lives in the Flutter layer regardless. First
attempted fix was a per-`AppCard` fade-in (`AnimatedOpacity` wrapping `Ink.image`, driven by an
`ImageStreamListener` on the resolved image), tested manually on-device: it didn't produce a
visible fade and made loading *feel* slower. Root cause of that failure: `Ink`/`Ink.image` paint
their image via the ambient `Material`'s ink-feature controller (so ripples can render over the
image), a separate paint path from normal `RenderObject` compositing -- an ancestor `Opacity`/
`AnimatedOpacity` has no effect on what `Ink.image` actually paints. Cleanly reverted rather than
patched further, and the whole-screen approach above was built instead.

~~**Pre-crop `assets/default_wallpaper.jpg` to 1920x1080.**~~ — done (2026-08-08): the bundled
asset was 4000x2491 (~3.9 MB), above the Google TV Streamer 4K's actual 1920x1080 render size
(`adb shell wm size` on the real device: `Physical size: 3840x2160`, `Override size: 1920x1080` --
apps render into the 1080p framebuffer, which the TV pipeline then upscales to the panel), so
`WallpaperService._resizeToScreen` fired on every fresh install (decode the ~10 MP JPEG, re-encode
as PNG at 1920x1080) and the resulting PNG was then re-read and re-decoded on every subsequent
cold start. Cropped and scaled the asset itself offline, using the same crop-then-scale math
`_resizeToScreen` applies at runtime (`BoxFit.cover`: scale so the shorter relative dimension
fills the target, crop the overflow on the other axis centered) so the visible composition matches
what was already being displayed -- concretely, crop the original 4000x2491 to a centered
4000x2250 region, then downscale that to 1920x1080. This makes `_resizeToScreen`'s early-return
apply, removing both the first-run encode and the per-start PNG decode; no code change. Also
dropped the file size from 3.9 MB to 2.4 MB as a side effect (re-encoded at high JPEG quality, not
the smaller-but-untested default). Verified: `flutter analyze --fatal-infos` clean, full test
suite (212 tests) passes. Flagged by the 2026-08-08 second-pass review (`REVIEW.md`).

~~**Reconsider the `FLauncher`/`PitchforkLauncher` title split in file headers, and the remaining
bare `flauncher` naming (`pubspec.yaml:1`'s package `name: flauncher`).**~~ — decided (2026-08-08):
**Header title, rebranded in one pass.** All 58 files carrying the decorative project-name line
(56 with Fesser's copyright line, plus 2 wholly-new files that had mistakenly kept saying
`FLauncher` -- an unrelated pre-existing bug, fixed alongside this) now say `PitchforkLauncher`,
including the ones that still carry `Copyright (C) 2021  Étienne Fesser` -- that copyright line
itself, the only part the license actually requires preserving, is untouched everywhere. The
previous incremental split (old files keep `FLauncher`, only touched/new files get the new name)
made sense while this was an actively-rebased fork, where every unmodified line stays a zero-diff
match against upstream for future merges; it stopped making sense once the project settled into
being its own thing, no longer tracking FLauncher's GitLab -- at that point the split just reads as
inconsistent rather than as a deliberate policy. `AGENTS.md` updated to document the new rule and
why the old one no longer applies. **`pubspec.yaml`'s `name: flauncher`, left as-is.** This is a
technical package identifier, not a cosmetic label -- renaming it means rewriting the import prefix
(`package:flauncher/...`) across every file in `lib/`, for zero user-visible benefit (the actual
app identity users see comes from `AndroidManifest.xml`'s `android:label` and the
`io.sifft.pitchforklauncher` application id, both already correctly branded). Common in fork-land
to leave this alone indefinitely given that cost/benefit; not a loose end. Verified: `flutter
analyze`, `flutter test` (comment-only change, unsurprisingly unaffected), and a debug build.

~~**`buildAppMap()` encodes `banner` for every app, including ones that never render through an
`AppCard`.**~~ — fixed (2026-08-08), Route B (of two considered; see the conversation this came
from): `getApplications()`'s bulk sync now takes a `visiblePackageNames` argument -- Dart queries
its own database for which apps currently sit in a visible category *before* calling native, and
`buildAppMap()` only computes `banner` for those (`icon` stays unconditional for everyone, still
needed for the Applications panel's Hidden tab). A new lean `getAppBanner(packageName)` method
covers the moment an app newly becomes visible outside a full sync -- wired into `addToCategory`
and `unHideApplication` (hiding never removes the category-membership row, so unhiding alone can
make an app visible again) via a shared `_ensureBanner` helper that no-ops if a banner is already
present. Deliberately *not* wired into `moveToCategory`: it always moves between two already-visible
categories, so the app already has a banner in practice, and that method already runs inside a
`_database.transaction()` -- adding a platform-channel round-trip inside a DB transaction isn't
worth it for what's realistically always a no-op check. Also deliberately *not* threaded into the
native-initiated `PACKAGE_ADDED`/`PACKAGE_CHANGED`/`PACKAGES_AVAILABLE` `EventChannel` path (which
still always includes the banner): those fire only when an app is installed/updated on the device,
a rare event compared to the bulk sync running on every cold start, so keeping that path simple
outweighed adding native-side visibility-state tracking for it. Verified: `flutter analyze`,
`flutter test` (added coverage for the new visible-package-names argument and the
fetch-vs-skip banner logic, on top of updating ~28 existing stubs across two test files for the
changed `getApplications` signature), a debug build, and a clean emulator install confirming
banners still render correctly on a genuinely fresh install (which exercises the on-demand path via
`addToCategory` during first-run category seeding, since the very first bulk sync runs before any
category exists yet).

~~**Tizen pairing token is stored in plaintext in the settings backup file.**~~ — fixed
(2026-08-08), decided: strip it, both paths. **Deliberate Downloads export:**
`TvInputProfile` gained a `secretParamKeys` getter (empty by default; `SamsungTizenProfile`
overrides it to `{"token"}`), and `TvInputConfig.toJson()` takes an `excludeParamKeys` param;
`SettingsBackupService._buildBackupJson()` looks up each input's profile in `tvInputProfiles` and
passes its `secretParamKeys` through, so the token never makes it into the exported JSON while
`host`/`key` still do. Generic and extensible: a future profile with its own secret just overrides
the same getter, no other file needs to change. **Passive Auto Backup export:** Android's backup
rules only work at *file* granularity, not per-key within a file, and every `shared_preferences`
setting (not just `tv_inputs`) lives in one shared `FlutterSharedPreferences.xml` -- so closing
this path means excluding that whole file from Auto Backup, not just the token. Added
`res/xml/backup_rules.xml` (pre-API 31) and `res/xml/data_extraction_rules.xml` (API 31+, takes
precedence where both exist) both excluding `domain="sharedpref" path="FlutterSharedPreferences.xml"`,
wired via `AndroidManifest.xml`'s `android:fullBackupContent`/`android:dataExtractionRules`
(previously the manifest set `fullBackupContent="true"` as a literal boolean, i.e. no rules file
at all). Trade-off, accepted: the few other `shared_preferences`-backed settings (time format,
animation toggle, button mappings, wallpaper source id) no longer survive a factory-reset/new-device
restore via Google's Auto Backup either -- only via this app's own Backup/Restore feature, which
already covers that scenario deliberately and already strips secrets from its own export. Verified:
`flutter analyze`/`flutter test` (added a `settings_backup_service_test.dart` case exercising the
strip end-to-end, plus a unit test on `SamsungTizenProfile.secretParamKeys`), a debug build (the
new XML files parse correctly -- first attempt used `--` inside an XML comment, which AAPT
rejects), and a clean emulator install with no crashes.

~~**`TimeWidget` ticks every second, permanently.**~~ — fixed (2026-08-08): `_refreshTime()` now
skips `setState` when the tick lands in the same hour+minute as the last one — both display
formats (`Hm`/`jm`) show hour:minute only, never seconds, so those ticks wouldn't have changed
what's on screen anyway. Kept the per-second `Timer.periodic` itself rather than rescheduling to
the next minute boundary: a self-correcting reschedule would cut the wake-ups themselves (60/min
down to 1/min) but adds real complexity (must recompute the delay from the actual wall clock on
every fire, or risk drifting to a fixed arbitrary phase — e.g. permanently ticking at :39 past
every minute — if implemented as a naive `Timer.periodic(minutes: 1)` from whatever moment the
widget happens to init). Traded that root-cause fix for the simpler one; still cuts ~59 out of 60
rebuilds/repaints per minute.

~~**App-card focus-pulse animation runs continuously for every card, not just the focused one.**~~
— fixed (2026-08-08): the `AnimationController` now only runs (`.forward()`) for the genuinely
focused card; every other card calls `.stop()` instead of ticking at 60fps for an always-`null`
border. `.stop()` rather than resetting, so a card that loses and regains focus resumes its color
cycle from wherever it left off. The `AnimatedContainer`/`AnimatedBuilder` widget tree itself stays
mounted regardless of focus (only whether `appHighlightAnimationEnabled` is on gates that) so the
existing 200ms border-appear/disappear transition on focus change is unaffected. Verified via a
clean emulator install: the focused card's border still renders correctly.

~~**MethodChannel handler throws instead of `result.notImplemented()`.**~~ — fixed (2026-08-08):
`MainActivity.kt`'s `else` branch now calls `result.notImplemented()`, the standard Flutter
pattern, instead of throwing `IllegalArgumentException()`. The unchecked-casts half of this item
(e.g. `call.arguments as String`) was left as-is -- that's the normal, idiomatic shape of a Kotlin
MethodChannel handler (every branch in this file does the same), and wrapping each one
defensively would be a materially different, larger change than the "cheap to match" scope this
item was filed under.

~~**`network_image_mock` dev dependency is unused.**~~ — removed (2026-08-08): dropped from
`pubspec.yaml` and `pubspec.lock` via `flutter pub get`.

~~**`TickerModel` is effectively dead code in production.**~~ — removed (2026-08-08): deleted
`lib/providers/ticker_model.dart`, its registration in `flauncher_app.dart`, and
`app_card.dart`'s `Provider.of<TickerModel>(...).tickerProvider ?? this` (now just `vsync: this`,
what production always resolved to anyway). `test/flauncher_test.dart`'s `_pumpWidgetWithProviders`
no longer injects a `TickerModel(tester)` either — turned out unnecessary: `tester.pump(...)`
already drives any `Ticker` in the tree regardless of which `TickerProvider` created it, confirmed
by the full suite (203 tests) still passing, including the focus-navigation test that used to rely
on the injected one. Verified further via a clean emulator install: the focus-pulse animation
still renders on the focused card.

~~**`SettingsBackupStorage.write`/`read` don't sanitize `fileName`.**~~ — fixed (2026-08-08): added
a private `isSafeFileName` check (rejects anything that isn't a bare filename — a path separator,
or literally "." / "..") gating both `write` and `read`. The existing caller's hardcoded filename
trivially passes it, so no behavior change was expected for the actual backup/restore flow —
confirmed manually on the emulator (Backup then Restore both still succeed) rather than assumed.

~~**Icon/banner encoding blocks the platform thread on every app sync.**~~ — fixed (2026-08-08):
`getApplications()` (the `"getApplications"` MethodChannel handler) and the `PACKAGE_ADDED`/
`PACKAGE_CHANGED`/`PACKAGES_AVAILABLE` `EventChannel` callbacks now hop onto the same
`backgroundExecutor` already used for settings-backup I/O, posting the result back via
`mainHandler` — same pattern, no new dependency. Verified via a clean debug install on the
emulator (`just uninstall` + `just build-install`, needed since the emulator had a release build
on it, different signing key): app list loads and renders correctly, `flutter analyze` and the
full `flutter test` suite (203 tests) both pass, no crashes in logcat. **Scope, precisely:** this
fixes *where* the icon/banner encoding runs (off the platform thread), not *how much* of it
happens — every installed app still gets encoded on cold start regardless of whether it's ever
shown. See the `banner`-specific work-reduction item above (Open) for the actual CPU/power
angle.

### Known issue: Back button leaves FLauncher when opened via the Home-button override

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

~~**Stable "latest" download link for the Downloader app (shortcode support).** Downloader
  supports shortcodes that redirect to a fixed URL. GitHub provides a permanent
  `https://github.com/<owner>/<repo>/releases/latest/download/<asset-filename>` link that always
  resolves to the newest non-draft, non-prerelease release's asset with that exact filename — but
  it requires the asset filename to stay identical across releases. `release.yml` currently names
  the asset `pitchforklauncher-${GITHUB_REF_NAME}.apk` (includes the version tag), so it changes
  every release and the `/releases/latest/download/...` link won't work as-is.
  Decided: drop the version from the asset filename (e.g. just `pitchforklauncher.apk`) rather
  than publishing a second, duplicate-named asset alongside the versioned one — a second asset
  named e.g. `-latest.apk` would misleadingly show up attached to *every* past release too when
  browsing old ones on GitHub. No need to keep versioned apk files around for old-version access
  either: every release is a git tag, so an old build is always just `git checkout <tag>` +
  rebuild away. Version identification instead comes from the git tag / release title / in-app
  build-name (`--build-name` is already set from `GITHUB_REF_NAME` at build time), not the
  filename.~~ — done: `release.yml` now names the asset `pitchforklauncher.apk` (no version tag).

~~The YouTube-button keycode in `HomeButtonAccessibilityService.kt` (190 / `KEYCODE_BUTTON_3`) was
  identified empirically on one specific Google TV Streamer 4K remote. Other Google TV
  devices/remotes may send a different code for that button, in which case it won't do anything
  until re-identified.~~ — non-issue: it's just the default/example mapping, seeded once; any user
  can remap it themselves in Settings → Pitchfork Settings → Remote buttons regardless of what
  code their own remote's button actually sends.

~~Test the Home-button-override approach on the real Google TV Streamer 4K, not just the
`GoogleTV_API31` emulator~~ — done: confirmed working on real hardware, including the YouTube
button override.

~~Revisit the dormant Unsplash wallpaper source~~ (`unsplashEnabled` hardcoded `false` in
  `lib/providers/settings_service.dart`, see `DRIFT.md`) — **superseded 2026-07-24: not revisiting,
  removing it instead.** Was already on hold since 2026-07-22 (Picsum's live preview covers the
  need well enough that a user-supplied-API-key flow wasn't worth the friction); with `ADR_001_Project_Scope_and_Feature_Governance.md`
  ADR-001's governance gate now in effect, re-enabling it doesn't clear question 1 (no personal
  irritation it solves) either, so this isn't "on hold pending reassessment" anymore, it's just
  dead code sitting in the base with no path to being turned on.

~~Remove the dormant Unsplash wallpaper source entirely.~~ — done (2026-07-24): the
  `unsplash_client` and `webview_flutter` (only used for the Unsplash author-credit link)
  pubspec dependencies, `lib/unsplash_service.dart`, `UnsplashService`'s registration in
  `flauncher_app.dart`/`main.dart`, `WallpaperService.randomFromUnsplash`/`setFromUnsplash`/
  `searchFromUnsplash`, the `unsplashEnabled`/`unsplashAuthor` settings fields,
  `lib/widgets/settings/unsplash_panel_page.dart` and its route, the wallpaper picker's "Unsplash"
  menu entry and author-credit display in `wallpaper_panel_page.dart`, the ten
  category/random-photo asset images plus `assets/unsplash.png`, and the corresponding tests. The
  bundled default wallpaper's Unsplash-License photo credit (About dialog, license registry) is
  unrelated to this SDK integration and was kept as-is.

~~Focus jumps to "Add Category" after reordering with exactly 2 categories
  (`lib/widgets/settings/categories_panel_page.dart`)~~ — fixed: each up/down arrow `IconButton`
  now gets an explicit, per-category `FocusNode`, and after `_move()` the row's remaining enabled
  arrow is refocused via `addPostFrameCallback` instead of leaving it to Flutter's default
  disabled-widget fallback. Covered by a regression test in `categories_panel_page_test.dart`.

~~Focus-snap on the categories reorder fix feels a bit abrupt~~ — softened (2026-07-22): the
one-frame hop itself can't be eliminated (Flutter defers focus updates by a frame by design,
confirmed via its docs, regardless of mechanism), so the arrows now fade their own focus highlight
in/out (120ms) instead of Flutter's instant default, in `categories_panel_page.dart`.

~~No confirmation dialog before deleting a category~~ — fixed (PR #16, 2026-07-22):
`CategoryPanelPage`'s "Delete" button now shows an `AlertDialog` ("Delete category?" / Cancel /
Delete) before calling `deleteCategory`, with focus defaulting to Cancel rather than Delete.

~~Migrate off `sqlite3_flutter_libs` to `sqlite3` v3.x~~ — done (PR #11, 2026-07-21): dropped
  `sqlite3_flutter_libs` from `pubspec.yaml` entirely, depend on `sqlite3` v3.x directly. See
  `DRIFT.md`.

~~Migrate off the Kotlin Gradle Plugin (KGP) applied by `image_picker_android`/
  `shared_preferences_android`~~ — resolved (2026-07-24): both plugins already shipped their
  Built-in Kotlin migration upstream on 2026-06-02, but plain `flutter pub get` never picks up a
  newer transitive dependency once it's already in `pubspec.lock` (that needs an explicit
  `pub upgrade`), and Renovate had no `lockFileMaintenance` rule to force that either — so the fix
  sat unused for weeks despite being available. Bumped via
  `flutter pub upgrade image_picker_android shared_preferences_android`
  (`0.8.13+17` -> `0.8.13+19`, `2.4.23` -> `2.4.27`); the "uses the following plugins that apply
  KGP" half of the warning is gone. Root cause fixed too, not just this one instance:
  `renovate.json` now has `lockFileMaintenance` enabled (weekly, same schedule as everything else),
  so Renovate periodically opens a PR refreshing the lockfile to the latest versions still allowed
  by existing constraints — this exact class of "the umbrella package's declared range already
  permits it, so nothing ever prompts an upgrade" gap shouldn't recur silently again.

~~`useMaterial3: false` in `flauncher_app.dart`~~ — resolved (2026-08-01): tried
`useMaterial3: true` on branch `experiment/material3-preview`. Visual diff is marginal (main
launcher grid is custom-painted, not stock Material widgets; settings dialogs pick up the M3
tokens but the difference is minor) and acceptable. No longer blocking; flip via PR when
convenient.

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

~~Seed a richer, sane default test setup instead of the bare upstream one.~~ — shipped
  (2026-07-22), wider in scope than originally captured: rather than a debug-only convenience,
  `AppsService._initDefaultCategories()` now sorts well-known apps into topical categories
  (`lib/default_app_categories.dart`'s hardcoded package-name map) on any genuine fresh
  install/data wipe, falling back to the original TV/Non-TV split for anything unmatched, and
  `WallpaperService` seeds a bundled default wallpaper (`assets/default_wallpaper.jpg`) instead of
  the plain gradient. Always-on production behavior, not gated behind debug mode — both paths key
  off the same fresh-install signal, so an ordinary app update/reinstall never re-triggers them.
  See `DRIFT.md`.

~~Concept: universal wallpaper filters (B&W, Blur, Contrast) for any wallpaper source, not just
  Picsum.~~ — **rejected per `ADR_001_Project_Scope_and_Feature_Governance.md` ADR-001** (2026-07-24): named explicitly in that ADR's
  "Negative / Accepted Trade-offs" as the kind of technically-elegant-but-scope-expanding feature
  the new governance gate exists to reject (turns "pick a wallpaper" into "edit a wallpaper"; the
  disqualifier about per-frame GPU cost for a never-changing background also applies directly, even
  with the "bake once" mitigation discussed below). Kept here for the technical writeup, not as an
  open item. Raised in conversation 2026-07-23. Right now
  B&W/Blur only exist inside the Picsum "Random photo" flow (`WallpaperControlBar`), calling
  `WallpaperService.reapplyPicsumFilters`, which re-fetches the photo from Picsum's server with
  `?grayscale`/`?blur=N` query params — Custom and Unsplash wallpapers have no filter step at all.
  Idea: add a "Filter" entry to the Wallpaper settings menu that loads a
  `WallpaperFilterControlBar` (same live-over-the-home-screen pattern as the existing control bar)
  and applies to whatever the *current* wallpaper is, regardless of which source set it. Adds
  Contrast alongside B&W/Blur.
  - Decouples "pick a wallpaper" from "adjust its filters" — filters become a property of the
    current wallpaper, not a step bolted onto one specific source's picker.
  - Technique: render client-side instead of round-tripping to a server, so it works for any
    source. `ColorFilter.matrix()` can combine grayscale + contrast (and brightness) in a single
    4x5 matrix multiply per pixel; `ImageFilter.blur(sigmaX:, sigmaY:)` handles blur — this app
    already uses the latter elsewhere (`lib/flauncher.dart`'s settings-icon shadow). Applying
    either live every frame via `ImageFiltered` would mean an ongoing per-frame GPU cost for a
    background that never changes, which is wasteful on a TV box's modest SoC — better to bake the
    result once: draw the base image through a `Paint` with `imageFilter`/`colorFilter` set onto a
    `ui.PictureRecorder`/`Canvas`, rasterize via `picture.toImage()`, then `toByteData(format:
    ui.ImageByteFormat.png)` and write those bytes to `_wallpaperFile` exactly like today — same
    one-time-cost, flat-file-on-disk shape the app already has, just computed locally instead of
    fetched from Picsum. Would need to keep the base (unfiltered) photo around separately from the
    baked result so filters can be changed/reset without re-fetching/re-picking.
  - Not a bug or regression, current approach works fine for Picsum; this is a scope expansion, not
    a fix.

~~**Resize custom wallpapers to screen resolution before saving them.**~~ — done (2026-08-06,
  PR #52): `WallpaperService._resizeToScreen` now downscales `pickWallpaper()` picks and the
  bundled default asset to the screen's physical resolution before writing to disk. Picsum turned
  out not to need it after all — it already requests photos pre-sized server-side. See `DRIFT.md`.

~~**Project health audit follow-up (2026-08-06).**~~ — done, PRs #49-#51: enabled
  `use_build_context_synchronously` (11 real missing `mounted` guards fixed, see `0a117bb` for the
  bug class), added CI `--fatal-infos`, and covered `SamsungTizenProfile`/`tv_input_profiles` with
  tests (0% -> 93%/100%).

~~**Settings export/import (JSON).** Export all categories, app-to-category assignments,
  wallpaper/gradient state, and remote button mappings to a JSON file, with import restoring them.
  Minimal UI: "Export settings" and "Import settings" buttons somewhere in the Settings panel
  (probably `SettingsPanelPage`). Use `path_provider` to write to a well-known path on the device
  (e.g. Downloads) and let the user pick a file for import. Useful for recovery after a factory
  reset or when moving to a new device. Pure data-layer work — no new runtime services, background
  tasks, or network permissions. Clears ADR-001 Q1 (reconfiguring everything from scratch after a
  reset is irritating) and Q2 (fast recovery preserves the upgrade pipeline's value).~~ — done
  (branch `feature/settings-export-import`): implemented `SettingsBackupService` that exports to
  `pitchfork_launcher_settings_<timestamp>.json` and keeps a `pitchfork_launcher_settings_latest.json`
  copy in external app storage, with import replacing all categories, app assignments, hidden apps,
  SharedPreferences settings, button mappings, and wallpaper bytes. Added "Export settings" / "Import
  settings" buttons to `SettingsPanelPage` and a `restoreWallpaper` method to `WallpaperService`.

~~**Settings export/import: use a file picker instead of a fixed app-private path.** Current
  implementation (`SettingsBackupService`, see above) always reads/writes a fixed filename
  (`pitchfork_launcher_settings_latest.json`) under `getExternalStorageDirectory()` -- the app's
  own external-files directory, not a shared/public location. That directory is deleted when the
  app is uninstalled (same lifecycle as internal storage), which undercuts the feature's stated
  "recovery after a factory reset or moving to a new device" purpose: the backup only survives if
  the user manually copies it elsewhere (e.g. via adb) before uninstalling/resetting. Considered
  good enough for this version; picked up as a follow-up: use a Storage Access Framework file
  picker (e.g. `file_picker` or `saf_util`) so export/import target a location and filename the
  user actually chooses, instead of a hardcoded path.~~ — done differently (2026-08-05): a file
  picker was reconsidered and rejected -- its `DocumentsUI` picker screen is touch-first and not
  guaranteed to be comfortably D-pad-navigable on a TV, and pulling in a whole picker package
  (`file_picker`/`saf_util`) for one button felt heavier than the project's usual dependency
  budget (see the Firebase/Unsplash-SDK removals). Also explicitly not wanted: any "pick which
  backup" UI at all -- the ask was to keep it exactly two buttons, Backup and Restore, no file
  choice.

  First landed on `MediaStore.Downloads` (an app can write/read its own rows there with zero
  permission), but testing on the Google TV emulator (Android 14, API 34) falsified that:
  `owner_package_name` came back `NULL` on the row our own app had just inserted, and after an
  actual uninstall/reinstall the app could no longer find or read the file back at all -- confirmed
  via web search as a general, documented Android limitation (`MediaProvider` does not preserve
  per-app ownership of `MediaStore` rows across an uninstall/reinstall), not an emulator quirk. That
  broke the one thing this feature exists for.

  Replaced with `MANAGE_EXTERNAL_STORAGE` ("All files access") plus a plain `File` against
  `Environment.getExternalStoragePublicDirectory(DIRECTORY_DOWNLOADS)` (`SettingsBackupStorage.kt`,
  wired through `FLauncherChannel.writeSettingsBackup`/`readSettingsBackup`/
  `isSettingsBackupStorageAvailable`/`openSettingsBackupStoragePermission`). This sidesteps
  MediaStore's ownership model entirely -- once granted, the fixed-name file
  (`pitchfork_launcher_settings.json`) in the real Downloads folder is reachable regardless of which
  install of the app wrote it. Trade-off: needs a one-time manual grant via a system Settings screen
  (`Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`), which -- like any permission -- resets
  on uninstall and needs re-granting after a fresh install, similar in spirit to the existing "Set as
  Home button target" one-time setup step; `PitchforkSettingsPanelPage` checks
  `SettingsBackupService.isStorageAvailable()` before Backup/Restore and offers an "Open Settings"
  button instead of a bare failure when it isn't granted yet. Reasonable only because
  PitchforkLauncher isn't on the Play Store, where this permission needs a declared justification
  most apps don't have. Requires Android 11+ (API 30); no-ops below that, and
  `isStorageSupported()` lets the UI tell "not granted yet" apart from "OS too old" instead of
  offering a settings screen that can't resolve on this app's minSdk-24 floor. Writes go through a
  temp file + atomic rename rather than truncating the target in place, so a failed write can't
  destroy the previous good backup; the native read/write handlers also moved off the UI thread
  (`MethodChannel` callbacks run there by default) to avoid janking rendering on a large wallpaper
  payload. Still no new Flutter dependency, still the same two-button UI. **Scope, precisely:**
  this survives an app uninstall/reinstall (verified), not a factory reset or a move to a new
  device by itself — those wipe/don't-carry-over the Downloads folder too, so recovering from
  either still needs the file copied off-device first. See `DRIFT.md`.

~~**Restructure the Settings panel menu.** `SettingsPanelPage` has grown a lot (categories,
  applications, button mappings, wallpaper, time format, animations, about, and now export/import)
  and is starting to feel like a flat, ever-growing list of buttons rather than a coherent menu.
  Keeping it clean and legible needs ongoing attention as more settings get added, rather than
  just tacking each new item onto the end -- likely candidates: grouping related entries under
  headers/sections, or splitting some off into their own sub-pages.~~ — done (branch
  `feature/settings-menu-restructure`): split off a new `PitchforkSettingsPanelPage` ("Pitchfork
  Settings") holding TV Inputs, Set as Home button target, Remote buttons, the 24-hour time format
  and app card highlight animation toggles, and Export/Import settings. `SettingsPanelPage` now
  only has Applications, Categories, Wallpaper, Android settings, Pitchfork Settings and About --
  fits on one screen again without scrolling.

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

- **`buildAppMap()` encodes `banner` for every app, including ones that never render through an
  `AppCard`.** `MainActivity.kt:207-214` builds `banner` unconditionally for every installed app,
  but `banner` has exactly one consumer in the whole codebase — `app_card.dart:124-125` — which
  only draws for apps sitting in a visible category. Hidden apps and apps not yet assigned to any
  category never go through `AppCard`, so their `banner` bytes are computed, stored, and read by
  nothing. (`icon`, in contrast, genuinely is needed for every app regardless of hidden state —
  `applications_panel_page.dart:123` renders it in the Applications panel's "Hidden" tab, so an app
  can be recognized before being unhidden.) The recent background-thread fix
  (see Done below) only moved this work off the platform thread; it didn't reduce it — this is the
  actual work-reduction/power angle. Lazy-computing `banner` only when an app is added to a visible
  category (the `addToCategory` hook already exists) would cut this to zero cost for apps that
  never show a banner, with no fundamental added cost elsewhere. Found via conversation
  (2026-08-08), verified against the code — `banner`'s only read site confirmed via grep across
  `lib/`.

- **Reconsider the `FLauncher`/`PitchforkLauncher` title split in file headers, and the remaining
  bare `flauncher` naming (`pubspec.yaml:1`'s package `name: flauncher`).** `AGENTS.md:97-100`
  currently documents that files carrying Fesser's copyright line keep `FLauncher` as the header
  title while wholly-new files use `PitchforkLauncher` — in practice that reads as more
  inconsistent than intentional. Non-negotiable regardless of what's decided: the copyright
  attribution line itself, `Copyright (C) 2021  Étienne Fesser` (present in all 47 files that carry
  it, per `AGENTS.md:90-95`), stays untouched everywhere it appears — only the decorative title line
  above it, and cosmetic references like the pubspec package name, are up for reconsideration.
  Noted, not yet decided.

## Done

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

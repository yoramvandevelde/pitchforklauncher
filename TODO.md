# TODO

## Open

- **Icon/banner encoding blocks the platform thread on every app sync.**
  `MainActivity.getApplications()`/`buildAppMap()`/`drawableToByteArray()`
  (`MainActivity.kt:183-214,286-303`) run synchronously on the platform thread whenever apps are
  queried — cold start and every `PACKAGE_ADDED`/`PACKAGE_CHANGED`. Per app: `loadBanner`/
  `loadIcon`, rasterize to a `Bitmap`, `Bitmap.compress(PNG, 100)`. On a TV with 50-100 apps that's
  easily hundreds of ms of UI-thread block, visible as the "Loading..." state
  (`apps_service.dart:143-168`). `backgroundExecutor` already exists in this file (used for
  `writeSettingsBackup`/`readSettingsBackup`) — dispatching `getApplications()` through it would be
  the same pattern already established, no new dependency. Found via a review pass (2026-08-06),
  verified against the code.

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

- **`TimeWidget` ticks every second, permanently.** `lib/widgets/time_widget.dart:41` —
  `Timer.periodic(Duration(seconds: 1))` + `setState` runs for as long as the launcher is on
  screen (which for a TV launcher is essentially always), even though the displayed text only
  changes once a minute. Could reschedule to the next minute boundary instead, or skip `setState`
  when the formatted string hasn't actually changed. Found via the same review pass.

- **App-card focus-pulse animation runs continuously for every card, not just the focused one.**
  `lib/widgets/app_card.dart:57-85,162-189` — the `AnimationController`'s status listener flips
  forward/reverse unconditionally once started; the `Selector` in `build()` only gates on the
  `appHighlightAnimationEnabled` setting, not on `Focus.of(context).hasFocus`, so every `AppCard`'s
  `AnimatedBuilder` subtree repaints at 60fps whenever the setting is on — including cards that
  aren't focused. There's already a Settings toggle to turn the whole thing off, but the
  always-on-when-enabled cost affects every card, not just the one actually showing the pulse.
  Consider only animating while genuinely focused. Found via the same review pass.

- **`network_image_mock` dev dependency is unused.** `pubspec.yaml:33` — zero imports anywhere in
  `lib/` or `test/`. Leftover from before this app had any `Image.network` widgets. Remove +
  `flutter pub get`. Found via the same review pass, confirmed dead by grep.

- **`TickerModel` is effectively dead code in production.** `flauncher_app.dart:110` always
  registers `TickerModel(null)`, so `app_card.dart:61`'s `tickerProvider ?? this` never actually
  uses the injected ticker — `_AppCardState` already has its own `SingleTickerProviderStateMixin`
  to fall back to. Only `test/flauncher_test.dart:705` supplies a real one. Removing it needs a
  small test refactor (that test currently relies on the injection to control animation timing).
  Found via the same review pass.

- **Tizen pairing token is stored in plaintext in the settings backup file.**
  `settings_backup_service.dart:191` includes the full `tvInputs` list (via
  `TvInputConfig.toJson()`) in the exported JSON, which for a `SamsungTizenProfile` input includes
  the pairing `token` once paired (see `samsung_tizen_profile.dart`). That token has replay value —
  whoever can read `pitchfork_launcher_settings.json` from Downloads can reconnect to the TV as
  "Pitchfork" without re-pairing. The backup's plaintext-JSON-in-shared-storage trade-off is
  already accepted/documented (`DRIFT.md`), but the token specifically wasn't called out before.
  Worth deciding: strip tokens from the export (re-pairing on restore just costs one "Allow
  access?" prompt), or leave as-is and document the risk explicitly. Found via a review pass
  (2026-08-06), verified against the code — a related claim from the same pass (that
  `SettingsBackupStorage.write` ignores `renameTo`'s return value) turned out to be wrong: Kotlin's
  `return try { ...; tempFile.renameTo(target) } catch { false }` does return it, and the failure
  correctly propagates up to `settings_backup_service.dart`'s `BackupException`. Not added here.
  **Update (2026-08-07, Grok pass, verified):** the same token also has a second, passive exposure
  path — `AndroidManifest.xml:53,55` sets `android:allowBackup="true"` with
  `android:fullBackupContent="true"` as a literal boolean (not a `@xml/backup_rules` file scoping
  what's included), so the token rides along in Android's own Auto Backup to the user's Google
  account on every backup cycle, with no explicit export action needed — broader and less visible
  than the Downloads-file case. Same open decision (strip the token vs. accept and document) should
  cover both; a `fullBackupContent`/`dataExtractionRules` rules file excluding the relevant prefs
  key would close the passive path specifically without touching the deliberate Downloads export.

- **`SettingsBackupStorage.write`/`read` don't sanitize `fileName`.** `SettingsBackupStorage.kt:77,88`
  builds `File(downloadsDirectory, fileName)` straight from the channel argument, so a name
  containing `../` could escape the Downloads directory. Not exploitable today —
  `settings_backup_service.dart:36`'s `backupFileName` is a hardcoded constant, and the channel
  isn't reachable from outside this app — but a basename-only check (or rejecting anything with a
  path separator) is a one-line, zero-risk hardening that's worth having before any future caller
  (a file picker, say) could ever make it live. Found via a review pass (2026-08-07, Grok),
  verified against the code.

- **MethodChannel handler throws instead of `result.notImplemented()`, and does unchecked casts on
  every argument.** `MainActivity.kt:67-122` — each branch does e.g. `call.arguments as String` or
  `args["keyCode"] as Int` with no type check, and the `else` branch does
  `throw IllegalArgumentException()` rather than `result.notImplemented()`. Not attacker-reachable
  (only this app's own Dart code calls the channel, always with fixed argument shapes) — this is a
  hygiene/convention nit, not a vulnerability, but it's the standard Flutter pattern and cheap to
  match. Found via a review pass (2026-08-07, Grok), verified against the code.

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

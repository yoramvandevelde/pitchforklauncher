# Drift from upstream

This fork diverges from the original [FLauncher](https://gitlab.com/flauncher/flauncher) in a
few deliberate ways, listed here so it's clear what changed and why. New feature proposals are
weighed against `ADR_001_Project_Scope_and_Feature_Governance.md`'s governance gate before landing
here — see that file for the criteria and for examples of what's been rejected on that basis.

## Toolchain

- **Flutter pinned via FVM** (`.fvmrc`, `.fvm/`). The project didn't have a reproducible SDK
  version pinned to the working tree; FVM avoids depending on whatever Flutter happens to be
  globally installed, without touching any global/system Flutter install. Currently pinned to
  3.44.6 (bumped from the initial fork point, 3.7.5, through a series of intermediate stepping
  stones — see `UPGRADE_PLAN.md`'s Phase 2 for the full history; 3.44.6 is the latest stable as of
  Phase 2's completion).
- **Android toolchain modernized alongside the Flutter SDK bumps** — see `UPGRADE_PLAN.md` for the
  phased plan (AGP/Gradle/Kotlin, then Flutter SDK, then dependencies) and the real landmines hit
  along the way (an old Flutter patch's Gradle script hard-incompatible with Gradle 8, AGP 8's
  `namespace` requirement breaking several plugins' old Android implementations, Flutter's Gradle
  plugin loader dropping the imperative `apply from`/`apply plugin` style entirely, the v1 Android
  embedding's removal breaking several plugins a second time, `compileSdk` now at 36).
- **`sqlite3_flutter_libs` dropped, depends on `sqlite3` directly** (2026-07-21). Upstream
  deprecated `sqlite3_flutter_libs` once native SQLite binary bundling moved to Dart's build hooks
  system — its `0.6.0+eol` release strips all code from the package. `lib/database.dart` never
  called `sqlite3_flutter_libs`'s API directly (no `DynamicLibrary.open`, `open.overrideFor`, or
  the old-Android workaround); it was purely there to bundle the native lib, and `drift` already
  required `sqlite3 ^3.4.0` transitively. Straight swap: `sqlite3_flutter_libs` removed from
  `pubspec.yaml`, `sqlite3` added as a direct dependency. Verified both a fresh install and
  installing over an existing database (upgrade path) preserve all data with no crash.
- **JDK bumped from 17 to 25 (LTS)** (2026-07-24). `AGENTS.md` had claimed since this fork's
  earliest commit (back when AGP was still 7.1.1) that this project's AGP version "fails dexing on
  JDK 21+" and needed to stay on 17 — that claim was never re-checked through the several AGP bumps
  since and turned out to be stale: building on JDK 21 and JDK 25 both succeed cleanly on the
  current toolchain (AGP 9.3.1 / Gradle 9.6.1 / Kotlin 2.4.10), verified with a real
  `flutter build apk --debug` plus install and launch on the emulator, not just assumed. JDK 17
  remains the actual floor (Gradle 9.x itself dropped support for running its daemon on JDK 16 or
  older), but there's no reason to sit at the floor once a newer LTS is confirmed to work — CI
  (`ci.yml`, `release.yml`) and the `justfile` recipes now all target JDK 25.
- **Android review cleanup** (2026-08-04): a few small removals verified with a real
  `flutter build apk --debug`. Dropped the redundant `package=` manifest attribute (superseded by
  `namespace` in `build.gradle` since AGP 8) from all three manifests, the debug/profile overlays'
  now-duplicate `INTERNET` permission (already granted unconditionally in the main manifest), the
  empty `signingConfigs { debug {} }` block (AGP's default already covers it), and a dead
  pre-minSdk-24 branch in `MainActivity.applicationExists()`. One claim from that same pass didn't
  hold up, though: the `flutterEmbedding` meta-data looked like obsolete v1-embedding boilerplate,
  but it's actually the only signal `flutter_tools` checks (`project.dart`'s
  `computeEmbeddingVersion()`); removing it makes a v2 app look like unsupported v1 and hard-fails
  the build. Left in place.

## Removed Firebase

Firebase (Analytics, Crashlytics, Remote Config) required a `google-services.json` that isn't
committed to the repo (it's supplied by CI from a secret for the official Play Store build). Without
it, the app crashed on launch (`FirebaseInitProvider` / `IllegalArgumentException: Please set your
Application ID`). Rather than fake credentials, Firebase was removed entirely:

- `firebase_analytics`, `firebase_core`, `firebase_crashlytics`, `firebase_remote_config` removed
  from `pubspec.yaml`, and the corresponding Gradle plugins/classpaths from `android/build.gradle`
  and `android/app/build.gradle`.
- Crash reporting / analytics settings toggles removed from the Settings panel.
- The Unsplash wallpaper source (previously gated behind Remote Config) was removed entirely —
  see "Picsum wallpaper source" below for the replacement, and why.

## Home-button override (AccessibilityService)

Google TV doesn't allow a third-party launcher to become the system default HOME app through
normal means (`pm set-home-activity`, the Home-app picker) — this is a platform restriction, not
a bug (see the original README's "Method 2: disable the default launcher"). Disabling the stock
launcher works, but breaks the remote's dedicated YouTube button.

Instead, `HomeButtonAccessibilityService` (an `AccessibilityService` with
`flagRequestFilterKeyEvents`) intercepts `KEYCODE_HOME` directly and brings FLauncher to the
front, the same technique other third-party TV launchers (e.g. Projectivy Launcher) use. This
keeps the stock launcher intact. A "Set as Home button target" button in Settings → Pitchfork
Settings opens Android's Accessibility settings so the user can enable it.

## Configurable remote button mappings

Beyond Home, any other remote button can be mapped to launch an app — Settings → Pitchfork
Settings → "Remote buttons". This replaces what was originally a single hardcoded case for the
remote's dedicated YouTube button (which doesn't send a standard Android keycode; on this Google
TV Streamer remote it's `KEYCODE_BUTTON_3`/190, identified by temporarily logging every key event
the service saw).
That mapping is now just a pre-seeded, editable/removable entry in the same generic system rather
than a special case.

- `ButtonMappings.kt` persists `keyCode -> package name` in a dedicated SharedPreferences file,
  readable directly by `HomeButtonAccessibilityService` (which doesn't have a Flutter engine
  attached) as well as via the platform channel from Dart.
- "Add mapping" puts the service into a one-shot capture mode (`ButtonCapture.kt`, an in-process
  singleton — the service and `MainActivity` share a process) that reports the next key event's
  code back to Flutter instead of acting on it, so the UI can show "press a button", then let the
  user pick which app it should launch from the existing app list.
- Home, Back, D-pad/select navigation, Power, volume, and the assistant key are excluded from
  capture/mapping. Home is FLauncher's own core feature; the navigation keys turned out to be
  necessary too — capture mode originally swallowed *any* non-reserved key, including the D-pad
  presses needed to reach the "press a button" dialog's own Cancel button, making it impossible
  to back out of; the assistant key fought with Android's own Assistant overlay when mapped. In
  practice this leaves dedicated quick-launch buttons (YouTube, Netflix, etc.) as the only
  practical thing left to map — which was the actual goal anyway.
- The mapped button keeps working even if you disable the stock launcher (README "Method 2"),
  since the service handles it directly rather than relying on whatever normally reacts to it.

`showDialog()` targets the root `Navigator` by default, which isn't the same one
`Navigator.of(context)` resolves to from inside `ButtonMappingPanelPage` (it lives inside
`SettingsPanel`'s own nested `Navigator`) — worth remembering if a future dialog added there
seems to silently do nothing when dismissed, since `.pop()` would target the wrong navigator.

Tested and working on real Google TV Streamer 4K hardware. `adb shell input keyevent` and `adb
emu event send` (console/HID-level injection) don't reliably reach the accessibility service's
key filter in emulator testing — not just for custom-mapped buttons, even the already-working
Home override didn't respond to either, on both Android 11 and 14 emulators. Use a real remote
(or an actual keyboard attached to the emulator) if testing this on an emulator.

Known trade-off: because FLauncher isn't the *actual* resolved default launcher in this setup,
pressing Back while at FLauncher's home screen pops through to the stock launcher instead of
staying put. See `TODO.md`.

The original README's "Method 2" (disable the stock launcher) is still there as a documented
option — `justfile` has `disable-default-launcher` / `restore-default-launcher` recipes to toggle
it via adb, for anyone who prefers that trade-off (real default-launcher behavior, Back does
nothing on the home screen) over the accessibility-service approach. The YouTube button keeps
working either way now, since the service handles it directly rather than relying on the stock
launcher.

## Open Sans body font, Nebula Sans Black headers

Switched the app's typeface to Open Sans (bundled as a variable font,
`assets/fonts/OpenSans-Variable.ttf`) for a cleaner look than the platform-default font upstream
uses. The home screen's category headers and clock use Nebula Sans Black
(`assets/fonts/NebulaSans-Black.ttf`) instead, via `lib/fonts.dart`, a display face for those three
call sites only; app names, dialogs and the settings panels stay on Open Sans.

Both are SIL OFL 1.1 and both are bundled non-pub assets, so Flutter's "VIEW LICENSES" screen
doesn't pick either up automatically. Each is registered manually via
`LicenseRegistry.addLicense()` in `main.dart` (see AGENTS.md's License section for the pattern),
with its own copy of the license text.

## Picsum wallpaper source

The existing Unsplash wallpaper source needed a developer API key (and, in the original app,
Remote Config to turn it on) — not something worth setting up for personal use. `PicsumService`
(`lib/picsum_service.dart`) adds a "Random photo" option using [picsum.photos](https://picsum.photos),
a free, key-less random-image API — no signup, no credentials, no rate-limit management. The
Unsplash integration (`unsplash_client` dependency, `UnsplashService`, `UnsplashPanelPage`, the
`WallpaperService`/`SettingsService` methods and fields backing it) sat dormant, unreachable, for a
while, then was removed entirely (2026-07-24) per `ADR_001_Project_Scope_and_Feature_Governance.md`
ADR-001 once it became clear there was no path back to turning it on — dead code with no owner
requirement doesn't get a special exemption from that gate. `webview_flutter` was removed alongside
it, since its only use was rendering the Unsplash photo author's profile link.

Picking "Random photo" (Settings → Wallpaper) closes the Settings panel entirely and shows a live
full-screen preview instead of choosing from behind the docked 350px settings dialog: a rounded,
content-sized control bar (`lib/widgets/wallpaper_control_bar.dart`) slides up from the bottom of
the screen, directly over the real home screen, with **Random** / **Black & White** / **Blur**
controls (2026-07-21).

Picsum's "random" endpoint (`picsum.photos/{w}/{h}`) is itself just a redirect to a specific
numbered photo (`fastly.picsum.photos/id/{id}/{w}/{h}.jpg`). `PicsumService` follows that redirect
manually to capture the id (`http.get()` would otherwise auto-follow it and discard it), so
toggling Black & White or Blur re-fetches the *same* photo with `?grayscale`/`?blur=N` instead of
rolling a new random one — both filters combine in a single request. The switches are disabled
until a photo actually exists to filter (`WallpaperService.hasCurrentPicsumPhoto`).

Wallpaper changes also cross-fade (200ms) instead of cutting instantly — a `wallpaperVersion`
counter on `WallpaperService` keys an `AnimatedSwitcher` around the background in `FLauncher`.
This applies to every wallpaper source, not just Picsum.

Custom wallpapers (`pickWallpaper()`) and the bundled default asset are downscaled to the screen's
physical resolution before being written to disk (`WallpaperService._resizeToScreen`, 2026-08-06)
— a phone/camera photo can be 8-12MP, which otherwise sits fully decoded in GPU memory for no
visible benefit on a TV screen. Picsum photos don't need this: `PicsumService` already requests
them pre-sized to the screen's resolution server-side.

## Smart first-run seed

On a genuine fresh install / wiped data (`FLauncherDatabase.wasCreated`, or the new
`isFreshInstall()` helper used by `WallpaperService`), instead of just the generic "TV
Applications"/"Non-TV Applications" split, well-known apps are automatically sorted into topical
categories first — see `lib/default_app_categories.dart`'s hardcoded package-name-to-category map
(currently Streaming/Media/System entries, editable directly, no config file or remote source).
Both the grouping and the display order follow the map's own order directly, not the device's
alphabetically-sorted app list. Unmatched apps still fall back to the original TV/Non-TV split.

Per-category display (grid vs. row, row height, grid column count) comes from the same file's
`defaultCategorySettings` map, keyed by category name (both the topical names and the
"TV Applications"/"System" fallback names) — e.g. Streaming is a 5-wide grid, System is an 80px
row. A category with no entry is left at the app's normal defaults. Every field that matters is
stated explicitly rather than left to "the default": the actual database column default for a
category's type is `CategoryType.row`, not grid, so any topical category meant to render as a grid
(Streaming, Media) must say so. `AppsService._seedCategory()` is the single place that reads this
map and applies it, shared by every seeded category (TV/Non-TV Applications and the topical ones)
instead of repeating the create/type/height/columns/add-apps dance per category.

A bundled default wallpaper (`assets/default_wallpaper.jpg`, a photo by Wilhelm Gunkel on
Unsplash, credited both in the About dialog itself and in its license viewer) is also shown instead
of the plain gradient fallback on that same first launch, and can be restored later via the
"Default" button on the wallpaper panel (`WallpaperService.resetToDefaultWallpaper()`). Both the
category seed and the wallpaper seed gate on the same fresh-install signal, so an ordinary app
update/reinstall never triggers either — only an explicit data wipe or full uninstall+reinstall
does.

## Transparent, floating app bar

The settings icon/clock bar (`FLauncher._appBar`) uses `Scaffold.extendBodyBehindAppBar` so the
category list can scroll all the way up behind it instead of being hard-clipped below a reserved,
opaque-looking strip. The gap the category list rests at (unscrolled) lives as a `SizedBox` inside
the scrollable content itself (`_categoriesTopGap`), not as padding around the whole
`SingleChildScrollView` — padding there would shrink the scrollable viewport and reintroduce the
hard clip. The bar's own height/alignment are back to Flutter's plain defaults (`kToolbarHeight`,
`Alignment.center`): shrinking it was only ever about reclaiming space for content, which
transparency already solves, and centering is also the only alignment that doesn't clip the
settings icon's splash circle against the bar's edge.

## "Move to..." from the home screen's app context menu

Long-pressing an app on the home screen already offered "Remove from `<category>`"; the only way
to place it under a *different* category used to be Settings > Applications' "+" button
(`AddToCategoryDialog`). `ApplicationInfoPanel` now also offers "Move to...", which reuses that
same dialog rather than duplicating its category-picker UI — `AddToCategoryDialog` takes an
optional `moveFrom` category, and when set, picking a category calls the new
`AppsService.moveToCategory(app, from, to)` instead of just `addToCategory`. That method does the
insert-into-new-category and delete-from-old-category in a single `_database.transaction()` with
one `categoriesWithApps` reload/`notifyListeners()` at the end, rather than calling `addToCategory`
then `removeFromCategory` back to back (two full reloads, and the app would transiently show up in
both categories at once).

## Rudimentary error log

`AppLog` (`lib/app_log.dart`) is an in-memory, 50-entry ring buffer of timestamped log lines,
surfaced to the user via the About dialog's "Logs" button (`AppLogDialog`). Not persisted across
restarts and not a crash-reporting solution — it exists to help a user explain a support issue
("my wallpaper won't load") without needing `adb logcat` on hand, since a Google TV box is rarely
plugged into a computer for debugging. `PicsumService`/`WallpaperService` (a failed random-photo
fetch) and `TvInputService` (a failed TV input switch) call `AppLog.instance.log(source, message)`
on failure; every entry also goes through `debugPrint`, so the same information is still readable
via `adb logcat` for anyone who does have a computer handy. The log text itself is plain (not
selectable/focusable) `Text`, which Flutter's default focus-follows-scroll behavior can't drive
with the D-pad — so `AppLogDialog` scrolls it manually via its own `Focus`/`onKeyEvent` handler
instead, releasing focus at the scroll bounds so Up/Down can still reach the Close button once
fully scrolled instead of the key being swallowed with nothing left to scroll.

Related: Picsum wallpaper requests now fail with an explicit timeout instead of hanging on the
default ~60s TCP timeout, so a network hiccup shows up in the log (and to the user) promptly
instead of leaving the wallpaper picker looking frozen.

## TV input switcher

Holding D-pad Up for 1 second on the home screen (`TvInputTrigger`) opens `TvInputBar`, letting
the user switch the physical TV to a configured input (Xbox, cable box, etc.) directly from the
launcher, without touching the TV's own remote or input-select menu. Every key event below the
1-second threshold is ignored and falls through to normal `DirectionalFocusIntent` handling
untouched, so ordinary Up presses/holds behave exactly as they did before this existed; the trigger
also opens (to a shortcut into `TvInputsPanelPage`) even with zero inputs configured yet, so the
gesture doubles as its own discovery path. Configured via Settings → Pitchfork Settings → TV Inputs.

Each TV brand/protocol is a pluggable `TvInputProfile` (`lib/providers/tv_input/tv_input_profile.dart`
has the extension-point doc comment) rather than one hardcoded implementation. The only one shipped,
`SamsungTizenProfile`, talks to a Samsung Tizen TV's local WebSocket remote-control API (present on
Tizen models since ~2016) over its secure port (8002) rather than the legacy plaintext one — newer
Tizen firmware silently rejects plaintext pairing attempts. The first connection from a given client
name pops an "Allow access?" prompt on the TV; the pairing token it hands back afterward is
persisted onto that input's config and resent on every later connection, and merged onto every
other configured input pointing at the same host, so approving once on the TV covers every button
mapped to it instead of re-prompting per input.

Configured inputs (`TvInputConfig`, a small id/label/profile-id/params record) are stored as a JSON
blob in SharedPreferences (`TvInputService`) rather than a Drift table — the same storage choice
`SettingsService` makes for similarly small, rarely-changing state.

## Settings backup/restore (JSON)

`SettingsBackupService` exports every category and its app assignments, hidden apps, the
SharedPreferences-backed settings, TV Input configuration, remote button mappings and the wallpaper
to a single fixed-name JSON file, with import restoring all of it. Reachable via Settings →
Pitchfork Settings → Backup/Restore, each behind a confirmation dialog. Motivation: recovering
without reconfiguring everything from scratch after an app uninstall/reinstall (clears ADR-001's
governance gate — see `ADR_001_Project_Scope_and_Feature_Governance.md`).

**Scope of what this actually protects against, precisely:** an app uninstall/reinstall — verified
on-device — not a factory reset or moving to a new device. The backup file survives in the real
Downloads folder because that folder isn't part of the app's own storage, but a factory reset wipes
the whole device's storage including Downloads, and a new device obviously doesn't inherit anything
from the old one's disk either. Recovering from either of those still needs the file copied
off-device first (`adb pull`, USB, cloud upload, etc.) before the reset/migration happens — this
feature doesn't do that copy step itself, it only solves "the app's own storage getting wiped from
under it," which an uninstall/reinstall triggers even without any of the above.

The backup file lives in the real, shared Downloads folder (`SettingsBackupStorage.kt`, reached
through `FLauncherChannel.writeSettingsBackup`/`readSettingsBackup`), not the app's own
external-files directory — that directory is wiped on uninstall, which would have defeated the
whole point above. `SettingsBackupService` always targets one recognisable name
(`pitchfork_launcher_settings.json`), so "Backup"/"Restore" stay two plain buttons — no picker, no
"which file" choice. Writes go to a temp file first, then an atomic rename over the target
(`File.renameTo` within the same directory), so a crash or failed write partway through leaves the
previous good backup in place instead of a half-written replacement Restore would then choke on.

First cut of this used `MediaStore.Downloads` instead, which lets an app write/read its own rows
with no permission at all — but confirmed on a real device (and independently documented as
general Android behavior, not an OEM quirk): `MediaProvider` does not preserve that per-app
ownership across an uninstall/reinstall, which broke the "survive uninstall" requirement this
feature exists for. Now uses the `MANAGE_EXTERNAL_STORAGE` ("All files access") permission plus a
plain `File` against `Environment.getExternalStoragePublicDirectory(DIRECTORY_DOWNLOADS)` instead
— sidesteps the ownership question entirely, at the cost of a one-time manual grant via a system
Settings screen (`Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`, opened via
`SettingsBackupService.openStoragePermissionSettings()`), which — like any permission — needs
re-granting after a fresh install. `SettingsBackupService.isStorageAvailable()` lets the UI check
this up front and prompt with an "Open Settings" action instead of a bare failure. Reasonable only
because PitchforkLauncher isn't on the Play Store, where this permission needs a declared
justification most apps don't have. Requires Android 11+ (API 30, where
`Environment.isExternalStorageManager()` and `ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION` were
introduced) — `SettingsBackupService.isStorageSupported()` lets the UI tell "not granted yet"
(fixable) apart from "OS too old" (not fixable) instead of offering a settings screen that can't
resolve on this app's minSdk-24 floor; the native side no-ops (write returns false, read returns
null) below API 30 either way.

`writeSettingsBackup`/`readSettingsBackup`'s native handlers hop onto a background thread for the
actual file I/O (the payload includes the base64-encoded wallpaper, easily several hundred KB) and
post the result back to the platform thread — `MethodChannel` handlers run on the UI thread by
default, and blocking it on synchronous storage I/O risks jank or an ANR.

Import parses and validates the *entire* backup payload up front, into a typed `_ParsedBackup`
model, before touching anything. Restoring spans several independent stores with no shared
rollback — SharedPreferences, the database, the native button-mapping channel, `TvInputService`,
the wallpaper file — so discovering a malformed field partway through (a bad category enum, say)
would otherwise leave some stores updated and others not. The one genuinely transactional step (the
database restore: categories, app assignments, hidden state) runs last, so a failure in any of the
earlier, non-rollback-able steps leaves that hardest-to-manually-recreate data untouched rather than
wiped with nothing successfully restored in its place. Categories and button mappings referencing
an app that isn't currently installed are silently skipped instead of crashing on a foreign-key
violation or leaving a dead mapping. The category/hidden-state writes and the button-mapping restore
route back through `AppsService.reloadFromDatabase()`/`ButtonMappingService.setMapping()` rather
than hitting the database/native channel directly, so those services' own in-memory caches — and
the UI reading them — reflect the restore immediately rather than only after an unrelated refresh.

The backup file is plain, unencrypted JSON in the real Downloads folder, readable by anything with
file access to that folder (another app with storage permissions, a USB/file-manager connection,
etc.) — it includes TV Input hostnames/IPs, category/app layout and the wallpaper. No UI warning for
this; acceptable for a single-user device, but worth knowing before treating that file as
disposable or sharing it.

## Per-category name-visibility toggle

`Category.showName` (schema v6) controls whether `apps_grid.dart`/`category_row.dart` render the
name label above a category's apps on the home screen — the category keeps its actual name either
way, used everywhere else (management UI, `AddToCategoryDialog`, etc.); this only gates that one
piece of on-screen text. Defaults to `true`, so existing categories are unaffected by the upgrade.
Toggled per category via a `SwitchListTile` in `CategoryPanelPage`, alongside the existing
sort/type/row-height controls. Included in settings backup export/import, falling back to `true`
when absent (any backup written before this field existed).

# Drift from upstream

This fork diverges from the original [FLauncher](https://gitlab.com/flauncher/flauncher) in a
few deliberate ways, listed here so it's clear what changed and why.

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

## Removed Firebase

Firebase (Analytics, Crashlytics, Remote Config) required a `google-services.json` that isn't
committed to the repo (it's supplied by CI from a secret for the official Play Store build). Without
it, the app crashed on launch (`FirebaseInitProvider` / `IllegalArgumentException: Please set your
Application ID`). Rather than fake credentials, Firebase was removed entirely:

- `firebase_analytics`, `firebase_core`, `firebase_crashlytics`, `firebase_remote_config` removed
  from `pubspec.yaml`, and the corresponding Gradle plugins/classpaths from `android/build.gradle`
  and `android/app/build.gradle`.
- Crash reporting / analytics settings toggles removed from the Settings panel.
- `unsplashEnabled` (previously gated behind Remote Config) is hardcoded `false` — see "Picsum
  wallpaper source" below for the replacement.

## Home-button override (AccessibilityService)

Google TV doesn't allow a third-party launcher to become the system default HOME app through
normal means (`pm set-home-activity`, the Home-app picker) — this is a platform restriction, not
a bug (see the original README's "Method 2: disable the default launcher"). Disabling the stock
launcher works, but breaks the remote's dedicated YouTube button.

Instead, `HomeButtonAccessibilityService` (an `AccessibilityService` with
`flagRequestFilterKeyEvents`) intercepts `KEYCODE_HOME` directly and brings FLauncher to the
front, the same technique other third-party TV launchers (e.g. Projectivy Launcher) use. This
keeps the stock launcher intact. A "Set as Home button target" button in Settings opens Android's
Accessibility settings so the user can enable it.

## Configurable remote button mappings

Beyond Home, any other remote button can be mapped to launch an app — Settings → "Remote
buttons". This replaces what was originally a single hardcoded case for the remote's dedicated
YouTube button (which doesn't send a standard Android keycode; on this Google TV Streamer remote
it's `KEYCODE_BUTTON_3`/190, identified by temporarily logging every key event the service saw).
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

## Picsum wallpaper source

The existing Unsplash wallpaper source needs a developer API key (and, in the original app,
Remote Config to turn it on) — not something worth setting up for personal use. `PicsumService`
(`lib/picsum_service.dart`) adds a "Random photo" / "Random photo (blurred)" option using
[picsum.photos](https://picsum.photos), a free, key-less random-image API — no signup, no
credentials, no rate-limit management. The Unsplash code path is untouched and still there,
dormant, in case a real Unsplash key gets added back later.

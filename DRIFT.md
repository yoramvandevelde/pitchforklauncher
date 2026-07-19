# Drift from upstream

This fork diverges from the original [FLauncher](https://gitlab.com/flauncher/flauncher) in a
few deliberate ways, listed here so it's clear what changed and why.

## Toolchain

- **Flutter pinned via FVM** (`.fvmrc`, `.fvm/`). The project didn't have a reproducible SDK
  version pinned to the working tree; FVM avoids depending on whatever Flutter happens to be
  globally installed, without touching any global/system Flutter install.

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

The same service also intercepts the remote's dedicated YouTube button and launches
`com.google.android.youtube.tv` directly, so the button keeps working even if you do disable the
stock launcher (README "Method 2") — normally that's what breaks it. The button doesn't send a
standard Android keycode; on this Google TV Streamer remote it's `KEYCODE_BUTTON_3` (190),
identified by temporarily logging every key event the service saw. Other remotes/devices may use
a different code — check `HomeButtonAccessibilityService.kt` if the button doesn't do anything.

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

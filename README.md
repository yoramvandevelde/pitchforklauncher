# PitchforkLauncher

A personal fork of FLauncher, an open source Android TV launcher, with a modernized stack and a
few new features. Built for and tested on a Google TV Streamer 4K (Android 14). Untested on other
devices.

This is a personal project. No feature requests, no ongoing support. Shared in case others find it
useful.

## Installation

Grab the latest APK from [Releases](https://github.com/yoramvandevelde/pitchforklauncher/releases)
and `adb install` it, or build it from source:
```shell
git clone https://github.com/yoramvandevelde/pitchforklauncher.git
cd pitchforklauncher
fvm install
fvm flutter build apk --debug
adb install build/app/outputs/flutter-apk/app-debug.apk
```

See `AGENTS.md` for the full toolchain setup (FVM, JDK 17, the `just` recipes used below). Once
installed, see "Set as default launcher" below to make it your home screen.

## Features

**No external telemetry.** No Firebase, no analytics, no crash reporting, nothing phoning home.

Other highlights:
- **Home Button override** (Accessibility Service): become the home screen without disabling the
  stock launcher, so things like the remote's dedicated YouTube button keep working. Comes with a
  trade off, see "Set as default launcher" below.
- **Remote button remapping**: map any other physical remote button to launch an app of your
  choice (Settings, "Remote buttons").
- **Key-less random wallpaper**, backed by [picsum.photos](https://picsum.photos). No API key
  needed.
- **Current toolchain**: Flutter 3.44, Android Gradle Plugin 8.13, Kotlin 2.4, compileSdk 36.

Plus the essentials the original FLauncher already got right:
- No ads
- Customizable categories, manually reorderable
- Wallpaper support
- Clock
- Open Android Settings, app info, uninstall an app, directly from the launcher
- Support for sideloaded (non-TV) apps

## Set as default launcher

There are two ways to make PitchforkLauncher your home screen, and they trade off differently.
Pick based on what matters more to you.

**Option A: make it the real default launcher.** This is the only way that gets correct Back
button behavior (pressing Back at the home screen does nothing, like a real launcher). The cost:
you disable the stock Google TV launcher, and its dedicated YouTube remote button stops working on
its own. This fork's remote button remapping already has YouTube pre-mapped by default, so it
keeps working with no extra setup, but if your remote sends a different code for that button and it
doesn't come back automatically, remap it yourself in Settings, "Remote buttons".

```shell
just disable-default-launcher <device-serial>
```

The next time you press Home, Android prompts you to choose PitchforkLauncher. To undo:

```shell
just restore-default-launcher <device-serial>
```

**Warning:** you are doing this at your own risk. Tested on a Google TV Streamer 4K only, may
behave differently on other devices.

**Option B: the built-in Home Button override.** Enable `HomeButtonAccessibilityService` in
Android's Accessibility settings. PitchforkLauncher then takes over the Home button without
touching the stock launcher at all, so the YouTube button and everything else the stock launcher
normally handles keeps working untouched. The trade off: PitchforkLauncher is not the real system
default this way, just a regular app brought to the front, so pressing Back at the home screen
exits back to whatever was open before instead of doing nothing. Known issue, not something this
fork tries to fix (see `TODO.md` for why).

**Option C: a third-party remap.** Use
[Button Mapper](https://play.google.com/store/apps/details?id=flar2.homebutton) to remap the Home
button of the remote to launch PitchforkLauncher. Doesn't touch the stock launcher, but needs an
extra app installed, and has the same Back button quirk as Option B.

## Wallpaper

Because Android's `WallpaperManager` isn't available on some Android TV devices, PitchforkLauncher
implements its own wallpaper management. Changing wallpaper via a custom image requires a file
explorer to be installed on the device to pick a file.

## About this fork

Not an Android or Flutter developer. Used Claude (Anthropic's AI) for almost all of the coding,
refactoring, and upgrade work, and made the design decisions and did the testing personally. See
`DRIFT.md` and `UPGRADE_PLAN.md` for the detailed history of what changed and why.

---

A personal fork of [FLauncher](https://gitlab.com/flauncher/flauncher) by Étienne Fesser. Thanks
for the solid foundation this is built on. Not affiliated with the original project or its Play
Store listing. Licensed under GPL-3.0, see `LICENSE`.

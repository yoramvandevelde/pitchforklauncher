# PitchforkLauncher

Personal FLauncher fork with a modern stack and new features for QoL.

This is my personal fork of FLauncher for my Google TV Streamer 4K. It's built for me, not as a
general project. I'm not a developer and I don't plan to take feature requests or provide ongoing
support. I'm sharing it because others might find it useful too.

## Features

The highlights — why this fork exists:
- **Home Button override** (Accessibility Service) — become the home screen without disabling the
  stock launcher, so things like the remote's dedicated YouTube button keep working.
- **Remote button remapping** — map any other physical remote button to launch an app of your
  choice (Settings → "Remote buttons").
- **Key-less random wallpaper**, backed by [picsum.photos](https://picsum.photos) — no API key
  needed.
- **Fully modern stack** — current Flutter, current Android toolchain, no Firebase, no telemetry.

Plus the essentials the original FLauncher already got right:
- No ads
- Customizable categories, manually reorderable
- Wallpaper support
- Clock
- Open Android Settings / app info, uninstall an app — directly from the launcher
- Support for sideloaded (non-TV) apps

## Why I made this fork

I wanted a bare-bones, up-to-date, no-bloat launcher for Android TV/Google TV. I really liked the
original FLauncher for its simplicity, but it had become outdated (Flutter 3.7 era) and some things
didn't work well for me (e.g. the Unsplash wallpaper integration requiring an API key).

So I:
- Modernized the entire stack (Flutter + Android toolchain + dependencies) in careful phases.
- Removed Firebase (Analytics/Crashlytics/Remote Config) completely.
- Added a built-in Home Button override via Accessibility Service so I don't have to disable the
  stock launcher (keeps dedicated remote buttons like YouTube working).
- Made any remote button mappable to launch apps.
- Replaced the wallpaper source with a simple, key-less Picsum.photos random photo option.
- Fixed various small issues along the way.
- Gave it its own name and repo once it had diverged enough to feel like its own project.

## How it was built

I did the design decisions and testing myself, but I used Claude (Anthropic's AI) for almost all
the coding, refactoring, and upgrade work. I'm not a coder — this fork wouldn't exist without AI
assistance. I've tried to keep changes clean and well-documented (see `DRIFT.md`,
`UPGRADE_PLAN.md`, and the commit history).

## Set PitchforkLauncher as default launcher

**Recommended: disable the stock launcher via ADB.** This is the only method that makes
PitchforkLauncher the *actual* system default (`isDefaultLauncher()` genuinely returns `true`) —
the other two methods below are more convenient in one way or another, but come with their own
quirks (see `TODO.md`).

```shell
just disable-default-launcher <device-serial>
```

That disables the stock Google TV launcher (and the setup-wizard fallback that would otherwise
take its place); the next time you press Home, Android prompts you to choose PitchforkLauncher.
To undo:

```shell
just restore-default-launcher <device-serial>
```

**:warning:** you're doing this at your own risk. Tested on a Google TV Streamer 4K only — may
differ on other devices. Disabling the stock launcher normally breaks the remote's dedicated
YouTube button, but this fork's built-in remote button remapping already has it covered — YouTube
comes pre-mapped by default, so it keeps working with no extra setup. If your remote sends a
different code for that button and it doesn't work automatically, remap it yourself in
Settings → "Remote buttons".

### Alternative 1: the built-in Home Button override

Enable `HomeButtonAccessibilityService` in Android's Accessibility settings. PitchforkLauncher
then takes over the Home button without touching the stock launcher at all — the YouTube button
and everything else the stock launcher normally intercepts keeps working untouched. Trade-off:
PitchforkLauncher isn't the *real* system default this way, just a regular Activity brought to the
front, so Back behaves slightly differently than a true default launcher (see `TODO.md`'s "Back
button leaves FLauncher" entry).

### Alternative 2: remap the Home button with a third-party app

Use [Button Mapper](https://play.google.com/store/apps/details?id=flar2.homebutton) to remap the
Home button of the remote to launch PitchforkLauncher. Doesn't touch the stock launcher, but needs
an extra app installed.

## Wallpaper

Because Android's `WallpaperManager` isn't available on some Android TV devices, PitchforkLauncher
implements its own wallpaper management. Changing wallpaper via a custom image requires a file
explorer to be installed on the device to pick a file.

---

This is a personal fork of [FLauncher](https://gitlab.com/flauncher/flauncher) by Étienne Fesser —
thanks for the solid, simple foundation this is built on. Not affiliated with the original project
or its Play Store listing. Licensed under GPL-3.0, see `LICENSE`.

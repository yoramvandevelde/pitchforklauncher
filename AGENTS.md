# Agent instructions

PitchforkLauncher is a personal fork of [FLauncher](https://gitlab.com/flauncher/flauncher), an
Android TV launcher built with Flutter. Read `README.md` first for what this fork changes and why,
`DRIFT.md` for the detailed rationale behind each change, `TODO.md` for known issues and open
items, and `ADR_001_Project_Scope_and_Feature_Governance.md` before proposing any new feature —
it's the gate new work gets weighed against, not just this project's history. This file is about
*working on the code* — toolchain, commands, conventions.

## Toolchain

- **Flutter is pinned via FVM**, not globally installed. Always run `fvm flutter ...` /
  `fvm dart ...`, never a bare `flutter`/`dart`. The pinned version is in `.fvmrc`; if `fvm` itself
  isn't installed, `brew install leoafarias/fvm/fvm` (or see fvm.app) then `fvm install`.
- **Gradle needs at least JDK 17** (Gradle 9.x dropped support for running its daemon on JDK 16 or
  older), but not necessarily the machine's default JDK. Pinned to **JDK 25** (LTS) as of
  2026-07-24 — verified by actually building on it (`fvm flutter build apk --debug`, clean install
  + launch on the emulator), not assumed. An earlier note here claimed AGP failed dexing above
  JDK 17; that turned out to be stale, dating back to this file's original AGP 7.1.1-era version
  and never re-checked through several AGP bumps since. JDK 21 and 25 both build cleanly on the
  current toolchain (AGP 9.3.1 / Gradle 9.6.1 / Kotlin 2.4.10) once a stale Gradle daemon isn't the
  actual culprit (`./android/gradlew -p android --stop` before switching JDKs if a build fails
  right after changing `JAVA_HOME`). Don't change a global/system Java version for this; set
  `JAVA_HOME` (and prepend `$JAVA_HOME/bin` to `PATH`) to a JDK 25 install for the duration of the
  build/test command instead, e.g.:
  ```shell
  export JAVA_HOME=/path/to/a/jdk-25
  export PATH="$JAVA_HOME/bin:$PATH"
  fvm flutter build apk --debug
  ```
  If `/usr/libexec/java_home -V` doesn't list a JDK 25, check whether one is managed by `mise`
  before installing a new one via Homebrew — `mise` installs land under
  `~/.local/share/mise/installs/java/...`, a path `java_home` doesn't scan, so a `mise`-managed JDK
  can look "missing" when it's actually already there. `mise list java` shows what's installed;
  `mise install java@temurin-25` then `mise where java@temurin-25` installs it and prints the exact
  path to use as `JAVA_HOME`.
- **Regenerate mocks after touching `test/mocks.dart`** (the `@GenerateMocks([...])` list) or any
  class it mocks:
  ```shell
  fvm flutter pub run build_runner build
  ```
- **Run tests** with `fvm flutter test`. Widget tests that navigate the Settings panels
  drive focus with `tester.sendKeyEvent(LogicalKeyboardKey.arrowDown)` — inserting or reordering a
  button in one of those panels shifts the arrow-key counts in every test after it in the same
  file. Check `fvm flutter analyze` too; it's fast and catches import-order/lint issues the tests
  won't.

## Running it

- **Emulator**: create an Android TV AVD. By default Android-TV AVDs ship with
  `hw.keyboard=no` in `~/.android/avd/<name>.avd/config.ini`, which silently disables the virtual
  keyboard/D-pad device entirely (both physical arrow keys and the Extended Controls D-pad stop
  working, while `adb shell input keyevent` still works since it bypasses that device). If D-pad
  input does nothing in the emulator, that's almost certainly it — set `hw.keyboard=yes` and cold
  boot (`-no-snapshot-load`); the emulator only reads that file at startup.
- **Real hardware**: Google TV devices don't expose USB debugging (removed for security since
  Android 14); use wireless debugging instead. On the device: Settings → System → About →
  tap the build number ~7 times to unlock Developer options, then Developer options → Wireless
  debugging. Pair once (`adb pair <ip>:<pairing-port>`, then the 6-digit code) — that pairing is a
  persistent trust relationship and survives reboots/network changes, but the **connect port is
  ephemeral** and changes on every reboot or Wireless-debugging toggle, so you'll need to re-read
  it from the device and `adb connect <ip>:<connect-port>` again each session; only a revoked
  pairing (or a wiped `~/.android/adbkey` on the host) needs `adb pair` again.
- Installing a debug build on Android 14 can hit `INSTALL_FAILED_VERIFICATION_FAILURE` (the
  stricter package verifier blocking sideloaded/adb installs). Fix:
  `adb shell settings put global verifier_verify_adb_installs 0` and
  `adb shell settings put global package_verifier_enable 0`.
- **Setting PitchforkLauncher as the Home app**: see the "Set as default launcher" section in
  `README.md` for the three options (disabling the stock launcher, this fork's built-in
  `HomeButtonAccessibilityService`, or Button Mapper). `justfile` has `disable-default-launcher` /
  `restore-default-launcher` recipes for the first option (`just <recipe> <adb-device-serial>`).

## Git

- `origin` should point at your own fork; `upstream` at the real upstream, which is
  **GitLab** (`https://gitlab.com/flauncher/flauncher.git`), not the GitHub mirror some search
  results point to — the GitHub mirror lags behind GitLab.
- This repo's commit convention: no AI co-author trailers in commit messages.

## Releases

- **Label every PR** before merging: `enhancement`, `bug`, or `dependencies` (Renovate PRs get
  `dependencies` automatically via `renovate.json`'s `labels` config). Tagging a release
  (`YYYY.MM.DD`, see `.github/workflows/release.yml`) auto-generates the "What's Changed" release
  notes, grouped by these labels per `.github/release.yml`. An unlabeled PR still shows up, but
  falls into a generic "Other Changes" bucket instead of the right category.

## License

GPL-3.0 (`LICENSE`). Every source file carries a header comment with the original copyright line
(`Copyright (C) 2021  Étienne Fesser`, the upstream author). When you modify an existing file,
keep that line and add your own copyright line beneath it rather than replacing it. When you add a
wholly new file (not derived from his code), the header should only carry your own copyright line.
Match the existing header format/wording in a neighboring file of the same language for the
boilerplate GPL text.

- **Bundled non-pub assets (fonts, etc.) need a manual `LicenseRegistry.addLicense()` call** in
  `main.dart`. Flutter's "VIEW LICENSES" screen (`FLauncherAboutDialog`) auto-collects licenses
  from pub dependencies only (including path/vendored ones, as long as they have a `LICENSE`
  file) — it does *not* scan `assets/`. See the Open Sans registration in `main.dart` for the
  pattern (load the license file via `rootBundle.loadString`, yield a
  `LicenseEntryWithLineBreaks`).

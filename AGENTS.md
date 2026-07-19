# Agent instructions

This is a personal fork of [FLauncher](https://gitlab.com/flauncher/flauncher), an Android TV
launcher built with Flutter. Read `README.md` first for what this fork changes and why, `DRIFT.md`
for the detailed rationale behind each change, and `TODO.md` for known issues and open items.
This file is about *working on the code* — toolchain, commands, conventions.

## Toolchain

- **Flutter is pinned via FVM**, not globally installed. Always run `fvm flutter ...` /
  `fvm dart ...`, never a bare `flutter`/`dart`. The pinned version is in `.fvmrc`; if `fvm` itself
  isn't installed, `brew install leoafarias/fvm/fvm` (or see fvm.app) then `fvm install`.
- **Gradle needs JDK 17**, not whatever newer JDK might be the machine's default — this project's
  Android Gradle Plugin version fails dexing on JDK 21+. Don't change a global/system Java version
  for this; set `JAVA_HOME` (and prepend `$JAVA_HOME/bin` to `PATH`) to a JDK 17 install for the
  duration of the build/test command instead, e.g.:
  ```shell
  export JAVA_HOME=/path/to/a/jdk-17
  export PATH="$JAVA_HOME/bin:$PATH"
  fvm flutter build apk --debug
  ```
- **Regenerate mocks after touching `test/mocks.dart`** (the `@GenerateMocks([...])` list) or any
  class it mocks:
  ```shell
  fvm flutter pub run build_runner build
  ```
- **Run tests** with `fvm flutter test`. Widget tests that navigate FLauncher's Settings panels
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
- **Setting FLauncher as the Home app**: see the "Set FLauncher as default launcher" section in
  `README.md` for the three options (Button Mapper, disabling the stock launcher, or this fork's
  built-in `HomeButtonAccessibilityService`). `justfile` has `disable-default-launcher` /
  `restore-default-launcher` recipes for the second option (`just <recipe> <adb-device-serial>`).

## Git

- `origin` should point at your own fork; `upstream` at the real upstream, which is
  **GitLab** (`https://gitlab.com/flauncher/flauncher.git`), not the GitHub mirror some search
  results point to — the GitHub mirror lags behind GitLab.
- This repo's commit convention: no AI co-author trailers in commit messages.

## License

GPL-3.0 (`LICENSE`). Every source file carries a header comment with the original copyright line
(`Copyright (C) 2021  Étienne Fesser`, the upstream author). When you modify an existing file,
keep that line and add your own copyright line beneath it rather than replacing it. When you add a
wholly new file (not derived from his code), the header should only carry your own copyright line.
Match the existing header format/wording in a neighboring file of the same language for the
boilerplate GPL text.

# Stack upgrade plan

Nothing in this fork has been upgraded since the initial fast-forward onto upstream's last commit
(Flutter 3.7.5, AGP 7.1.1, Gradle 7.4, Kotlin 1.6.10, compileSdk/targetSdk 33) — see `TODO.md`.
That's now three-ish years behind. This is a plan to close that gap safely, in reviewable steps,
rather than one big jump that makes it impossible to tell which change broke what.

**Ground rules for every phase below:**
- One phase at a time, on a dedicated branch (e.g. `upgrade/stack`), not directly on `master`.
- After each phase: `fvm flutter analyze` clean, full test suite green (currently 129 tests),
  then an actual smoke test on real hardware before moving on.
- Commit after each phase, not after the whole thing — so a bad step can be reverted without
  losing the good ones before it.

## Known landmines (found while scoping this, not yet hit)

Two things in the current codebase are near-certain to break and are worth knowing about before
starting, rather than being a surprise mid-upgrade:

- **`WillPopScope`** is used in `lib/flauncher_app.dart` and `lib/widgets/settings/settings_panel.dart`
  for the Back-button interception logic — this is load-bearing (it's how `isDefaultLauncher()` /
  `shouldPopScope()` decides whether Back exits FLauncher), not decorative. It's deprecated in
  favor of `PopScope`, which has different callback semantics (`onPopInvoked`/`canPop` instead of
  an awaitable `onWillPop`). Needs a deliberate rewrite, not a find-and-replace.
- **Deprecated `ThemeData` fields** (`accentColor`, `backgroundColor`) are used in
  `lib/flauncher_app.dart`, already marked `// ignore: deprecated_member_use`. Newer Flutter
  versions default to Material 3 (`useMaterial3: true` became the default around Flutter 3.16) and
  may have fully *removed*, not just deprecated, some of these fields by the version we land on —
  that's a compile error, not a lint warning, and the app's whole color scheme needs re-checking
  against Material 3 either way.

## Phase 0 — Safety net

- [ ] Commit and push everything currently pending (the button-remapping feature, docs).
- [ ] Create an `upgrade/stack` branch off `master`. Do the rest of this plan there.
- [ ] Confirm `fvm flutter test` is green and `fvm flutter analyze` is clean on `master` first —
      this is the baseline every later phase gets compared against.

## Phase 1 — Android toolchain (Gradle / AGP / Kotlin), Flutter version untouched

Do this before touching the Flutter SDK version, so a build failure here is unambiguously a
Gradle/Android problem, not tangled up with Dart/Flutter changes.

- [ ] **Research at this step:** current recommended AGP + Gradle + Kotlin trio for targeting
      compileSdk 34 (Android 14, matching the real Streamer's current OS — see AGENTS.md). AGP 7.1.1
      is old enough that this is likely AGP 8.x + Gradle 8.x + Kotlin 1.9.x or newer, but confirm
      against Flutter's own compatibility notes at the time, since these move faster than this plan
      will stay accurate.
- [ ] Bump `android/gradle/wrapper/gradle-wrapper.properties` (`distributionUrl`).
- [ ] Bump the AGP classpath in `android/build.gradle`.
- [ ] Flutter moved Kotlin version configuration from `android/build.gradle`'s `ext.kotlin_version`
      to `android/settings.gradle` at some point (part of a broader move away from the old
      imperative `apply plugin:` style to a declarative `plugins {}` block) — check whether the
      Flutter version we're targeting in Phase 2 expects this and migrate the Android project
      files' structure accordingly, not just the version numbers.
- [ ] Bump `compileSdkVersion` and `targetSdkVersion` in `android/app/build.gradle` to 34.
      `webview_flutter` (current version already, before even upgrading it further) wants
      `minSdkVersion` 24+; current is 21 — bump this too, it doesn't affect the personal-use
      target device.
- [ ] Build (`just build-install <device>`) against the *current* Flutter 3.7.5 to confirm the
      Android side alone still compiles. Install and smoke-test on real hardware.

## Phase 2 — Flutter SDK, one or two stops at a time

Jumping straight from 3.7.5 to latest skips ~35+ minor releases of deprecations and removals at
once, which makes failures hard to attribute. Step through a handful of intermediate stable
versions instead — a reasonable set of stops to research and pin `.fvmrc` to, testing at each one:

- [ ] A version just past the Dart 3 language release (roughly Flutter 3.10) — mostly additive
      (patterns, class modifiers, required named-param defaults), low risk, good first checkpoint.
- [ ] A version at/after Material 3 became the default (roughly Flutter 3.16) — this is where the
      "known landmines" above (`WillPopScope`, deprecated `ThemeData` fields) will actually surface
      as build failures. Fix `PopScope` migration and the theme here, deliberately, with the app
      running on real hardware to verify Back-button behavior specifically (that's core, tested
      functionality — don't just make it compile, re-verify the actual behavior).
- [ ] One or two more stops of your choosing spaced through the remaining gap (check
      `docs.flutter.dev/release/release-notes` for what each covers) — the point isn't to hit every
      single version, just to avoid one undifferentiated leap.
- [ ] Land on the actual latest stable (check what that is *at the time*, not what's written here
      today — this plan will already be stale by the time Phase 2 starts).

At each stop: `.fvmrc` bump → `fvm flutter pub get` → `fvm flutter analyze` → fix what's flagged →
`fvm flutter pub run build_runner build --delete-conflicting-outputs` (drift/mockito codegen) →
`fvm flutter test` → build + install + smoke test → commit → next stop.

## Phase 3 — Dependencies

Do this *after* the Flutter SDK is current — most packages gate their max supported version on
the Flutter/Dart SDK, so bumping dependencies first would just get capped by the old SDK anyway.

- [ ] Run `fvm flutter pub outdated` for the full picture before touching anything.
- [ ] `drift` + `drift_dev` + `sqlite3_flutter_libs` as one group (they need to move together).
      Current pin (2.5.0) already includes drift's big 2.0 breaking changes (nullability of
      `Expression`/`QueryRow.read`, `toSql`/`fromSql` renames) — those are done. What's ahead:
      drift 2.32 bumped its underlying `sqlite3` package to a 3.x major version, worth checking
      what that touches here (`NativeDatabase` construction in `lib/database.dart`, see
      `sqlite3_flutter_libs` usage). Regenerate codegen after bumping, diff the generated
      `database.drift.dart`/`mocks.mocks.dart` output to sanity-check nothing structural moved.
- [ ] `provider`, `path_provider`, `shared_preferences`, `package_info_plus`, `image_picker` — bump
      one at a time or in a batch if changelogs look clean; these have historically been lower-risk
      than drift or webview_flutter.
- [ ] `webview_flutter` — already noted above for its `minSdkVersion` 24 requirement; check its
      changelog for the version gap specifically (it's used for a small in-app browser: Unsplash
      photo attribution links, YouTube — actually no, just the "Photo by X on Unsplash" link in
      `wallpaper_panel_page.dart`).
- [ ] `unsplash_client` — the code path using it is currently dormant (`unsplashEnabled` hardcoded
      `false`, see `DRIFT.md`). Lowest priority; decide separately whether to keep it dormant,
      remove it, or actually wire up a real Unsplash key while touching this area — don't let it
      block the rest of the upgrade.
- [ ] `http` (used by `picsum_service.dart` and `unsplash_service.dart`) — check for breaking API
      changes, low risk historically.

## Phase 4 — Full regression pass

- [ ] `fvm flutter analyze` — zero issues, not just "no errors" (clear out warnings introduced
      along the way rather than letting them accumulate).
- [ ] Full test suite green.
- [ ] Manual smoke test on real hardware *and* both emulators (`GoogleTV_API31`, `GoogleTV_API34`):
      home grid navigation, categories, all four wallpaper sources (Gradient, Custom, Picsum
      plain/blurred, Unsplash if re-enabled), every Settings panel, the Home-button override, and
      the remote-button remapping feature built this session (including the Back-button-inside-a-
      dialog case that was buggy before — that's exactly the kind of thing a Flutter upgrade could
      silently re-break).
- [ ] Update `TODO.md` (remove the "upgrade Flutter" item) and `AGENTS.md`'s toolchain section
      once versions have actually moved.

## Phase 5 — optional / later

- [ ] compileSdk/targetSdk 35 (Android 15), only if there's an actual reason to — 34 already
      matches the real Streamer's current shipping OS (see AGENTS.md), so this isn't urgent.

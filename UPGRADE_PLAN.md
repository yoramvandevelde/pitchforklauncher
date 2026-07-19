# Stack upgrade plan

Nothing in this fork has been upgraded since the initial fast-forward onto upstream's last commit
(Flutter 3.7.5, AGP 7.1.1, Gradle 7.4, Kotlin 1.6.10, compileSdk/targetSdk 33) — see `TODO.md`.
That's now three-ish years behind. This is a plan to close that gap safely, in reviewable steps,
rather than one big jump that makes it impossible to tell which change broke what.

**Ground rules for every phase below:**
- One phase at a time, on its own branch off `master` (e.g. `upgrade/phase1-android-toolchain`,
  `upgrade/phase2-flutter-sdk`, ...), not directly on `master`.
- After each phase: `fvm flutter analyze` clean, full test suite green (currently 129 tests),
  then an actual smoke test on real hardware before moving on.
- Commit within the phase branch, push, and open a PR into `master` — don't merge it as the
  agent. The user reviews and merges each phase's PR themselves (also runs it through Codex
  review as a second pass) before the next phase branches off the updated `master`. This gives
  each phase an actual multi-step review checkpoint, not just an automated test pass.

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

- [x] Commit and push everything currently pending (the button-remapping feature, docs).
- [x] Confirm `fvm flutter test` is green and `fvm flutter analyze` is clean on `master` first —
      this is the baseline every later phase gets compared against.
- [x] Branch per phase off `master` (see ground rules above), merging back before starting the
      next one — not one long-lived `upgrade/stack` branch for everything.

## Phase 1 — Android toolchain (Gradle / AGP / Kotlin), Flutter version untouched

Do this before touching the Flutter SDK version, so a build failure here is unambiguously a
Gradle/Android problem, not tangled up with Dart/Flutter changes.

- [x] **Research at this step:** current recommended AGP + Gradle + Kotlin trio for targeting
      compileSdk 34 (Android 14, matching the real Streamer's current OS — see AGENTS.md). AGP 7.1.1
      is old enough that this is likely AGP 8.x + Gradle 8.x + Kotlin 1.9.x or newer, but confirm
      against Flutter's own compatibility notes at the time, since these move faster than this plan
      will stay accurate.
- [x] Bump `android/gradle/wrapper/gradle-wrapper.properties` (`distributionUrl`) → Gradle 8.4.
- [x] Bump the AGP classpath in `android/build.gradle` → 8.3.0, Kotlin → 1.9.22.
- [x] ~~Flutter moved Kotlin version configuration from `android/build.gradle`'s `ext.kotlin_version`
      to `android/settings.gradle`~~ — not needed yet. The old imperative `apply plugin:` /
      `ext.kotlin_version` style still works fine under AGP 8.3; that structural migration is tied
      to newer Flutter project templates, not to the AGP/Gradle version itself. Left for Phase 2 if
      the Flutter version we land on there actually requires it.
- [x] Bump `compileSdkVersion` to 35 (see landmine below — forced by `sqlite3_flutter_libs`,
      not originally planned for Phase 1) and `targetSdkVersion` to 34 in `android/app/build.gradle`.
      Also bumped `minSdkVersion` 21 → 24 (`webview_flutter` wants 24+; doesn't affect the
      personal-use target device).
- [x] Build (`just build-install <device>`) — see landmines below for what it actually took to get
      this compiling. `fvm flutter analyze` clean, all 129 tests still passing.
- [x] Install and smoke-test on real hardware — confirmed on the real Google TV Streamer 4K:
      app launch, button remapping (hotkeys), and the Picsum wallpaper fetch (network I/O) all
      still work. Not an exhaustive pass, but covers the newest feature and the most invasive
      toolchain change, which was judged good enough to merge this phase.

### Landmines actually hit in Phase 1 (not anticipated above)

- **Flutter 3.7.5's bundled `flutter.gradle` cannot run under Gradle 8 at all** — not a version
  mismatch, a hard failure (`No signature of method: Jar.destinationDir()`, an API Gradle 8 removed
  outright). AGP 8.x requires Gradle 8.x, and compileSdk 34 requires AGP 8.x — so Gradle 8 wasn't
  optional once compileSdk 34 was the target, which meant staying on 3.7.5 wasn't compatible with
  the rest of this phase's goal. The fix stayed inside this phase's spirit anyway: Flutter shipped
  the Gradle-8 fix as a **hotfix cherry-pick within the same 3.7 branch**, in 3.7.12 (confirmed via
  `gh api repos/flutter/flutter/compare/3.7.5...3.7.12` — 15 commits, all cherry-picked tooling
  hotfixes, no Dart/Flutter API changes). Bumped `.fvmrc` to 3.7.12. This is still "Flutter SDK
  untouched" in the sense that matters for Phase 1/2 separation — no language or framework surface
  changed, only tooling bugfixes.
- **AGP 8.0+ requires an explicit `namespace` in every module's build.gradle, with no manifest
  fallback** (`android:package` in `AndroidManifest.xml` is ignored). This broke every plugin whose
  Android implementation predates that requirement: `flutter_plugin_android_lifecycle`,
  `image_picker_android`, `package_info_plus`, `shared_preferences_android`, `webview_flutter_android`.
  Each needed bumping to its first version that declares `namespace` in `android/build.gradle`,
  while staying within this project's Dart <3.0.0 / Flutter 3.7.x SDK ceiling (still pre-Phase-3 in
  spirit — these are the *minimum* version bumps needed for AGP 8 to configure at all, not a general
  dependency refresh):
  - `flutter_plugin_android_lifecycle` (transitive) → 2.0.17
  - `package_info_plus` `^3.0.3` → `^4.0.0`
  - `shared_preferences` `^2.0.18` → `^2.2.2`
  - `image_picker` `^0.8.6+3` → `^1.0.4`
  - `path_provider` `^2.0.13` → `^2.1.1` (bumped alongside the others; its Android impl needed the
    same fix)
  - `webview_flutter` `^4.0.5` → `^4.4.2`
- **`sqlite3_flutter_libs` (already at the latest version this project's Dart-2.19 ceiling allows,
  0.5.42) requires `compileSdk` 35**, not 34 — a 16KB-page-size native library packaging
  requirement Android enforces from API 35 tooling onward. This is why `compileSdkVersion` ended up
  at 35 instead of the originally planned 34; `targetSdkVersion` stayed at 34 (compileSdk ahead of
  targetSdk is normal and doesn't change runtime behavior on the device).
- **JDK 17 + AGP 8 surfaced a latent Java/Kotlin JVM-target mismatch**
  (`compileDebugJavaWithJavac` defaulting to 1.8 vs `compileDebugKotlin` defaulting to 17) that
  Flutter's own Gradle defaults hadn't pinned down. Fixed by explicitly setting both to 17 in
  `android/app/build.gradle` (`compileOptions` + `kotlinOptions.jvmTarget`).

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

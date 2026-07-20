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

- [x] A version just past the Dart 3 language release (roughly Flutter 3.10) — landed on 3.10.7
      (latest patch in that branch). Tightened `pubspec.yaml`'s `environment` to
      `sdk: ">=3.0.0 <3.1.0"` / `flutter: ">=3.10.7 <3.11.0"` (widened again at the next stop).
      Turned out not to be as low-risk as expected — see landmine below, a real Flutter focus-
      traversal behavior change, not just a compile fix. `fvm flutter analyze` clean (only the
      pre-existing deprecation infos, no errors), all 129 tests passing, confirmed on real
      Google TV Streamer 4K hardware (thorough manual navigation pass through every menu,
      including a freshly-created app grid, plus the button-remapping and wallpaper-change
      regression checks from the previous phase).
- [x] A version at/after Material 3 became the default (roughly Flutter 3.16) — landed on 3.16.9
      (latest patch in that branch). `sdk: ">=3.2.0 <3.3.0"` / `flutter: ">=3.16.9 <3.17.0"`.
      `useMaterial3` becoming the default was handled by pinning `useMaterial3: false` explicitly
      — adopting Material 3 is a separate design decision, not something that should silently
      ride along with an SDK bump. `ThemeData.backgroundColor` is still only deprecated (not
      removed) at this version too — left alone, as planned, for a later stop.
      **`WillPopScope` → `PopScope` migration was attempted, caused a real freeze on real
      hardware, and was reverted** — `WillPopScope` is still only deprecated here, not a hard
      error, so this is deferred rather than blocking. See landmines below for the full story
      (this is the one worth reading before trying again). Also needed an unplanned
      `drift`/`drift_dev`/`sqlite3` bump just to get codegen running again (also below).
      `fvm flutter analyze` clean, all 129 tests passing, build succeeds, confirmed not
      regressing on real hardware *with the revert in place*.
- [x] A version past the Android-TV-relevant edge-to-edge `SystemUiMode` default change and the
      Material 3 token update (roughly Flutter 3.27) — landed on 3.27.4 (latest patch in that
      branch, Dart 3.6.2). `sdk: ">=3.6.0 <3.7.0"` / `flutter: ">=3.27.4 <3.28.0"`. Latest stable
      at the time this stop was picked was 3.44.6 — 3.27.4 is roughly the midpoint of the
      remaining 3.16.9→3.44.6 gap.
      `ThemeData.backgroundColor` (flagged as a future landmine at the 3.16.9 stop) and
      `Paint.enableDithering` were both hard removed at this version — see landmines below.
      Also needed a chain of dev-tooling-only fixes (not runtime code) to get
      `build_runner`/`mockito` codegen and `flutter test` working again under the Flutter-bundled
      Dart 3.6.2 — see landmines below, this is the bulk of what this stop actually took.
      `fvm flutter analyze` clean, all 129 tests passing, build succeeds, smoke-tested on the
      `GoogleTV_API34` emulator (app grid renders, wallpaper loads, Settings panel opens with
      correct theming, Back from Settings top level to home works without freezing — the real
      Google TV Streamer 4K hardware was in active use at the time. Real-hardware confirmation
      landed together with the 3.35.7 stop below (same install, cumulative).
- [x] One more stop, roughly the midpoint of the remaining 3.27.4→3.44.6 gap — landed on 3.35.7
      (latest patch in that branch, Dart 3.9.2). `sdk: ">=3.9.0 <3.10.0"` /
      `flutter: ">=3.35.7 <3.36.0"`. By far the biggest stop yet — see landmines below. In short:
      Flutter's Gradle plugin loader dropped the old imperative `apply from`/`apply plugin` style
      entirely (hard error, not just deprecated), forcing a migration of all three
      `android/*.gradle` files to the declarative `plugins {}` block; Flutter's v1 Android
      embedding was fully removed, breaking several plugins' Android implementations that still
      referenced it, requiring version bumps for `image_picker`, `path_provider`,
      `package_info_plus`, `shared_preferences`, `webview_flutter`, plus a
      `dependency_overrides` for the transitive `flutter_plugin_android_lifecycle`; one of those
      bumps (newer AndroidX Core) forced AGP 8.3.0 → 8.10.0, which forced Gradle 8.4 → 8.11.1 and
      compileSdk 35 → 36, which forced Kotlin 1.9.22 → 2.1.0 (metadata-version mismatch
      otherwise). The `dependency_overrides` added at the 3.27.4 stop
      (`frontend_server_client`, `win32`) turned out to be unnecessary here — the newer
      `build_daemon`/plugin versions this stop naturally resolves to already pull in
      versions that don't hit those bugs, so both were removed rather than carried forward
      unused. `fvm flutter analyze` clean, all 129 tests passing, build succeeds, confirmed on
      real Google TV Streamer 4K hardware — full manual pass (every menu, apps added/removed,
      categories created/renamed/moved/deleted, wallpaper changed, button remapping redone,
      Android settings navigated to and back, Accessibility service toggled off/on), no
      regressions found.
- [x] Land on the actual latest stable — latest stable at the time this stop was picked was 3.44.6
      (Dart 3.12.2, released 2026-07-09). `sdk: ">=3.12.0 <3.13.0"` / `flutter: ">=3.44.6 <3.45.0"`.
      Phase 2 is now complete. Needed a forced `drift`/`drift_dev` major bump (`^2.10.0` →
      `^2.34.0`, alongside `build_runner` and `mockito` bumps) to get codegen working again, and
      one real UI fix (a `ColoredBox`-over-`Material` ink-visibility issue in
      `right_panel_dialog.dart`) — see landmines below. `fvm flutter analyze` clean (same 66
      pre-existing deprecation infos as before, no new ones, no errors), all 129 tests passing,
      build succeeds (with soft "will soon be dropped" warnings for Gradle/AGP/Kotlin — see
      landmines), confirmed on real Google TV Streamer 4K hardware (switches — 24-hour time
      format, app-highlight-animation — button remapping, general navigation; not an exhaustive
      menu-by-menu pass this time, but nothing looked wrong).

At each stop: `.fvmrc` bump → `fvm flutter pub get` → `fvm flutter analyze` → fix what's flagged →
`fvm flutter pub run build_runner build` (drift/mockito codegen; `--delete-conflicting-outputs` is
now a no-op on `build_runner` 2.15+, see the 3.44.6 stop's landmines) → `fvm flutter test` →
build + install + smoke test → commit → next stop.

### Landmines actually hit at the 3.10.7 stop (not anticipated above)

- **`ThemeData.accentColor` was already removed (not just deprecated) at this version** — the
  plan expected this at the ~3.16 Material 3 checkpoint, but it's a hard compile error here
  already. Fixed by replacing it with `colorScheme: ColorScheme.fromSwatch(...).copyWith(secondary:
  ...)` in `lib/flauncher_app.dart`, which is what `accentColor` actually got folded into.
  `backgroundColor` (the other flagged field) is still only deprecated, not removed, at this
  version — left alone for the 3.16 stop as originally planned.
- **A genuine Flutter framework behavior change, not a compile issue**: `flauncher_test.dart`'s
  focus-traversal tests started failing. `RowByRowTraversalPolicy` (`lib/custom_traversal_policy.dart`)
  handles up/down and same-row left/right navigation itself, by design, specifically to avoid
  depending on Flutter's own "smart" directional focus search (see the class's own doc comment).
  But it silently *did* still fall through to that built-in search (`super.inDirection`) for one
  case: moving right past the last app in the topmost row, to reach the header's settings icon.
  Flutter's built-in heuristics for "nearest focusable node in that general direction" changed
  between 3.7 and 3.10, and this fell through to a different, wrong node (the row below) instead.
  Fixed by making that case explicit and version-independent: added
  `NodeSearcher.findCandidatesAboveOnSameSide`, which only looks for something both above *and*
  still to the right of the current node — reachable only from the actual topmost row (where
  nothing else is above), not from every other row (which correctly keeps "stays on the same
  row" behavior, verified by another existing test). Deliberately right-only, no symmetric
  left-side shortcut exists (nothing sits at the top-left).
- **Code review (GitHub Copilot, on the draft PR) caught a real latent bug in the fix above**:
  `findCandidatesAboveOnSameSide` matched *any* node above-and-right, not just the topmost one.
  It happened to still pass both existing tests only because of that test data's specific
  geometry (a 5-item row extends further right than a 2-item row above it, so nothing in the
  shorter row was ever actually "to the right" of the longer row's last item) — with 3+ rows, or
  different item counts, it could have matched an app card in a nearer row instead of the header,
  silently violating the "topmost row only" intent stated in its own comment. Fixed by keeping
  only the minimum-Y candidates among the above-and-right matches, so the header wins whenever
  it's actually a candidate.

### Landmines actually hit at the 3.16.9 stop (not anticipated above)

- **`PopScope` migration attempted, caused a real freeze on real hardware, reverted to
  `WillPopScope` for now.** Long entry, deliberately — this is exactly the kind of thing to read
  before trying again, not just a line to check off.

  `PopScope`'s API is structurally different from `WillPopScope`, not a drop-in rename —
  `onWillPop` was an awaitable `Future<bool> Function()` that could still prevent the pop at the
  moment it was called; `PopScope.canPop` is synchronous and decided in advance, and
  `onPopInvoked(bool didPop)` only fires *after* the pop attempt already happened or was blocked
  by `canPop`. Both of this app's usages (`lib/flauncher_app.dart`'s Back-button/ambient-mode
  logic, `lib/widgets/settings/settings_panel.dart`'s nested-Navigator-aware dialog dismissal)
  depend on an async check (`AppsService.isDefaultLauncher()` over a platform channel, and nested
  `Navigator.maybePop()`, respectively) to decide whether to allow the pop — impossible to
  express as a synchronous `canPop`. Migrated both to the standard async pattern: `canPop: false`
  unconditionally (block every pop up front), then do the async check inside `onPopInvoked` and
  manually trigger the equivalent of "the pop succeeding" ourselves (`SystemNavigator.pop()` /
  `Navigator.of(context).maybePop()`) if it should have been allowed — since `canPop: false`
  means the original pop never actually goes through on its own anymore. `flutter analyze` and
  all 129 widget/unit tests were clean with this in place — the bug never showed up in
  automated testing, only on real hardware.

  **The freeze, as reproduced on real Google TV Streamer 4K hardware**: open FLauncher's
  Settings ("menu"), and from the Settings panel's *top level* (not a sub-page), press Back to
  return to FLauncher's home screen — the app freezes completely. No crash, no ANR, the Activity
  stays `mResumed=true`. Confirmed via `adb bugreport`: `Choreographer.mLastFrameTime` was over
  4 minutes stale with `mFrameScheduled=false` (nothing was even asking for a new frame), and
  `WindowManagerShell`/`BLASTSyncEngine` logged `Unfinished container` entries for FLauncher's
  own task — i.e. the window manager was left waiting on a sync transaction from FLauncher's
  window that never completed. Worth noting for future debugging: even the remote's dedicated
  YouTube button stopped working once frozen — that's handled entirely natively by
  `HomeButtonAccessibilityService` with no Dart/platform-channel involvement at all, so its
  failure too points at something blocking at the window/rendering level, not just a stuck Dart
  `Future`. Also found, and left in place since it's correct regardless: this app's manifest
  never declared `android:enableOnBackInvokedCallback`, yet `logcat` showed Android's
  `CoreBackPreview` registering a predictive-back `OnBackInvokedCallback` for the app anyway —
  the documented recommendation for any app using `PopScope` on Android 13+ is to declare that
  flag explicitly; this was added during the investigation but reverted along with `PopScope`
  itself, since testing it in combination with `WillPopScope` (the reverted state) is untested
  territory of its own.

  No Dart exception, no native exception, nothing in `logcat` across two separate live-captured
  reproductions (via `adb logcat -d` immediately after freezing, and an `adb bugreport` while
  frozen) pointed at a specific line of code — this is a real, reproducible bug, but remote
  debugging against someone's daily-driver TV via `adb`/`logcat`/`bugreport` archaeology wasn't
  enough to root-cause it, and repeated reproduction meant repeated frozen-device recovery
  (force-stop, sometimes a full power cycle) for no forward progress. Reverted `PopScope` back to
  `WillPopScope` in both files (and reverted the manifest flag alongside it) rather than keep
  spending the user's hardware time on speculative fixes.

  **Before attempting this migration again**: do it with `flutter run` and a live attached debug
  console/DevTools (an emulator would do, if this reproduces there too — untested) so an actual
  Dart stack trace or engine-level log is available at the moment of the freeze, instead of
  reconstructing it after the fact from `adb bugreport`. Suspect areas worth checking first:
  whether `PopScope`'s `onPopInvoked` interacts badly with a dialog route pushed via
  `showDialog()`'s default `useRootNavigator: true` (a *different* root-navigator gotcha than the
  one already documented in `DRIFT.md` for `ButtonMappingPanelPage`, but the same family of bug);
  and whether `SystemNavigator.pop()` or `Navigator.of(context).maybePop()` called from inside an
  async `onPopInvoked` can race with the window manager's own BLAST sync barrier during the
  Activity's back-transition animation.
- **`drift_dev` 2.5.2 (unrelated to the Flutter SDK bump itself) stopped working with the
  `analyzer` package version that `build_runner`/`watcher` pulled in once *those* were bumped to
  fix their own incompatibility with newer Dart** (`watcher` 1.0.2 extended a `dart:io` class that
  became `sealed`; bumping `watcher`/`build_runner` transitively pulled `analyzer` 5.13.0, and
  `drift_dev` 2.5.2's generated-code visitor didn't implement a method that version of `analyzer`
  added). This is exactly the "drift + drift_dev + sqlite3_flutter_libs move together" dependency
  group the plan flagged for Phase 3 — but it became a hard blocker for Phase 2's codegen, not
  something that could wait. Bumped `drift` and `drift_dev` `^2.5.x` → `^2.10.0`, the highest pair
  still within this stop's Dart 3.2.x ceiling (2.16.0+ needs Dart 3.3). Pulled `sqlite3` 1.9.1 →
  2.4.0 (a major version bump) transitively — no compile errors surfaced from it, `NativeDatabase`
  usage in `lib/database.dart` is apparently unaffected, but worth keeping in mind as something
  Phase 3's planned `sqlite3` 3.x check should re-verify more thoroughly (schema/migration tests
  passed here, but this wasn't a deliberate, deep review of that bump).

### Landmines actually hit at the 3.27.4 stop (not anticipated above)

- **`ThemeData.backgroundColor` and `Theme.of(context).backgroundColor` were hard removed** (this
  was flagged as expected at this stop already). Folded into `colorScheme.surface` instead —
  added `surface: _swatch[400]` to the `ColorScheme.fromSwatch(...).copyWith(...)` call in
  `lib/flauncher_app.dart`, and changed `lib/widgets/right_panel_dialog.dart` to read
  `Theme.of(context).colorScheme.surface` instead of the removed getter. Same pattern as the
  `accentColor` → `colorScheme.secondary` fix from the 3.10.7 stop.
- **`Paint.enableDithering` (the static setter in `lib/main.dart`) was removed.** Dithering is
  now always on by default (Impeller couldn't support a global toggle, so the option was dropped
  entirely rather than just deprecated further) — the line was simply deleted, nothing to
  replace it with.
- **A chain of dev-tooling-only breakage, nothing to do with the app's own code, needed to get
  `build_runner` and `flutter test` working again under this stop's bundled Dart (3.6.2):**
  1. `pub run build_runner build` failed outright with `Could not find a command named
     ".../frontend_server.dart.snapshot"` — the Flutter-bundled Dart SDK from this stop onward no
     longer ships that JIT snapshot at all (only `frontend_server_aot.dart.snapshot`), but the
     transitively-pinned `frontend_server_client` 3.2.0 (pulled in via `build_daemon` →
     `build_runner`) only knew how to start the frontend server from the JIT one. Fixed via a
     `dependency_overrides: frontend_server_client: ^4.0.0` in `pubspec.yaml` — that version
     prefers the AOT snapshot when present. This is a transitive dev-only package we don't import
     directly, so a `dependency_overrides` pin (with a comment explaining why) was used instead of
     dragging it into `dev_dependencies` as a fake direct dependency.
  2. With that fixed, build_runner's own *build script precompile* step then failed differently:
     `build_runner_core` 7.2.7/7.2.8's `BuildForInputLogger implements Logger` was missing an
     override for `Logger.onLevelChanged` — a member the `logging` package added in 1.2.0.
     `logging` only reached 1.2.0+ transitively as a side effect of chasing fix #1 above (an
     unconstrained `pub upgrade build_daemon --unlock-transitive` pulled it in), and
     `build_runner_core` had a matching fix for exactly this in 7.2.9. Rather than leave that as a
     second override, this one was resolved by letting `pub upgrade` (full, unconstrained) settle
     everything at once — see #3.
  3. That, in turn, resolved `build_resolvers` to a version that itself couldn't co-exist with
     `build_runner_core` 8.0.0 (`Conflicting outputs: Both build_resolvers:transitive_digests and
     build_resolvers:transitive_digests may output lib/flauncher.dart.transitive_digest` — the
     same builder registered twice). This turned out to be a real bug fixed in `build_runner`
     2.5.1 ("don't run builders with multiple outputs once per output"), but 2.5.0+ requires Dart
     `^3.7.0` — one minor above this stop's bundled 3.6.2, so that fix isn't reachable here.
     **What actually resolved it**: running a full unconstrained `fvm flutter pub upgrade` (no
     package names) let pub's resolver settle on a mutually-compatible combination
     (`build_resolvers` 2.4.4, `build_runner` 2.4.15, `build_runner_core` 8.0.0) that doesn't hit
     the bug in practice, without needing 2.5.1's actual fix. This also dragged `analyzer` all the
     way to 7.7.1 as a side effect, which promptly broke `mockito` 5.4.1's generated-mock builder
     (`InterfaceElement` vs `InterfaceElementImpl` assignment errors — an internal API mockito
     relies on that changed within analyzer 7.x despite mockito's own `analyzer: >=6.9.0 <8.0.0`
     constraint technically allowing it). Fixing *that* properly needs `mockito` 5.5.1+, which
     itself requires `analyzer: ^8.1.0` — a bigger jump than this stop should be making for a
     dev-only tool. **Decision: reverted `pubspec.lock` back to the pre-upgrade baseline and did
     this surgically instead** — `dependency_overrides` for `frontend_server_client: ^4.0.0` only
     (fix #1), nothing else. That alone was sufficient: `build_runner` 2.4.9's own bundled
     `build_runner_core`/`build_resolvers` versions (7.2.7/2.2.0) don't hit the conflicting-outputs
     bug when `frontend_server_client` is the only thing bumped — the bug in #2/#3 above only
     appeared once the broad `pub upgrade` cascade was already in motion. Lesson for future stops:
     prefer the narrowest possible fix and re-test before reaching for a broad `pub upgrade`; the
     broad upgrade here manufactured two additional problems that a scoped fix didn't have.
  4. Separately, `flutter test` (not `build_runner`) failed to *compile* on this macOS dev host
     with `Type 'UnmodifiableUint8ListView' not found` in `win32`'s `Guid` class —
     `path_provider_windows`/`shared_preferences_windows` (desktop federated implementations,
     unused on Android but still compiled for host-side `flutter test`) pull in `win32`, and
     `win32` 4.1.4's code referenced a `dart:typed_data` class removed from the SDK at Dart 3.6.
     Fixed via a second `dependency_overrides` entry: `win32: ">=5.5.1 <5.11.0"` — 5.5.1 is the
     first version that migrated away from `UnmodifiableUint8ListView`, and the upper bound is
     needed because win32 5.11.0+ requires Dart `^3.7.0` (same ceiling as the build_runner 2.5.x
     line above) and fails to even parse otherwise ("The specified language version is too high").
  Net result: two narrow, commented `dependency_overrides` entries for dev/build-only transitive
  packages, no changes to any package actually shipped in the APK.

### Landmines actually hit at the 3.35.7 stop (not anticipated above)

By far the biggest stop so far — a chain of five forced changes, each one triggered by the fix
for the previous one. Worth reading in order if hitting something similar at a later stop.

1. **Flutter's Gradle plugin loader stopped supporting the old imperative `apply from`/
   `apply plugin` style entirely** (a hard `FAILURE: Build failed` at Gradle configuration time,
   not a deprecation warning — the 3.27.4 stop's build already printed a warning about this, but
   it kept working until now). Migrated all three `android/*.gradle` files to Flutter's
   documented declarative-`plugins{}` style
   (`docs.flutter.dev/release/breaking-changes/flutter-gradle-plugin-apply`):
   `android/settings.gradle` gained a `pluginManagement {}` block that resolves
   `flutter.sdk` from `local.properties` and declares AGP/Kotlin versions via
   `id "com.android.application" version "..." apply false` /
   `id "org.jetbrains.kotlin.android" version "..." apply false`, plus
   `id "dev.flutter.flutter-plugin-loader" version "1.0.0"`; `android/build.gradle` lost its
   entire `buildscript {}` block (AGP/Kotlin versions now live in `settings.gradle` instead);
   `android/app/build.gradle` replaced `apply plugin: '...'` / `apply from: '.../flutter.gradle'`
   with a `plugins {}` block at the very top of the file (Gradle requires it to be the first
   statement — the original imperative code did its `local.properties`/signing-config setup
   *before* the plugin application, which had to move after the `plugins {}` block instead), and
   dropped the `implementation "org.jetbrains.kotlin:kotlin-stdlib-jdk7:$kotlin_version"` line
   (the `kotlin_version` variable no longer exists once `ext.kotlin_version` is gone from
   `build.gradle`, and the Kotlin Gradle plugin brings the stdlib in on its own now anyway).
2. **Flutter's v1 Android embedding was fully removed**, not just deprecated — broke the Java/
   Kotlin source of several plugins' Android implementations that still had a
   `registerWith(PluginRegistry.Registrar)` fallback method left over from years-old v1/v2
   dual-support code (`error: cannot find symbol ... class Registrar`). Hit this one plugin at a
   time, as each successive build reached the next broken one: `flutter_plugin_android_lifecycle`
   (transitive, fixed via `dependency_overrides: ^2.0.28`), then `image_picker_android` (fixed by
   bumping the direct `image_picker` dependency to `^1.2.0`), then `path_provider_android`,
   `shared_preferences_android` and `webview_flutter_android` (fixed by bumping `path_provider`,
   `shared_preferences`, `webview_flutter` directly). `package_info_plus` was bumped alongside
   the others pre-emptively (`^4.0.0` → `^8.0.0`) rather than waiting for its own build failure,
   since it's the same plugin generation and was already flagged as likely next.
3. **`package_info_plus` 8.0.0's `PackageInfoPlatform.getAll` gained a new optional `baseUrl`
   parameter**, breaking `_MockPackageInfoPlatform`'s override in
   `test/widgets/settings/settings_panel_page_test.dart` (`invalid_override` — a real
   `flutter analyze` error, not just a test failure). Fixed by adding the same optional parameter
   to the mock's override signature.
4. **One of the plugin bumps above (image_picker's newer `image_picker_android`, pulling a newer
   AndroidX Core transitively) forced a cascade of Android toolchain bumps that had nothing to do
   with plugins directly**: `androidx.core:core:1.18.0` requires AGP ≥ 8.9.1 and `compileSdk` ≥
   36 — bumped AGP 8.3.0 → 8.10.0 (the lowest AGP version whose documented max supported API
   level is actually 36; 8.9.x tops out at 35 despite satisfying the ≥8.9.1 requirement on paper)
   and `compileSdkVersion` 35 → 36 in `android/app/build.gradle`. AGP 8.10.0 in turn requires
   Gradle ≥ 8.11.1 — bumped `android/gradle/wrapper/gradle-wrapper.properties` 8.4 → 8.11.1. That
   newer AGP/Gradle pair then failed Kotlin compilation of `image_picker_android`'s own Kotlin
   sources with `Class 'kotlin.Unit' was compiled with an incompatible version of Kotlin` (its
   prebuilt `.jar` was compiled with Kotlin 2.1.20's metadata, unreadable by our Kotlin
   1.9.22 compiler) — bumped Kotlin 1.9.22 → 2.1.0 in `android/settings.gradle`'s `plugins {}`
   block (the version Flutter's own build output had already been warning was needed).
5. **Two more landmines, unrelated to any of the above, just to get a clean build on this dev
   machine specifically**: two separate NDK versions (25.1.8937393, then 27.0.12077973 once AGP
   8.10.0 requested the newer default) had corrupted local installs — only an empty `.installer`
   directory, no actual NDK content, causing `[CXX1101] NDK ... did not have a source.properties
   file`. Both were fixed the way Flutter's own error message suggests: delete the local copy
   under `$ANDROID_HOME/ndk/<version>` and let Gradle re-download it cleanly. Separately, the
   Jetifier transform step ran out of heap (`Java heap space` while transforming
   `armeabi_v7a_debug...jar`) under the project's existing `org.gradle.jvmargs=-Xmx1536M` — bumped
   to `-Xmx4G` in `android/gradle.properties`. Neither of these is a code landmine future stops
   need to worry about, but worth knowing about if `[CXX1101]` or `Java heap space` show up again
   on a fresh machine.
6. **Bonus cleanup, not a landmine**: the two `dependency_overrides` added at the 3.27.4 stop
   (`frontend_server_client`, `win32`) turned out to be unneeded at this stop — the newer
   `build_daemon`/plugin versions this stop's dependency resolution naturally settles on already
   pull in versions past the point those bugs were fixed, without forcing anything. Removed both
   rather than carrying forward `dependency_overrides` nothing actually depends on anymore. Worth
   re-checking at *every* stop whether previously-added overrides are still load-bearing, since
   they're easy to forget about once they stop being necessary.

**Update**: the fuller manual pass landed after all — every menu opened, apps added/removed,
categories created/renamed/moved/deleted, wallpaper changed, button remapping redone, Android
settings navigated to and back (the historically freeze-prone path), Accessibility service
toggled off and on. All clean, no regressions found. 3.35.7 is fully hardware-confirmed.

### Landmines actually hit at the 3.44.6 stop (not anticipated above)

The final Phase 2 stop. Smaller than 3.35.7, but with one genuine (if narrow) UI bug and one
confusing dev-tooling dead end.

1. **`analyzer` 5.13.0 (pulled in by the still-old `build_runner`/`drift_dev`/`mockito` pins)
   couldn't parse Flutter's own framework source under the new Dart 3.12 language version** —
   `build_runner build` failed with `drift_dev:not_shared` errors like `Could not resolve Dart
   library package:flutter/src/foundation/diagnostics.dart` / `Expected an identifier` while
   analyzing `lib/database.dart`. Root cause: the pinned `build_runner: ^2.3.3` / `drift_dev:
   ^2.10.0` / `mockito: ^5.4.1` versions all cap `analyzer` well below what's needed to parse
   syntax used inside the Flutter SDK itself at this version. Fixed by bumping the whole codegen
   toolchain together: `drift` `^2.10.0` → `^2.34.0` (must move in lockstep with `drift_dev`, per
   the Phase 3 note above — this ended up forced here rather than waiting), `drift_dev` `^2.10.0`
   → `^2.34.0`, `build_runner` `^2.3.3` → `^2.4.9`, `mockito` `^5.4.1` → `^5.4.4` (actual resolved:
   `build_runner` 2.15.1, `mockito` 5.7.0, `analyzer` 13.0.0). Regenerated `lib/database.drift.dart`
   (drift's generated-file naming, not `.g.dart` — large diff, but mechanical/generated) and
   `test/mocks.mocks.dart`. `sqlite3` moved 2.4.0 → 3.5.0 transitively via the `drift` bump — this
   is the exact "drift + drift_dev + sqlite3 move together, watch the 3.x bump" note Phase 3
   already flagged, just forced early. All 129 tests still passed after the regen, so nothing
   structural in the schema/migrations broke.
2. **Red herring while debugging #1**: after bumping `build_runner` to 2.15.1, `build_runner
   build` failed differently — `Couldn't resolve the package 'build_runner_core'` while
   precompiling the generated `.dart_tool/build/entrypoint/build.dart`, even though
   `build_runner_core` was correctly no longer a dependency at all (it was merged into
   `build_runner` itself as of a recent version; `pub upgrade`'s own output even listed it under
   "no longer being depended on"). This was purely a **stale `.dart_tool/build/` cache** left over
   from the old `build_runner` version's last run — `rm -rf .dart_tool/build` wasn't enough (still
   failed the same way), but `rm -rf .dart_tool` entirely (forcing a full `flutter pub get` +
   fresh build-script generation) fixed it immediately. Worth trying first, before assuming a real
   dependency problem, if `build_runner_core`-flavored errors show up again after a `build_runner`
   bump. Also noted in passing: `--delete-conflicting-outputs` is now a no-op ("These options have
   been removed and were ignored") — newer `build_runner` deletes conflicting outputs by default,
   the flag is harmless to keep passing but does nothing.
3. **A genuine new Flutter framework assertion, not a compile issue**: `flauncher_test.dart`'s
   "Pressing select on settings icon opens SettingsPanel" test started failing with `ListTile
   background color or ink splashes may be invisible` — a new debug-mode Material assertion that
   fires when a `ListTile` (here, the ones `SwitchListTile` builds internally for the two switches
   in `SettingsPanelPage` — "Use 24-hour time format", "App card highlight animation") is
   separated from its nearest `Material` ancestor by an intervening opaque `ColoredBox`, since
   `ListTile` paints its ink effects on that `Material`'s render layer, which then ends up
   *underneath* the `ColoredBox` in paint order (the ancestor lookup for *which* `Material` to use
   still succeeds via `InheritedWidget`, it's specifically the paint-order layering that breaks).
   The culprit: `lib/widgets/right_panel_dialog.dart`'s `Container(padding: ..., color:
   Theme.of(context).colorScheme.surface, width: ..., child: ...)` — a `Container` with only
   `color`+`padding`+`width` set, which Flutter collapses into exactly this kind of `ColoredBox`,
   sitting between `Dialog`'s own `Material` and everything `RightPanelDialog` wraps (not just
   `SettingsPanelPage` — every panel routed through it shares this). Fixed by making the panel
   surface itself a `Material` instead of a colored `Container`: wrapped the inner `Container` (now
   just `padding`+`width`, no `color`) in `Material(color: Theme.of(context).colorScheme.surface,
   child: ...)`. All 129 tests pass with this in place.
4. **Not a landmine, just noting it happened automatically**: `flutter build apk` silently added
   `android.builtInKotlin=false` and `android.newDsl=false` to `android/gradle.properties` itself
   (commented as "added automatically by Flutter migrator") — opting out of newer AGP
   Kotlin-DSL/build-config behavior this Flutter version now defaults toward. Left as-is since the
   build succeeds either way and this is Flutter's own documented migration mechanism, not a
   manual workaround.
5. **Not a landmine yet, just a warning worth tracking**: `flutter build apk` now prints
   "will soon be dropped" support warnings for the current Gradle (8.11.1, wants ≥8.14.0), AGP
   (8.10.0, wants ≥8.11.1) and Kotlin (2.1.0, wants ≥2.2.20) versions — all soft warnings, the
   build still succeeds, left alone for this stop since none of them are hard errors yet. Likely
   the next thing to hit as a hard requirement if this project's Flutter version is bumped again
   past 3.44.x, or possibly worth doing proactively early in Phase 3/4 instead of waiting for a
   forced break.

Phase 2 is now complete — Flutter 3.7.5 → 3.44.6, latest stable, all five stepping stones landed
and hardware-confirmed.

## Phase 3 — Dependencies

Do this *after* the Flutter SDK is current — most packages gate their max supported version on
the Flutter/Dart SDK, so bumping dependencies first would just get capped by the old SDK anyway.

- [x] Run `fvm flutter pub outdated` for the full picture before touching anything — done
      2026-07-20, informed the ordering below.
- [x] `drift` + `drift_dev` as one group — done, forced early by the 3.44.6 Phase 2 stop's codegen
      breakage (see that stop's landmine #1): `drift`/`drift_dev` `^2.10.0` → `^2.34.0`, pulling
      `sqlite3` 2.4.0 → 3.5.0 transitively. All 129 tests passed after the regen; no deliberate
      deep review of the `sqlite3` 3.x bump's `NativeDatabase` implications happened, though —
      still worth a closer look here if anything database-related looks off later.
      `sqlite3_flutter_libs` itself is still on its original pin (`^0.5.13`, resolves 0.5.42) and
      hasn't been touched.
- [x] `provider` `^6.0.5` → `^6.1.5+1`, `path_provider` `^2.1.5` → `^2.1.6`, `image_picker`
      `^1.2.0` → `^1.2.3` — low-risk patch/minor bumps, no code changes needed, no new
      `flutter analyze` issues, all 129 tests passing.
- [x] `package_info_plus` `^8.0.0` → `^10.2.1` — no breaking changes for `PackageInfo.fromPlatform()`
      or the test mock, but `9.0.0+` requires AGP ≥8.12.1 / Gradle ≥8.13 / Kotlin 2.2.0, forcing an
      Android toolchain bump alongside it (see landmines below). `shared_preferences` needed no
      change at all — already resolving to `2.5.5` (latest) under the existing `^2.3.3` constraint.
- [x] `webview_flutter` `^4.10.0` → `^4.14.1` — no breaking changes, new SDK floor (Flutter ≥3.38,
      Dart ≥3.10) already well below what this project is on. Pulled `webview_flutter_wkwebview`
      3.25.0 → 3.26.0 transitively; `webview_flutter_android` untouched (still 4.12.0, already
      satisfies the new constraint).
- [x] `unsplash_client` — **decided to leave on `^2.1.0+3` (resolves 2.2.0), not bump to the
      breaking 3.0.0.** The code path is still fully dormant (`unsplashEnabled` hardcoded `false`),
      so a major-version bump there is pure risk for zero runtime benefit right now. Tracked as a
      real open decision in `TODO.md` ("Revisit the dormant Unsplash wallpaper source") rather than
      silently deferred.
- [x] `http` — was never actually declared in `pubspec.yaml` despite being imported directly in
      `lib/picsum_service.dart` and `lib/unsplash_service.dart` (relying entirely on transitive
      resolution). It had already jumped a full major version, `0.13.5` → `1.6.0`, as a side effect
      of the `package_info_plus` bump above — `package_info_plus` 10.2.1 itself pins `http: ^1.6.0`
      directly, and `unsplash_client`'s looser `>=0.13.0 <2.0.0` constraint didn't conflict with
      that. That transitive jump happened *before* this bullet was touched at all; adding
      `http: ^1.6.0` as an explicit direct dependency here didn't change the resolved version
      further, it only stopped the app from depending on an undeclared transitive package. Worth
      being explicit about, since "no behavior change" undersold a real major-version jump that did
      happen this phase — `fvm flutter analyze`/`test` stayed clean through it, and neither service
      file uses anything from the `http` 0.13.x→1.x breaking-change surface (both just call the
      package-level `get()`/`get`-style helpers), but this wasn't a deliberate changelog review of
      that jump, just an absence of symptoms.

Phase 3 is now feature-complete (all six bullets above done); still needs the hardware smoke test
and PR review before it's actually merged.

### Landmines hit during Phase 3

- **Picking the toolchain versions for the `package_info_plus` 9.0.0+ forced bump wasn't a single
  lookup** — its own floor is AGP ≥8.12.1 / Gradle ≥8.13 / Kotlin 2.2.0, but Android's own
  AGP↔Kotlin compatibility table (`developer.android.com/build/kotlin-support`) puts Kotlin 2.2.x's
  *supported* AGP range at only up to 8.10 — AGP 8.13 actually wants Kotlin 2.4.x+. Landed on AGP
  `8.13.0` (latest 8.x patch; deliberately *not* AGP 9.x, which is a bigger structural jump — see
  below), Gradle `8.14.5` (latest 8.x patch, also clears Phase 2's 3.44.6-stop "will soon be
  dropped" warning which wanted ≥8.14.0), Kotlin `2.4.10` (latest patch, satisfies both
  `package_info_plus` and the AGP compatibility table). Worth remembering next time a similar
  "package X wants AGP ≥Y" landmine shows up: check the *actual* AGP↔Kotlin pairing table too, not
  just the one package's stated floor, or the build fails on a Kotlin metadata-version mismatch
  again (same failure mode as the 3.35.7 stop's `image_picker_android` issue).
- **AGP 9.x already exists (released Jan 2026) and was deliberately not taken here** — it comes
  with its own DSL/API migration (see `developer.android.com/build/releases/gradle-plugin-roadmap`),
  which is a structural change in the same spirit as the 3.35.7 stop's `apply plugin:` →
  `plugins {}` migration, not something to fold silently into a dependency-driven bump. Staying on
  the latest AGP *8.x* patch (`8.13.0`) satisfies every current requirement; the AGP 9 migration is
  its own future piece of work if it ever becomes necessary.
- **Stale Gradle build cache after the AGP/Gradle/Kotlin bump** produced a real-looking compile
  error — `cannot find symbol ... class PackageInfoPlugin` in the auto-generated
  `GeneratedPluginRegistrant.java`, even though that file correctly referenced the right class and
  `.flutter-plugins-dependencies` correctly pointed at `package_info_plus-10.2.1`. Same family of
  problem as the 3.44.6 stop's `build_runner_core` red herring: the actual dependency graph was
  fine, a leftover cache from the pre-bump toolchain wasn't. Fixed by `./gradlew --stop` (kill the
  Gradle daemon) followed by `fvm flutter clean` (wipes `build/`, `.dart_tool/`, and
  `.flutter-plugins-dependencies` so they regenerate fresh) and a clean rebuild. Worth trying this
  combination first, before assuming a real dependency/code problem, any time an Android toolchain
  version bump (AGP/Gradle/Kotlin) is immediately followed by a "cannot find symbol" error for a
  plugin class that clearly still exists in the resolved package.
- **JDK 17 briefly looked like it had disappeared from the machine** — `/usr/libexec/java_home -V`
  only listed JDK 11, and the JDK 17 used throughout Phase 1/2 wasn't there. It hadn't been
  uninstalled: it's managed by `mise` (`~/.local/share/mise/installs/java/temurin-17.0.19+10`), a
  location `java_home` doesn't scan. See `AGENTS.md`'s JDK 17 section for the fix (`mise list
  java` before assuming a JDK needs reinstalling).

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
- [x] Update `TODO.md` (remove the "upgrade Flutter" item) — done alongside the 3.44.6 Phase 2
      stop's Codex review fixes. `AGENTS.md`'s toolchain section turned out not to need any
      version-specific updates (it's written generically, no hardcoded Flutter/AGP/Gradle/Kotlin
      version numbers) — it did have one stale `build_runner --delete-conflicting-outputs`
      reference, fixed while doing this end-of-Phase-2 docs pass.

## Phase 5 — optional / later

- [x] `compileSdkVersion` — already at 36, forced early during the Phase 2 3.35.7 stop (AndroidX
      Core cascade, see that stop's landmines). Nothing left to do here.
- [ ] `targetSdkVersion` 34 → 35+ (Android 15), only if there's an actual reason to — 34 already
      matches the real Streamer's current shipping OS (see AGENTS.md), so this isn't urgent.
      `compileSdk` being ahead of `targetSdk` is normal and doesn't change runtime behavior.

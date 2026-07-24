# TODO

## Known issue: Back button leaves FLauncher when opened via the Home-button override

Since the Home-button-override introduced in `HomeButtonAccessibilityService.kt`, FLauncher is
launched as a regular Activity on top of the existing task stack rather than being registered as
the actual system default launcher (that's the whole point — it avoids disabling the stock
launcher, which keeps things like the remote's YouTube button working, see README).

Consequence: while sitting at FLauncher's home screen, pressing the remote's Back button pops
FLauncher off the stack and reveals whatever was underneath — the stock launcher — instead of
staying put, which is what a "real" default launcher does (Back does nothing on an actual home
screen).

This happens because `AppsService.isDefaultLauncher()` (via `MainActivity.isDefaultLauncher()`)
checks the system's actual resolved default HOME activity, which is genuinely not FLauncher in
this setup, so `shouldPopScope()` in `flauncher_app.dart` always allows the pop.

**Decided (2026-07-20): not fixing this in-app.** The advised path for anyone who cares about
correct Back-button behavior is to actually set PitchforkLauncher as the real default launcher
(`adb shell cmd package set-home-activity`, or README's "Option A: make it the real default
launcher") rather than relying on the Home-button-override for that specific case —
`isDefaultLauncher()` then genuinely returns `true` and `shouldPopScope()` behaves correctly with
no code changes needed. This project
isn't published on the Play Store; anyone sideloading it who hits this and doesn't set themselves
up as real default launcher is an accepted edge case, not worth building around.

## Other open items

~~The YouTube-button keycode in `HomeButtonAccessibilityService.kt` (190 / `KEYCODE_BUTTON_3`) was
  identified empirically on one specific Google TV Streamer 4K remote. Other Google TV
  devices/remotes may send a different code for that button, in which case it won't do anything
  until re-identified.~~ — non-issue: it's just the default/example mapping, seeded once; any user
  can remap it themselves in Settings → Remote buttons regardless of what code their own remote's
  button actually sends.

~~Test the Home-button-override approach on the real Google TV Streamer 4K, not just the
`GoogleTV_API31` emulator~~ — done: confirmed working on real hardware, including the YouTube
button override.

~~Revisit the dormant Unsplash wallpaper source~~ (`unsplashEnabled` hardcoded `false` in
  `lib/providers/settings_service.dart`, see `DRIFT.md`) — **superseded 2026-07-24: not revisiting,
  removing it instead.** Was already on hold since 2026-07-22 (Picsum's live preview covers the
  need well enough that a user-supplied-API-key flow wasn't worth the friction); with `ADR_001_Project_Scope_and_Feature_Governance.md`
  ADR-001's governance gate now in effect, re-enabling it doesn't clear question 1 (no personal
  irritation it solves) either, so this isn't "on hold pending reassessment" anymore, it's just
  dead code sitting in the base with no path to being turned on.

~~Remove the dormant Unsplash wallpaper source entirely.~~ — done (2026-07-24): the
  `unsplash_client` and `webview_flutter` (only used for the Unsplash author-credit link)
  pubspec dependencies, `lib/unsplash_service.dart`, `UnsplashService`'s registration in
  `flauncher_app.dart`/`main.dart`, `WallpaperService.randomFromUnsplash`/`setFromUnsplash`/
  `searchFromUnsplash`, the `unsplashEnabled`/`unsplashAuthor` settings fields,
  `lib/widgets/settings/unsplash_panel_page.dart` and its route, the wallpaper picker's "Unsplash"
  menu entry and author-credit display in `wallpaper_panel_page.dart`, the ten
  category/random-photo asset images plus `assets/unsplash.png`, and the corresponding tests. The
  bundled default wallpaper's Unsplash-License photo credit (About dialog, license registry) is
  unrelated to this SDK integration and was kept as-is.

~~Focus jumps to "Add Category" after reordering with exactly 2 categories
  (`lib/widgets/settings/categories_panel_page.dart`)~~ — fixed: each up/down arrow `IconButton`
  now gets an explicit, per-category `FocusNode`, and after `_move()` the row's remaining enabled
  arrow is refocused via `addPostFrameCallback` instead of leaving it to Flutter's default
  disabled-widget fallback. Covered by a regression test in `categories_panel_page_test.dart`.

~~Focus-snap on the categories reorder fix feels a bit abrupt~~ — softened (2026-07-22): the
one-frame hop itself can't be eliminated (Flutter defers focus updates by a frame by design,
confirmed via its docs, regardless of mechanism), so the arrows now fade their own focus highlight
in/out (120ms) instead of Flutter's instant default, in `categories_panel_page.dart`.

~~No confirmation dialog before deleting a category~~ — fixed (PR #16, 2026-07-22):
`CategoryPanelPage`'s "Delete" button now shows an `AlertDialog` ("Delete category?" / Cancel /
Delete) before calling `deleteCategory`, with focus defaulting to Cancel rather than Delete.

~~Migrate off `sqlite3_flutter_libs` to `sqlite3` v3.x~~ — done (PR #11, 2026-07-21): dropped
  `sqlite3_flutter_libs` from `pubspec.yaml` entirely, depend on `sqlite3` v3.x directly. See
  `DRIFT.md`.

~~Migrate off the Kotlin Gradle Plugin (KGP) applied by `image_picker_android`/
  `shared_preferences_android`~~ — resolved (2026-07-24): both plugins already shipped their
  Built-in Kotlin migration upstream on 2026-06-02, but plain `flutter pub get` never picks up a
  newer transitive dependency once it's already in `pubspec.lock` (that needs an explicit
  `pub upgrade`), and Renovate has no `lockFileMaintenance` rule to force that either — so the fix
  sat unused for weeks despite being available. Bumped via
  `flutter pub upgrade image_picker_android shared_preferences_android`
  (`0.8.13+17` -> `0.8.13+19`, `2.4.23` -> `2.4.27`); the "uses the following plugins that apply
  KGP" half of the warning is gone.

- **Migrate this app's own `android/app/build.gradle` to Built-in Kotlin.** Follows directly from
  the above: with both plugins fixed, the *only* remaining KGP warning is our own module still
  applying `id "org.jetbrains.kotlin.android"` directly. Tried the obvious toggle (drop that plugin
  line, flip `android.builtInKotlin=true` in `gradle.properties`) and it's not that simple: KGP then
  needs declaring in `settings.gradle`'s plugins block instead, and the old `kotlinOptions { }` DSL
  in `build.gradle` needs replacing with Built-in Kotlin's newer compiler-options API — a small,
  self-contained migration, just not a one-line change. See
  https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers.
  Not started.

~~Concept: live full-screen preview for the Picsum wallpaper picker~~ — done (2026-07-21):
`WallpaperPanelPage`'s "Random photo" now closes the Settings panel and pushes
`WallpaperControlBar`, a bottom bar with Random/Black & White/Blur controls, live over the actual
home screen (`PageRouteBuilder(opaque: false)`). Subsumes the earlier "Add a grayscale option"
item. See `DRIFT.md` if a short writeup gets added there; implementation is
`lib/widgets/wallpaper_control_bar.dart` + `lib/picsum_service.dart`'s id-capturing rewrite.

~~B&W/Blur toggles were interactive even when there's no current Picsum photo to apply them to~~
— fixed (2026-07-21): `WallpaperService.hasCurrentPicsumPhoto` exposes whether a photo is
currently set, and `WallpaperControlBar` disables (grays out) both switches until it's true.
`_currentPicsumPhotoId` is also now cleared whenever the wallpaper source changes away from Picsum
(`pickWallpaper`, `setGradient`, `randomFromUnsplash`, `setFromUnsplash`).

~~No transition when the photo changes under a filter toggle~~ — fixed (2026-07-21):
`WallpaperService.wallpaperVersion` bumps on every wallpaper/gradient change, keying an
`AnimatedSwitcher` around the background in `FLauncher` so it cross-fades (200ms) between the old
and new wallpaper. Applies to every wallpaper source, not just Picsum toggles.

~~The cross-fade visibly dips in brightness partway through~~ — fixed (2026-07-22), confirmed gone
on real hardware: was a genuine artifact of the naive two-layer alpha crossfade (old 100%→0%, new
0%→100% simultaneously means both are ~50% opaque at the midpoint, letting the dark canvas
underneath bleed through). Fixed by confining `switchInCurve`/`switchOutCurve` to
`Interval(0.0, 0.5, ...)` each on `FLauncher`'s `AnimatedSwitcher` — since the outgoing entry's
controller runs in reverse, this makes the incoming photo reach full opacity by the midpoint and
the outgoing one only start fading (invisibly, now hidden under the opaque new layer) after that,
so at least one layer is always fully opaque and the background never shows through.

~~Seed a richer, sane default test setup instead of the bare upstream one.~~ — shipped
  (2026-07-22), wider in scope than originally captured: rather than a debug-only convenience,
  `AppsService._initDefaultCategories()` now sorts well-known apps into topical categories
  (`lib/default_app_categories.dart`'s hardcoded package-name map) on any genuine fresh
  install/data wipe, falling back to the original TV/Non-TV split for anything unmatched, and
  `WallpaperService` seeds a bundled default wallpaper (`assets/default_wallpaper.jpg`) instead of
  the plain gradient. Always-on production behavior, not gated behind debug mode — both paths key
  off the same fresh-install signal, so an ordinary app update/reinstall never re-triggers them.
  See `DRIFT.md`.

~~Concept: universal wallpaper filters (B&W, Blur, Contrast) for any wallpaper source, not just
  Picsum.~~ — **rejected per `ADR_001_Project_Scope_and_Feature_Governance.md` ADR-001** (2026-07-24): named explicitly in that ADR's
  "Negative / Accepted Trade-offs" as the kind of technically-elegant-but-scope-expanding feature
  the new governance gate exists to reject (turns "pick a wallpaper" into "edit a wallpaper"; the
  disqualifier about per-frame GPU cost for a never-changing background also applies directly, even
  with the "bake once" mitigation discussed below). Kept here for the technical writeup, not as an
  open item. Raised in conversation 2026-07-23. Right now
  B&W/Blur only exist inside the Picsum "Random photo" flow (`WallpaperControlBar`), calling
  `WallpaperService.reapplyPicsumFilters`, which re-fetches the photo from Picsum's server with
  `?grayscale`/`?blur=N` query params — Custom and Unsplash wallpapers have no filter step at all.
  Idea: add a "Filter" entry to the Wallpaper settings menu that loads a
  `WallpaperFilterControlBar` (same live-over-the-home-screen pattern as the existing control bar)
  and applies to whatever the *current* wallpaper is, regardless of which source set it. Adds
  Contrast alongside B&W/Blur.
  - Decouples "pick a wallpaper" from "adjust its filters" — filters become a property of the
    current wallpaper, not a step bolted onto one specific source's picker.
  - Technique: render client-side instead of round-tripping to a server, so it works for any
    source. `ColorFilter.matrix()` can combine grayscale + contrast (and brightness) in a single
    4x5 matrix multiply per pixel; `ImageFilter.blur(sigmaX:, sigmaY:)` handles blur — this app
    already uses the latter elsewhere (`lib/flauncher.dart`'s settings-icon shadow). Applying
    either live every frame via `ImageFiltered` would mean an ongoing per-frame GPU cost for a
    background that never changes, which is wasteful on a TV box's modest SoC — better to bake the
    result once: draw the base image through a `Paint` with `imageFilter`/`colorFilter` set onto a
    `ui.PictureRecorder`/`Canvas`, rasterize via `picture.toImage()`, then `toByteData(format:
    ui.ImageByteFormat.png)` and write those bytes to `_wallpaperFile` exactly like today — same
    one-time-cost, flat-file-on-disk shape the app already has, just computed locally instead of
    fetched from Picsum. Would need to keep the base (unfiltered) photo around separately from the
    baked result so filters can be changed/reset without re-fetching/re-picking.
  - Not a bug or regression, current approach works fine for Picsum; this is a scope expansion, not
    a fix.

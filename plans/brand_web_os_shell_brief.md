# Kohera Web / OS Brand Shell Brief

Task: fix stale web/OS brand shell (branding leverage #3).
Status: design brief. No code changes.

## Decisions (locked) — REVISED: SNES as system default

1. Default theme: **`ThemeMode.system` preserved** (follows OS light/dark) + **null-preset fallback = SNES spec (revised, path A).** No preset is written on first launch; instead `KoheraTheme.light/dark` resolve the null-preset path to the SNES preset's `ColorScheme` + `KoheraPalette`. SNES has no `forcedMode` → OS light/dark drives surface (**grey light / dusk dark** — aged-yellow demoted to accent container per path A, since aged-yellow collided with Paper/PICO-8 creams). Existing users on null preset get SNES automatically (null was never an explicit choice — no surprise). Users who picked a preset keep theirs.
2. Brand color: **SNES signature = Phantom Purple `#9b5de5`.** `_fallbackSeed` `#1976D2` → `#9b5de5` (defensive — only used if SNES preset missing + no dynamic; the real fallback now references the snes preset, not fromSeed). Shell mirrors this.
3. Dynamic sync: **static fallback + runtime sync.** Static brand purple at first paint; `AnnotatedRegion<SystemUiOverlayStyle>` (mobile) + web JS channel update OS chrome when in-app theme changes.
4. Web loader: **keep mycelium SVG, recolor theme-reactive.** Static brand purple at first paint; JS syncs to active `colorScheme.primary` after boot.
5. Splash: **brand-palette bg + centered mark.** Light = grey `#e5e5e5` bg + dusk `#2c3e50` mark; Dark = dusk `#2c3e50` bg + aged-yellow `#fcf4d9` mark (aged-yellow confirmed as dark-mode mark color — accent on dark bg, not a surface, no Paper/PICO-8 collision). (Mark never purple-on-purple.)
6. Brand constants: **codegen from Dart const.** `lib/core/brand/brand_constants.dart` is source of truth; native shell strings audited/generated from it.

## Prerequisite

**SNES theme must be implemented first** — issue #764 (open), full spec at `docs/theme-specs/snes-theme-spec.md`. `KoheraPalette.snes` + `ThemePreset(id:'snes')` do not yet exist in code. Tracked as task #6. The null-preset fallback in `KoheraTheme` references the snes preset, so #6 must land before this rebrand ships. Sequence: #6 → #3 shell rebrand. Interim: current Flutter-blue null fallback stays.

## 1. Why SNES as system default

User pivot to SNES as brand identity. SNES is the **soft-beveled pixel theme** — grey canvas, dusk ink, phantom-purple primary, 9-color accent ramp, translucent beveled shadows. Path A revises the spec so grey (snes.css's actual default `body,html{background-color:#e5e5e5}`) is the primary light surface, demoting aged-yellow to an accent container to avoid colliding with Paper/PICO-8 creams. Baking SNES into the null-preset fallback means the system theme *is* SNES — no migration, no first-launch write, no surprise for existing null-preset users. SNES remains independently selectable in the picker.

Mechanism in `KoheraTheme.light/dark` (both):
```
// before
final colorScheme = preset?.light() ?? dynamic ?? ColorScheme.fromSeed(seedColor: _fallbackSeed);
final resolvedPalette = palette ?? preset?.pixel(b) ?? KoheraPalette.fromColorScheme(cs, b);

// after
final snes = getPreset('snes')!;
final colorScheme = preset?.light() ?? dynamic ?? snes.light();   // dark: snes.dark()
final resolvedPalette = palette ?? preset?.pixel(b) ?? snes.pixel(b);
```
`_fallbackSeed` kept as defensive last-resort only (used if snes preset absent at runtime — shouldn't happen, but safe). `dynamic` (Material You) still wins where available, overriding SNES — accepted.

Ripple on #1/#2 briefs: **none.** Wordmark "K" + outer threads use `accentRamp[0]` (theme-agnostic). SNES ramp[0] = Plumber Red `#f22561` → K + outer threads render red on SNES. Shell uses `seedColor`/`primary` (phantom purple), not ramp[0] — same two-color pattern (shell=seed, K/threads=ramp[0]). Coherent.

## 2. Audit findings (current state)

| Location | Current | Status |
|---|---|---|
| `web/index.html` `<title>` | `kohera` | stale |
| `web/index.html` description meta | `A new Flutter project.` | stale |
| `web/index.html` apple-mobile-web-app-title | `kohera` | stale |
| `web/index.html` body bg | `#FEF7FF` / `#1C1B1F` (Flutter purple) | Flutter default |
| `web/index.html` loader color | `#1976D2` / `#90CAF9` (Flutter blue) | Flutter default |
| `web/index.html` loader SVG shape | mycelium bloom + 5 root threads + nodes | ✓ on-brand, keep |
| `web/index.html` theme-color meta | absent | missing |
| `web/index.html` apple status bar style | `black` | generic |
| `web/manifest.json` background_color | `#1976D2` | stale |
| `web/manifest.json` theme_color | `#1976D2` | stale |
| `web/manifest.json` description | generic OK | improve w/ #5 |
| `web/manifest.json` icons | Flutter default PNGs | task #4 |
| `android` label | `Kohera` | ✓ |
| `android` launch_background.xml | white, no mark | no brand splash |
| `android` styles | system themes, no brand tint | stale |
| `ios` CFBundleDisplayName | `Kohera` | ✓ |
| `ios` CFBundleName | `kohera` | stale (internal) |
| `ios` LaunchScreen.storyboard | systemBackgroundColor + Flutter LaunchImage | no brand |
| `ios` UIStatusBarStyle | unset | generic |
| `macos` CFBundleName | `$(PRODUCT_NAME)` | verify Xcode |
| `linux` gtk_window_set_title | `Kohera` | ✓ |
| `windows` window.Create | `L"kohera"` | stale casing |
| `windows` Runner.rc FileDescription/InternalName/ProductName | `kohera` | stale casing |
| `windows` AppUserModelID | `io.github.quantumheart.kohera` | ✓ (reverse-DNS, keep) |
| `lib/main.dart` MaterialApp.title | `'Kohera'` | ✓ |
| `lib/core/theme/kohera_theme.dart` `_fallbackSeed` | `#1976D2` Flutter blue | **root cause** |

## 3. Brand color

`_fallbackSeed`: `Color(0xFF1976D2)` → `Color(0xFF9b5de5)` (SNES Phantom Purple, the snes preset's `seedColor` + `primary`).

- Works on light + dark surfaces (verify contrast: purple on grey `#e5e5e5` = ~3.6:1 (AA-graphical pass), on dusk `#2c3e50` = ~4.8:1 — pass).
- Distinct from Flutter blue + Android system blue → recognizable.
- Matches SNES preset seedColor → continuity w/ the new brand-default theme.
- Alternatives if purple rejected: ocean blue `#4eb6d9` (SNES secondary), or revert to PICO-8 green `#008751`.

Shell static values:
- `theme_color` = `#9b5de5` (phantom purple)
- `background_color` = `#2c3e50` (SNES dusk, dark-first) — or `#e5e5e5` (grey, light-first). Pick dusk to match dark splash.

## 4. Splash color reconciliation

Decision 5 = "brand-palette bg + centered mark." Mark color must contrast bg. Light uses SNES light `onSurface` (dusk); dark uses aged-yellow (warm SNES accent, kept for dark mode since it's a small mark on dark bg, not a surface):
- Light: grey bg `#e5e5e5` + mark dusk `#2c3e50` (SNES light `onSurface`). High contrast, on-palette, faithful to snes.css default canvas.
- Dark: dusk bg `#2c3e50` + mark aged-yellow `#fcf4d9` (SNES dark `onSurface`). High contrast. Aged-yellow confirmed as dark mark color — accent use on dark bg, no Paper/PICO-8 surface collision.

Resolved spec:
- **Light splash:** grey bg `#e5e5e5` + mark dusk `#2c3e50`.
- **Dark splash:** dusk bg `#2c3e50` + mark aged-yellow `#fcf4d9`.
- Mark rendered w/ explicit color override (not `onSurface`) so splash is deterministic regardless of in-app theme state at launch.

Web loader bg mirrors: body bg grey/dusk per `prefers-color-scheme`, loader stroke phantom purple `#9b5de5`.

## 5. Per-location fixes

### 5.1 `lib/core/theme/kohera_theme.dart`
- Null-preset fallback: `ColorScheme.fromSeed(seedColor: _fallbackSeed)` → `getPreset('snes')!.light()` / `.dark()`; palette fallback → `snes.pixel(b)` (both in `light()` + `dark()` + `_build`). See §1 mechanism.
- `_fallbackSeed`: `#1976D2` → `#9b5de5` (defensive last-resort only).
- No change to `PreferencesService` — null preset stays null; no first-launch write, no migration.

### 5.2 `lib/core/brand/brand_constants.dart` (new — source of truth)
```
class BrandConstants {
  static const appName = 'Kohera';
  static const tagline = '<from #5>';
  static const description = '<from #5>';
  static const brandColor = Color(0xFF9b5de5);   // SNES Phantom Purple
  static const lightSurface = Color(0xFFe5e5e5);  // SNES grey (snes.css default canvas)
  static const darkSurface  = Color(0xFF2c3e50);  // SNES dusk
  static const markOnLight  = Color(0xFF2c3e50);  // dusk on grey
  static const markOnDark   = Color(0xFFfcf4d9);  // aged-yellow on dusk (confirmed accent)
  static const appUserModelId = 'io.github.quantumheart.kohera';
}
```
Existing `NotificationChannel.appName = 'Kohera'` → reference `BrandConstants.appName`. `main.dart` `MaterialApp.title` → `BrandConstants.appName`.

### 5.3 Codegen target: `scripts/generate_brand_shells.dart` (new)
Reads `BrandConstants` + tagline/description from #5, writes:
- `web/manifest.json` name/short_name/description/theme_color/background_color
- `web/index.html` title/description/apple-title (via placeholder substitution)
- `windows/runner/main.cpp` window title, `Runner.rc` string table
- `ios/Runner/Info.plist` CFBundleName/CFBundleDisplayName
- `macos/Runner/Info.plist` CFBundleName (or Xcode `PRODUCT_NAME`)
- `android/app/src/main/AndroidManifest.xml` label (already correct, keep)
- `linux/runner/my_application.cc` title (already correct, keep)
Run in CI / pre-commit to prevent drift. Native files use `@@BRAND_*@@` placeholders.

### 5.4 `web/index.html`
- `<title>Kohera — <tagline></title>`
- `<meta name="description" content="<description>">`
- `<meta name="apple-mobile-web-app-title" content="Kohera">`
- `<meta name="theme-color" content="#9b5de5" media="(prefers-color-scheme: light)">`
- `<meta name="theme-color" content="#9b5de5" media="(prefers-color-scheme: dark)">` (same phantom purple both modes)
- `<meta name="apple-mobile-web-app-status-bar-style" content="default">` (let Flutter override via AnnotatedRegion; `black` forces transluent)
- body bg: `#e5e5e5` light (SNES grey) / `#2c3e50` dark (SNES dusk) (replace `#FEF7FF`/`#1C1B1F`)
- `.loader` color: `#9b5de5` (phantom purple both modes; drop the `#90CAF9` dark override)
- keep mycelium SVG shape + animations
- add JS bridge: `window.kohera = { setShellTheme({bg, accent}) }` — updates body bg, `.loader` color, both theme-color metas. Called from Dart via `dart:js_interop` when in-app theme changes (web only, gated by `kIsWeb`).

### 5.5 `web/manifest.json`
- `theme_color` → `#9b5de5` (phantom purple)
- `background_color` → `#2c3e50` (SNES dusk, dark-first; PWA install splash). Or `#e5e5e5` (grey) if light-first preferred. Pick dusk to match dark splash.
- `description` → from #5
- icons → task #4

### 5.6 Android
- `launch_background.xml`: replace `@android:color/white` w/ brand drawable — grey (`#e5e5e5`) for light, dusk (`#2c3e50`) for night, + centered mark bitmap (from #4; mark color dusk on light, aged-yellow on dark). Two variants: `drawable/launch_background.xml` (light) + `drawable-night/launch_background.xml` (dark).
- `styles.xml` / `values-night/styles.xml`: `windowBackground` → `@drawable/launch_background`. Keep `NormalTheme` system-derived (Flutter handles in-app chrome).
- status/nav bar tint: **in-app `AnnotatedRegion<SystemUiOverlayStyle>`** at root (see §6), not shell files. Per active `KoheraPalette` + brightness.
- optional: `colorPrimary`/`colorPrimaryDark` in styles → brand purple, for task-bar recents color. Low priority.

### 5.7 iOS
- `Info.plist` `CFBundleName` → `Kohera` (currently `kohera`).
- `Info.plist` add `UIStatusBarStyle` → `UIStatusBarStyleDefault` (let AnnotatedRegion drive it). Or leave unset (default) — AnnotatedRegion still wins.
- `LaunchScreen.storyboard`: backgroundColor → brand (grey light / dusk dark via userDefinedColor or named color asset), LaunchImage → mark asset from #4 (mark color: dusk on light, aged-yellow on dark). Replace `systemBackgroundColor`.
- status bar: in-app `AnnotatedRegion` (§6).

### 5.8 macOS
- verify `PRODUCT_NAME` = `Kohera` in `macos/Runner.xcodeproj` project settings. If `kohera`, fix to `Kohera` so `CFBundleName = $(PRODUCT_NAME)` resolves correctly. Window title (Flutter sets via `MaterialApp.title` = `Kohera` ✓) — no MainFlutterWindow.swift change needed.
- window appearance tint: macOS auto-handles via Material; no DWM equivalent needed. Optional: `NSWindow` titlebar style — out of scope.

### 5.9 Windows
- `main.cpp` `window.Create(L"kohera", ...)` → `L"Kohera"`.
- `Runner.rc` `FileDescription`/`InternalName`/`ProductName` → `Kohera`. `OriginalFilename` → keep `kohera.exe` (exe filename is a separate concern; lowercase exe names are conventional). Or `Kohera.exe` if we rename the exe — defer.
- title bar caption tint (Windows 10+ DWM `DwmSetWindowAttribute(DWMWA_CAPTION_COLOR)`): optional, low priority. Brand green titlebar = strong but invasive. Defer unless wanted.

### 5.10 Linux
- already `Kohera` ✓. No change. Verify CMakeLists `APPLICATION_NAME`/window title match (grep showed `gtk_window_set_title(window, "Kohera")` ✓).

## 6. Cross-platform in-app OS chrome (AnnotatedRegion)

New root widget, wraps `MaterialApp.router` child tree:
```
AnnotatedRegion<SystemUiOverlayStyle>(
  value: _resolveOverlayStyle(context),  // from active palette + brightness
  child: ...
)
```
`_resolveOverlayStyle`:
- Reads `KoheraPalette.of(context)` + `Theme.of(context).colorScheme` + effective brightness.
- status bar icons: light icons on dark surface, dark icons on light surface (based on `surface` luminance).
- nav bar color: `surface` w/ matching icon brightness.
- On web/desktop: `AnnotatedRegion` no-ops (SystemUiOverlayStyle ignored) — harmless.

Updates automatically on theme change (ChangeNotifier rebuild). Single mechanism for iOS + Android.

Also: gate web JS bridge — `if (kIsWeb) _callJsSetShellTheme(bg, accent)` from the same theme-change listener. Updates web `theme-color` meta + body bg + loader color to active preset's `surface` + `colorScheme.primary`. Static fallback (brand purple `#9b5de5`) covers first paint before Flutter boots.

## 7. Files touched (impl deferred)

| File | Change |
|---|---|
| `lib/core/theme/kohera_theme.dart` | null-preset fallback → snes preset scheme + palette; `_fallbackSeed` → `#9b5de5` (defensive) |
| `lib/core/theme/kohera_palette.dart` | add `KoheraPalette.snes` (task #6 / issue #764) |
| `lib/core/theme/theme_presets.dart` | add `ThemePreset(id:'snes')` (task #6 / issue #764) |
| `lib/core/brand/brand_constants.dart` | new — source of truth |
| `lib/features/notifications/models/notification_constants.dart` | `appName` → ref `BrandConstants.appName` |
| `lib/main.dart` | `MaterialApp.title` → `BrandConstants.appName`; wrap root in `AnnotatedRegion` + theme-change JS bridge |
| `web/index.html` | title/description/apple-title/theme-color/body-bg/loader-color; add JS bridge stub |
| `web/manifest.json` | theme_color/background_color/description (codegen) |
| `android/app/src/main/res/drawable/launch_background.xml` + `drawable-night/` | brand splash w/ mark bitmap (mark asset from #4) |
| `android/app/src/main/res/values(-night)/styles.xml` | windowBackground → launch_background |
| `ios/Runner/Info.plist` | CFBundleName → Kohera; UIStatusBarStyle |
| `ios/Runner/Base.lproj/LaunchScreen.storyboard` | brand bg + mark image (from #4) |
| `macos/Runner.xcodeproj` | PRODUCT_NAME → Kohera (if needed) |
| `windows/runner/main.cpp` | window title casing |
| `windows/runner/Runner.rc` | string table casing |
| `scripts/generate_brand_shells.dart` | new codegen script |
| `pubspec.yaml` / CI | run codegen pre-build |

## 8. Deliverables (this task)

1. This brief.
2. Brand constants spec (§5.2) — exact values.
3. Codegen script design (§5.3) — placeholder scheme, target files, run trigger.
4. Per-location fix list (§5.4–5.10).
5. AnnotatedRegion + web JS bridge spec (§6).
6. Splash color reconciliation (§4) — confirm interpretation.
7. Contrast verification for brand purple on grey/dusk + mark dusk/aged-yellow.

## 9. Open / deferred

- Tagline + description copy → #5 (blocks codegen final values).
- App icons + splash mark bitmaps → #4 (blocks splash asset creation).
- `OriginalFilename` exe casing — defer.
- Windows titlebar DWM tint — defer.
- macOS titlebar styling — defer.
- Verify `lightDynamic`/`darkDynamic` behavior: on Material You platforms the fallback seed is overridden — confirm green still shows in shell (shell can't see dynamic color; static green stays). Accepted.
- Confirm `_fallbackSeed` change doesn't break existing golden tests (PICO-8/Paper/etc. presets unaffected — they pass explicit `preset`; only null-preset default changes). Re-run goldens.
# Kohera Tagline + README Hero Brief

Task: pick tagline + ship logo/tagline in README hero and auth (branding leverage #5).
Status: design brief. No code changes.

## Decisions (locked)

1. Primary tagline: **"Threads that hang together."**
2. Short title form (browser tab / window / PWA): **"Kohera" alone** — tagline lives in README/manifest/auth, not the tab.
3. Description: **candidate A (retro-pixel lead)** — see §3.
4. Auth: **tagline + keep per-screen contextual subtitle** — tagline = identity (top of lockup), per-screen subtitle = action (below).
5. Settings About: **add "why Kohera" blurb** explaining the coherent-threads / mycelial-network mark metaphor.
6. README hero screenshots: **file a separate GitHub issue** for the screenshot asset work (deferred from this brief). See task/issue cross-ref.

## 1. Tagline

**"Threads that hang together."**

Grounded in the mark metaphor (`kohera_loader.dart`: "mycelial mark... the hidden web through which fungi communicate, echoing a decentralized chat network"; `generate_icons.py`: "pixel-art mushroom above a mycelial root network"). Name "Kohera" ≈ coherent + threads. Tagline ties mark (threads) + name (coherent = hang together) + warmth.

- 29 chars. Fits auth header, manifest, README, store listing.
- Works at all sizes (PressStart2P optional; plain text in browser/store contexts).
- Reads as identity, not feature list.

## 2. Title form (browser tab, window, PWA)

- Web `<title>`: `Kohera` (tagline omitted — tabs truncate; tagline lives in README/manifest).
- macOS/linux/windows window title: `Kohera` (already set via `MaterialApp.title`).
- PWA `short_name` / `name`: `Kohera` (manifest unchanged).
- Tab does NOT carry the tagline — clean, brand-name-only.

## 3. Description (manifest, store, README subhead)

**Candidate A (retro-pixel lead) — locked:**

> Kohera is a retro-pixel Matrix chat client — coherent threads for encrypted messaging, voice/video calls, and spaces. Built with Flutter, runs on desktop, mobile, and web.

Identity-first ("retro-pixel... coherent threads"), feature-second. Replaces:
- README H1 subtitle (feature-list version)
- Web manifest `description` (generic "modern Matrix chat client")
- Web index.html description (stale "A new Flutter project." — also #3)
- Store listings (if any)

## 4. Centralized brand constants (source of truth)

`lib/core/brand/brand_constants.dart` (also referenced by #3):

```
class BrandConstants {
  static const appName = 'Kohera';
  static const tagline = 'Threads that hang together.';
  static const description =
      'Kohera is a retro-pixel Matrix chat client — coherent threads for '
      'encrypted messaging, voice/video calls, and spaces. Built with Flutter, '
      'runs on desktop, mobile, and web.';
  static const brandColor = Color(0xFF9b5de5);   // SNES phantom purple (#3)
  static const appUserModelId = 'io.github.quantumheart.kohera';
}
```

Consumers:
- `NotificationChannel.appName` → `BrandConstants.appName` (currently hardcoded `'Kohera'`).
- `MaterialApp.title` → `BrandConstants.appName` (currently hardcoded `'Kohera'`).
- Web manifest / index.html / Info.plist / Runner.rc → codegen from `BrandConstants` (#3's `scripts/generate_brand_shells.dart`).
- README / store copy → manual sync to `BrandConstants.description` (docs, not code).

## 5. Per-location copy

### 5.1 README hero

```
# Kohera

**Threads that hang together.**

Kohera is a retro-pixel Matrix chat client — coherent threads for encrypted
messaging, voice/video calls, and spaces. Built with Flutter, runs on desktop,
mobile, and web.

[stacked lockup image: assets/icons/kohera_lockup_stacked.svg rendered, or PNG]

[3 theme screenshots — deferred to separate issue]
```

Replaces current generic H1 subtitle. Lockup asset from #1 (`kohera_lockup_stacked.svg`). Screenshots from the filed issue (§6).

### 5.2 Web `<title>` + manifest

- `<title>Kohera</title>` (was `kohera` lowercase).
- `apple-mobile-web-app-title`: `Kohera` (was `kohera`).
- manifest `name`/`short_name`: `Kohera` (unchanged).
- manifest `description`: the §3 description (codegen).
- index.html `description` meta: the §3 description (codegen, overlaps #3).

### 5.3 Auth header (stacked lockup)

Per #1 brief, auth header = stacked lockup (mark top, wordmark bottom). Tagline added under the wordmark:

```
   [mark]
  Kohera
Threads that hang together.
```

- Tagline style: `DepartureMono` (mono, lighter than PressStart2P wordmark), `colorScheme.onSurfaceVariant`, size ≈ 0.4× wordmark size.
- Per-screen contextual subtitle stays **below** the lockup, unchanged:
  - homeserver screen: "Connect to the Matrix network"
  - registration screen: "Create an account on the Matrix network"
- `AppLogoHeader` widget gains a `tagline` slot (or hardcodes `BrandConstants.tagline`); the existing `subtitle` param keeps the per-screen action text.

Vertical order in `AppLogoHeader`:
1. mark (stacked lockup top)
2. wordmark (pixeled K + PressStart2P "ohera", per #1)
3. tagline (DepartureMono, "Threads that hang together.")
4. spacing
5. subtitle (per-screen action, current param)

### 5.4 Settings About — "why Kohera" blurb

Add a blurb below the existing `Kohera` + version tile (in the About card), explaining the mark metaphor + identity:

> Kohera is a retro-pixel Matrix client. The mark — a pixel mushroom above a mycelial root network — stands for the coherent threads of a decentralized chat network: the visible conversation and the hidden web that carries it.

Style: `bodySmall` / `onSurfaceVariant`, 2-3 lines. Placed as a non-interactive info tile (or a `Padding` block) above the Source code tile.

### 5.5 Notifications

- Notification channel `appName` → `BrandConstants.appName` (currently `NotificationChannel.appName = 'Kohera'`). No tagline in notifications (too long).

## 6. README hero screenshots — separate issue

File a GitHub issue (feature_request template) for the screenshot asset work:
- Capture 3 themed screenshots (SNES, PICO-8, Paper or Mocha) at desktop width showing the 3-column adaptive layout.
- Standardize size/cropping for README hero strip.
- Place under `docs/screenshots/` or `assets/readme/`.
- Embed in README hero (§5.1) once available.

Tracked separately — does not block this brief's copy work. Copy/lockup land first; screenshots follow.

## 7. Files touched (impl deferred)

| File | Change |
|---|---|
| `lib/core/brand/brand_constants.dart` | new — appName, tagline, description, brandColor, appUserModelId |
| `lib/features/notifications/models/notification_constants.dart` | `appName` → ref `BrandConstants.appName` |
| `lib/main.dart` | `MaterialApp.title` → `BrandConstants.appName` |
| `lib/features/auth/widgets/app_logo_header.dart` | add tagline slot under wordmark (per #1 stacked lockup) |
| `lib/features/settings/screens/settings_screen.dart` | add "why Kohera" blurb in About card |
| `README.md` | hero: tagline + description + lockup placeholder; screenshots pending issue |
| `web/index.html` | `<title>`, description, apple-title (codegen, overlaps #3) |
| `web/manifest.json` | description (codegen, overlaps #3) |
| `scripts/generate_brand_shells.dart` | codegen reads `BrandConstants` (#3) |

## 8. Deliverables (this task)

1. This brief.
2. Tagline locked: "Threads that hang together."
3. Description locked (§3 candidate A).
4. Copy placement spec (§5).
5. BrandConstants spec (§4).
6. GitHub issue filed for README hero screenshots (§6).

## 9. Open / deferred

- README hero screenshots → separate issue (filed).
- Lockup SVG assets → #1 (`kohera_lockup_stacked.svg`).
- Codegen script → #3 (`scripts/generate_brand_shells.dart`).
- Store listing copy (Flathub, etc.) → defer; reuse `BrandConstants.description`.
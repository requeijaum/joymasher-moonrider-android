# Moonrider Android

<p align="center">
  <img src="docs/icon.png" alt="Moonrider Android app icon" width="128" height="128">
  <br>
  <em>All rights reserved to JoyMasher, The Arcade Crew and Asteristic Game Studio.</em>
</p>

Android port of **Vengeful Guardian: Moonrider** (a Construct 2 / HTML5 game) as
a universal APK running in a native WebView. It wraps the same Construct 2 app
used in the muOS/PortMaster port (`../portsmaster_on_rg40xxh/`), but on Android
**all of the muOS workaround infrastructure disappears**: no WPE WebKit, no
Mali-fbdev backend, no audio-ghost, no native miniaudio mixer, no evdev bridge.

The WebView (system Chromium, updatable from Android 5.0 onward) natively solves
the three root problems that consumed the muOS port:

| Problem on muOS | Solution on Android |
|---|---|
| `.ogg` decode stalled the WebProcess | WebView plays native `<audio>`/WebAudio |
| broken present/frame_complete (3 FPS) | SurfaceFlinger + Chromium compositor |
| input via evdev + anti-edge latch | Chromium's native Gamepad API |

## Target

- **Universal APK**: detects a physical gamepad (Android handheld, BT controller)
  and, when there is none, shows an on-screen touch overlay.
- **minSdk 21 (Android 5.0)**, targetSdk 34.
- Landscape orientation, immersive fullscreen, screen kept awake.

## Architecture

```
assets/www/               <- Construct 2 app (same as the muOS port)
  index.html              <- adapted: no file:// alert, fullscreen viewport,
                             injects touch-controls.js, SW disabled
  touch-controls.js       <- touch overlay -> fires the game's NATIVE keycodes
  c2runtime.js, data.js   <- original runtime + event sheet (untouched)
  jquery-3.4.1.min.js
  media/ (287 audio)      <- 283 .ogg + 4 .m4a
  images/ (1260)          <- sprites
src/.../MainActivity.java  <- fullscreen WebView, hardware-accel, immersive
src/.../LoggingChromeClient.java <- JS console -> logcat
AndroidManifest.xml        <- minSdk21, landscape, gamepad optional
build.sh                   <- manual build (aapt2+javac+d8+zipalign+apksigner)
```

### Controls

The game already supports the keyboard natively. Default mapping (from `data.js`
`varConKB_DEFAULT`/`_MENU`):

```
↑=38  ↓=40  ←=37  →=39
Z=90  X=88  S=83  A=65  C=67  Y=89   Enter=13 (confirm menu)
```

- **Physical gamepad**: read directly by C2's Gamepad API
  (`navigator.getGamepads`). The touch overlay disappears automatically when a
  gamepad connects.
- **Touch**: `touch-controls.js` synthesizes real `keydown`/`keyup` for those
  keycodes — without touching the engine. Layout: D-pad on the left, A/B/X/Y
  buttons on the right, START/SEL at the top.

## Distribute as a patch (no commercial assets)

This repository versions **only the port code** — no game assets. The engine
(`c2runtime.js`) and data (`data.js`) are **identical to the original**, so the
"patch" boils down to 4 web files + the Android wrapper. Anyone with a legitimate
copy of the game assembles the project with a single command:

```bash
./apply.sh /path/to/the/game/assets --build
# -> copies the game assets, overlays the port overrides and builds the APK
```

The "game assets folder" is where `c2runtime.js`, `data.js`, `media/`, `images/`,
the `.csv` files and `asteristic_logo.mp4` live — extracted from your own
legitimate copy of the game (Construct 2 / HTML5).

What the port overlays (in `dist/www-overrides/`):

| File | Original? | What changes |
|---|---|---|
| `index.html` | modified | fullscreen viewport, injects the port scripts, disables the service worker; see `dist/index.html.diff` |
| `settings.js` | **new** | live patches (FPS cap, scale, audio, CRT, brightness) |
| `options-menu.js` | **new** | ⚙ options panel |
| `touch-controls.js` | **new** | touch overlay |

`dist/index.html.diff` is the unified diff against the original `index.html`, for
auditing / manual reapplication.

### Asset integrity (SHA-256)

`dist/assets.sha256` holds the SHA-256 hashes of the essential game files
(engine, data, language CSVs, intro) plus aggregate hashes of the `media/`
(287 audio files: 283 .ogg + 4 .m4a) and `images/` (1260 files) folders. It lets
you confirm your asset copy is intact and matches what this port expects, without
redistributing any commercial content. `apply.sh` runs this check automatically
(non-fatal warning on mismatch). Manual:

```bash
cd /path/to/the/game/assets
sha256sum -c /path/to/dist/assets.sha256
```

## Build

No Gradle (lean manual build). Requires the local SDK in `.android-sdk/`
(cmdline-tools + platform android-34 + build-tools 34.0.0), already installed.

```bash
./build.sh
# -> build/Moonrider-debug.apk
```

## Install / test

```bash
adb install -r build/Moonrider-debug.apk
adb logcat -s MoonriderJS   # see the game's JS console
```

## Notes

- The assets are the property of JoyMasher / The Arcade Crew; **do not version**
  the contents of `assets/www/media` and `assets/www/images` publicly.
- Saves use `localStorage` (origin `file://`), persistent across runs.
- Electron/Steam files (greenworks, main.js, node_modules, .mp4) were
  deliberately omitted: the Steam code in `c2runtime.js` is gated on
  `runtime.isNWjs` (false in a WebView), so it never executes.
- APK ~127M because of the assets. To shrink: recompress `.ogg`/sprites.

## API version & compatibility

| Field | Value |
|---|---|
| **minSdkVersion** | **21** (Android 5.0 Lollipop) |
| **targetSdkVersion** | **34** (Android 14) |
| **compileSdkVersion** | 34 |
| versionCode / versionName | 1 / "1.0" |
| Package | `com.joymasher.moonrider` |

**Coverage:** Android **5.0 through 14+** — effectively 100% of Android devices in
use today. minSdk 21 is possible because the Chromium WebView became a
Play-Store-updatable component from Android 5.0, so even an old device gets a
modern WebView with WebGL, WebAudio and the Gamepad API — exactly the three
features the game needs.

Declared features are all optional (`required=false`), so the app is not
Play-Store-filtered by hardware: `android.hardware.gamepad`,
`android.hardware.touchscreen`, `android.hardware.usb.host`,
`android.hardware.screen.landscape`. Validated on a real device only on Android 13
(POCO X3 Pro / vayu); the minSdk 21 floor is declared and installs but was not
tested on Android 5–6 hardware.

## Official versions vs. the local assets

Official-store check (Jul 2026) compared to the Construct 2/HTML5 assets used by
this port (your local copy of the game):

| | Steam | GOG | Local assets (this port) |
|---|---|---|---|
| AppID / SKU | 1942010 | vengeful_guardian_moonrider | — |
| Release | 12 Jan 2023 | 12 Jan 2023 | — |
| Dev / Pub | JoyMasher / The Arcade Crew | same | same (package.json) |
| Languages | **10** (EN, FR, IT, DE, ES, +5) | **10** ("English & 9 more") | **10** `mrlang*` CSVs ✓ |
| Platform | Native Win | Native Win (DRM-free) | **HTML5/Construct 2** (NW.js) |
| Achievements | 13 (Steam) | — (GOG Galaxy) | present in the event sheet |
| Version | not publicly exposed¹ | not exposed | `package.json` = 1.0.0² |

¹ SteamDB (patchnotes/buildid) is blocked by bot-detection; couldn't extract the
  exact changelist without logging in.
² `1.0.0` is the generic NW.js wrapper value, it does **not** reflect the game
  patch. There is no *game* version number embedded in the assets (Construct 2
  does not write a build id into `c2runtime.js`/`data.js`). The `1.4.x` that shows
  up in a grep is an npm dependency version (fs-extra etc.), not the game.

**Comparison conclusion:** the local assets are the **same game** as the official
stores — same date, same 10 languages, same dev/pub — in the form of the
**Construct 2 (NW.js/Electron) web build** instead of the stores' native Windows
executable. Underneath, Steam/GOG run the same `c2runtime.js` + `data.js`; the
only difference is the runtime wrapping them (NW.js here vs. the stores' native
wrapper). That is why this WebView port works: it discards the NW.js/Steam
wrapper and serves the same Construct 2 assets in Android's WebView. **It was not
possible to confirm whether the assets correspond to the *latest* store patch**
(no buildid access), but the content (10 locales, event sheet with
achievements/remap) is the full release, not a demo.

## Validated on a real device

✅ **Validated on a real device** (POCO X3 Pro / vayu, LineageOS, Android 13):
title screen renders (WebGL/Adreno), audio plays (AAudio player USAGE_MEDIA
started), full touch overlay with the 4 shoulders (L1/L2 top-left, R1/R2
top-right). See `docs/RELATORIO-SESSAO-20260714.md`.

### Critical pitfall: the intro video is MANDATORY
The game opens with the `asteristic_logo.mp4` video (C2 Video plugin). If it is
missing, the app stays on a **black, silent screen** — C2 waits for the video to
finish before advancing to the menu, and it is the first user-gesture/media that
unlocks the WebView's audio context. **Always copy `asteristic_logo.mp4` (3.9MB)**
into `assets/www/`. The `testdemo.mp4` (217MB, attract/demo) is optional.

## Live options menu (⚙)

A gear button in the top-right corner opens a panel that applies everything
**live** (JavaScript) and saves to `localStorage`:

| Option | Effect |
|-------|--------|
| FPS cap | 30 / 60 / 90 / 120 / Uncapped **+ `…` button for a custom value (10–240)** — per-callback gate on requestAnimationFrame (measured: cap 30→30fps, 60→60fps) |
| Scale | Off / Auto / 50 / 100 / 200 / 300 / 400 / 500% **+ `…` button for a custom % (25–1000)** of the native 428×240 resolution (pixel-perfect; measured: 100%→428px, 200%→856px, 500%→2140px) |
| Pixel smoothing | nearest (sharp) vs linear |
| Volume | 0–100% (master GainNode on WebAudio) |
| Audio | Stereo / Mono (real downmix via channel merger) |
| Show FPS | Counter at the top |
| CRT filter | Retro scanlines |
| Brightness | 50–150% |
| Vibration | Haptics on the touch buttons |
| Keep screen awake | Native bridge FLAG_KEEP_SCREEN_ON |
| Force touch overlay | Buttons visible even with a gamepad |
| **Quit game** | Closes the app (Activity.finish) via the native bridge — the game menu's "Quit" calls an NW.js/Electron API that doesn't exist in a WebView and does nothing |

Files: `assets/www/settings.js` (API patches, loaded BEFORE c2runtime) +
`assets/www/options-menu.js` (UI). Opening the menu pauses the game.

> Custom values: the **FPS cap** and **Scale** rows have a `…` button that opens
> an inline number field — type any value (Enter confirms, Esc cancels). The chip
> stays highlighted showing the active custom value.

## Exiting the app

- **"Quit game" button** in the ⚙ menu (two-tap confirmation) → `Activity.finish()`
  via the native bridge.
- **Double Back**: one Back tap shows a hint; a second tap within 2s closes the
  app. A safety valve in case the menu/bridge fails — the user never gets stuck.
  (The *game* menu's "Quit" does not work: it calls a nonexistent NW.js/Electron
  API in the WebView.)

## Roadmap / To-dos

Technical investigation done on `c2runtime.js` + `data.js` (event sheet) to assess
the feasibility of each item:

### 1. i18n for the custom menu (our overlay) — EASY
Today `options-menu.js` has its strings **hardcoded in PT**. Plan:
- Extract the strings into a `MR_I18N[lang]` dictionary in `settings.js`.
- Languages to cover (mirror the game's 10 native ones): pt, en, ja, de, fr, es,
  zh-Hans, zh-Hant, ko, it.
- Pick the menu language from the same value used for the game (see item 2), with
  a fallback to `en`.
- Effort: low. Risk: none (our code only).

### 2. Switch the game's internal language — VIABLE (root cause identified)
**Cause:** the game has no selector of its own. It reads `navigator.language` (via
the C2 "Language" expression) into a `windowsLanguage` variable and compares the
prefix against `pt/en/ja/de/fr/es/zh/ko/it`, loading the matching CSV
(`moonriderloc-mrlang{us,ptbr,jp,de,fr,es,chs,cht,kr,it}.csv`). On Android
`navigator.language` = the system locale, **with no way to change it in-game**.
**Plan:** in `settings.js` (loaded BEFORE `c2runtime.js`), override
`navigator.language`/`navigator.languages` with the saved language, and reload the
page on change (the language is only read at startup). Add a "Game language" row
to the ⚙ menu with the 10 values.
- Effort: medium (needs reload + code→prefix mapping). Risk: low — it doesn't
  alter the engine, only the value read at boot. **Validate:** each CSV actually
  loads ("CSV loaded successfully!" in logcat) and the CJK fonts render in the
  WebView.

### 3. Internal gamepad submenu / remap — INVESTIGATE
The event sheet has `remap` (37x) and `ConKB` (keyboard config) — i.e. **the game
already has remapping**. It remains to confirm whether the controls menu opens and
is navigable via a physical gamepad in the WebView (the Gamepad API delivers the
events, but the menu may depend on keyboard input the overlay/gamepad doesn't
synthesize). **Plan:** open Options→Controls in-game with a gamepad and observe;
if it doesn't navigate, map the gamepad buttons to the keycodes the menu expects
(reuse the `touch-controls.js` bridge). If the native remap works, document it;
otherwise expose a simple remap in our overlay.
- Effort: medium/uncertain until tested on a device. Risk: medium.

### 4. Useful cheats / hacks — PARTIALLY VIABLE
C2's global variables are accessible via `c2runtime` in the console/JS. Low-risk
candidates (dev/accessibility, opt-in and warned):
- **Infinite life / no-damage**: locate the player HP variable in the event sheet
  and force it every tick (periodic patch via `settings.js`).
- **Slow-mo / turbo**: we already have FPS control; a `dt` multiplier would give
  accessibility slow-motion.
- **Level select / unlock**: if there's a progress flag in `localStorage`.
These depend on mapping specific variables in `data.js` (laborious, obfuscated
names). **Plan:** start with slow-mo (we already have the time base) and an
invincibility toggle if the HP variable is locatable. Clearly mark them as
"cheats" and off by default.
- Effort: high (event-sheet reverse engineering). Risk: medium.

### 5. Touch overlay: visual + haptic feedback on press — MISSING
The on-screen touch buttons currently fire the keycodes correctly but give no
press feedback: no visual state change (pressed/highlight) and no haptic pulse
when a button is touched. Plan: add an `:active`/pressed style (opacity/scale/glow)
on `touchstart` and reset on `touchend` in `touch-controls.js`, and trigger a
short `navigator.vibrate()` pulse gated by the existing "Vibration" toggle in the
⚙ menu. Effort: low. Risk: none (our code only).

Suggested priority: **1 → 2 → 3 → 5 → 4** (from cheapest/safest to most uncertain;
item 5 is a quick UX win).

## Legal

The port code is licensed under the **Apache License 2.0** — see
[`LICENSE.md`](LICENSE.md) and [`NOTICE`](NOTICE).

This repository contains **only** the port code (WebView wrapper + JS/HTML
overlays), by the author. **No game asset is included or redistributed** —
`c2runtime.js`, `data.js`, audio, sprites, CSVs and the game's icons are the
property of **JoyMasher / The Arcade Crew / Asteristic Game Studio** and must be
supplied by whoever owns a legitimate copy (`apply.sh`). The `.gitignore` blocks
all of that material. The Apache 2.0 license covers **only** the author's port
code, not the game (see `NOTICE`). Unofficial project, not affiliated with
JoyMasher / The Arcade Crew / Asteristic Game Studio.

### App icon

The launcher icon (`res/mipmap-*/ic_launcher.png`, see `docs/icon.png`) is custom
Moonrider art, generated at 5 densities from a 256×256 PNG. To change it, replace
the PNGs at the 5 densities (mdpi 48px, hdpi 72, xhdpi 96, xxhdpi 144, xxxhdpi 192)
and rebuild. If you use official game art, keep it out of git.

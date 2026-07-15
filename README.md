# Moonrider Android

<p align="center">
  <img src="docs/icon.png" alt="Moonrider Android app icon" width="128" height="128">
  <br>
  <em>All rights reserved to JoyMasher, The Arcade Crew and Asteristic Game Studio.</em>
</p>

Android port of **Vengeful Guardian: Moonrider** — the Construct 2 / HTML5 build
of the game wrapped in a native WebView and shipped as a universal APK. Physical
gamepads work out of the box; a touch overlay appears when none is connected.

This repo contains **only the port code**. No game assets are included — bring
your own copy of the game (see below).

## Requirements

- Android 5.0+ (minSdk 21, targetSdk 34) on the target device
- A legitimate copy of the game's assets
- To build: a Linux host (tested on Debian 13; Ubuntu works the same), a JDK
  17+, and a local Android SDK in `.android-sdk/` (cmdline-tools, platform 34,
  build-tools 34.0.0)

The build uses the raw SDK build-tools directly — **no Gradle, no Android
Studio**. There's also a Docker path if you'd rather not install a toolchain.

## Build

The quickest path, from a fresh clone with a copy of the game:

```bash
# 1. Extract the Construct 2 assets out of the game's Electron app.asar
./extract-assets.sh /path/to/Vengeful.Guardian.Moonrider ./game-assets

# 2. Build the APK — pick "docker" (isolated Debian container, nothing installed
#    on your host) or "baremetal" (installs deps via apt and builds directly)
./make-apk.sh --mode docker ./game-assets     # -> build/Moonrider-debug.apk
```

`make-apk.sh` bootstraps the Android SDK for you the first time, so a fresh
clone builds from zero with no manual SDK setup. Run it with no arguments for an
interactive prompt.

Prefer to drive the pipeline by hand?

```bash
./apply.sh ./game-assets --build   # stage assets + build in one step
# or, if assets/www/ is already populated:
./build.sh                         # -> build/Moonrider-debug.apk
```

`apply.sh` copies your game assets into `assets/www/`, strips leftover Electron/
Steam junk, applies the port's overrides, and (with `--build`) produces the APK.
It also verifies the assets against `dist/assets.sha256` and warns on mismatch.

**Full instructions** — asset extraction, host packages, SDK bootstrap, the
build pipeline, Docker, and troubleshooting — are in [`BUILD.md`](BUILD.md).

The "game assets folder" is the one holding `c2runtime.js`, `data.js`, `media/`,
`images/`, the `.csv` files and `asteristic_logo.mp4`. `extract-assets.sh`
produces exactly this from the game's `app.asar`.

> The intro video `asteristic_logo.mp4` is **mandatory** — without it the app
> boots to a black, silent screen (the engine waits for it before the menu, and
> it's what unlocks WebView audio).

## Install

```bash
adb install -r build/Moonrider-debug.apk
```

## The port

Four files override the original web build (kept in `dist/www-overrides/`):

- `index.html` — fullscreen viewport, injects the port scripts, disables the
  service worker (`dist/index.html.diff` has the exact changes)
- `touch-controls.js` — on-screen overlay that fires the game's native keycodes
- `settings.js` + `options-menu.js` — a live options menu (gear button)

Everything else (`c2runtime.js`, `data.js`, sprites, audio) is the untouched
original. Saves live in `localStorage`.

### Options menu (⚙)

Applied live and saved to `localStorage`: FPS cap (presets + custom), integer/
percentage scaling (presets + custom), pixel smoothing, volume, stereo/mono,
FPS counter, CRT scanlines, brightness, haptics, keep-awake, force touch overlay,
and quit.

Quitting: use **Quit game** in the menu or double-tap Back. The game's own "Quit"
does nothing — it calls an NW.js API that doesn't exist in a WebView.

## About the assets

The game ships on Steam (AppID 1942010) and GOG as a native Windows build, but
underneath it's the same Construct 2 app this port wraps — which is why serving
those assets in a WebView works. Ten languages, released 12 Jan 2023.

These assets match the **launch build** (Steam BuildID 10293244, 12 Jan 2023),
not the only patch that followed (BuildID 10710596, 28 Mar 2023). Confirmed by
three markers the patch would have changed: `steam_appid.txt` is still present
(the patch removed it), there's no `CRT.ini` (the patch added it), and the boss
tracks the patch introduced (submarine / serpent / brain-jar) are absent. The
patch was mostly bug fixes, balancing and a Windows-only CRT rework, so little of
it affects this port.

`dist/assets.sha256` lets you verify your copy is intact without redistributing
anything:

```bash
cd /path/to/game/assets && sha256sum -c /path/to/dist/assets.sha256
```

Tested on a POCO X3 Pro (Android 13). The minSdk 21 floor is declared but hasn't
been checked on very old hardware.

## Roadmap

1. **Menu i18n** — the options menu strings are hardcoded in Portuguese; move
   them to a small dictionary covering the game's 10 languages.
2. **Game language switch** — the game picks its language from
   `navigator.language` (the system locale) with no in-game selector. Overriding
   that value in `settings.js` before boot + a reload would expose a picker.
3. **Gamepad remap menu** — the game has a native remap; confirm it's navigable
   with a physical gamepad in the WebView, otherwise expose our own.
4. **Touch feedback** — the overlay buttons have no pressed state or haptic pulse
   yet.
5. **Cheats** *(maybe)* — slow-mo is easy (we already control the timestep);
   invincibility needs finding the HP variable in the obfuscated event sheet.

## Legal

Port code licensed under **Apache 2.0** — see [`LICENSE.md`](LICENSE.md) and
[`NOTICE`](NOTICE). The license covers the port code only.

*Vengeful Guardian: Moonrider* and all its assets (engine, data, audio, sprites,
artwork, icons) are the property of **JoyMasher / The Arcade Crew / Asteristic
Game Studio** and are not included here. Unofficial project, not affiliated with
them.

The launcher icon is custom art; if you swap in official game art, keep it out of
git.

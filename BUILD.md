# Building Moonrider Android

This project builds a signed debug APK **without Gradle** — the raw Android SDK
build-tools are driven directly:

```
aapt2 compile  ->  aapt2 link  ->  javac  ->  d8  ->  zipalign  ->  apksigner
```

Everything lives in a self-contained SDK under `.android-sdk/`, so once that
folder is populated the build touches nothing else on your machine and needs no
`ANDROID_HOME`, no Android Studio, no Gradle daemon.

There are two ways to build:

- **`make-apk.sh`** — the recommended one-stop helper. Pick **docker** (builds
  inside a self-contained Debian container, nothing installed on your host) or
  **baremetal** (installs deps via apt and builds directly). It also bootstraps
  the Android SDK automatically. See [section 3](#3-quick-build-with-make-apksh).
- **The manual pipeline** — `apply.sh` + `build.sh` with a hand-installed SDK,
  documented in full from [section 4](#4-manual-build) on if you want to
  understand or customize each step.

> **You still need to supply the game assets.** This repo ships only the port
> code — no commercial assets. You provide your own legit copy of *Vengeful
> Guardian: Moonrider*. `extract-assets.sh` ([section 2](#2-getting-the-game-assets))
> pulls the Construct 2 assets out of it.

---

## 1. The scripts at a glance

| Script | What it does |
|--------|--------------|
| `extract-assets.sh` | Extracts the Construct 2 assets from the game's `app.asar` (or an install dir / already-extracted folder) into a clean `game-assets/` folder. |
| `make-apk.sh` | One-stop build helper: choose **docker** or **baremetal**, auto-bootstraps the SDK, produces the APK. |
| `apply.sh` | Stages a game-assets folder into `assets/www/`, lays the port overrides on top, optionally builds. |
| `build.sh` | The raw build-tools pipeline (aapt2 → javac → d8 → zipalign → apksigner). Called by `apply.sh --build`. |

Typical end-to-end run (from a fresh clone):

```bash
./extract-assets.sh /path/to/Vengeful.Guardian.Moonrider ./game-assets
./make-apk.sh --mode docker ./game-assets
```

---

## 2. Getting the game assets

The commercial game (Steam/GOG) is an **Electron** app: the Construct 2 assets
(`c2runtime.js`, `data.js`, `media/`, `images/`, `asteristic_logo.mp4`) live
**inside `resources/app.asar`**. `extract-assets.sh` gets them out.

### 2.1 Requirements

- **Node.js 16+** (for `npx asar`). Debian/Ubuntu: `sudo apt install -y nodejs npm`.
- To unpack a `.rar`/`.7z` game archive first: `sudo apt install -y unrar-free p7zip-full`
  (or `unrar`).

### 2.2 Run it

`extract-assets.sh` accepts three kinds of input and figures out what it got:

```bash
# a) the game install folder (auto-finds game/resources/app.asar)
./extract-assets.sh /path/to/Vengeful.Guardian.Moonrider ./game-assets

# b) an app.asar directly
./extract-assets.sh /path/to/app.asar ./game-assets

# c) a folder that already has the assets extracted (c2runtime.js at its root)
./extract-assets.sh /path/to/extracted-www ./game-assets
```

Second argument is the output folder (default: `./game-assets`).

What it does:
1. locates `app.asar` (or detects already-extracted assets),
2. extracts it with `npx asar@3.2.0` (falls back to `@electron/asar`),
3. finds the Construct 2 root inside (`c2runtime.js`),
4. copies it to the output folder,
5. **strips the Electron/Steam junk** — `greenworks/`, `node_modules/`,
   `steam_settings/`, the cross-platform `.node` binaries, etc. This is real
   dead weight: the raw asar is ~360 MB, the cleaned output is ~140 MB, and none
   of the removed files are ever loaded by the WebView.
6. validates the essential assets are present before and after.

> `game-assets/` is gitignored, so extracted commercial assets can never be
> committed by accident.

The output folder is exactly what `apply.sh` / `make-apk.sh` expect.

---

## 3. Quick build with make-apk.sh

`make-apk.sh` is the recommended path. It handles dependency install and SDK
bootstrap for you, in whichever mode you pick.

### 3.1 Interactive

```bash
./make-apk.sh
```

It asks for the mode (docker / baremetal) and the assets folder, then runs.

### 3.2 Non-interactive

```bash
./make-apk.sh --mode docker    ./game-assets
./make-apk.sh --mode baremetal ./game-assets
```

### 3.3 What each mode does

**docker** — builds inside a Debian container from `Dockerfile.build`. Nothing
is installed on your host beyond Docker itself.
- Builds the image, then runs the build inside it.
- The repo is bind-mounted at `/app`; the assets folder is mounted read-only.
- Runs as your host UID/GID (`--user $(id -u):$(id -g)`), so `build/`,
  `.android-sdk/` and `debug.keystore` come out **owned by you**, not root.
- The SDK it bootstraps persists in `.android-sdk/` on the host (bind mount), so
  the next build reuses it.

**baremetal** — installs deps on the host and builds directly.
- Detects what's missing (JDK, zip, unzip, curl) and installs only that via apt
  (uses sudo if you're not root).
- Bootstraps the SDK into `.android-sdk/` if incomplete.
- Runs `apply.sh <assets> --build`.

Both modes share the same idempotent SDK-bootstrap step, so a fresh clone builds
from zero with no manual SDK setup.

### 3.4 Output

```
build/Moonrider-debug.apk    (~130 MB — most of it is the game assets)
```

The debug keystore (`debug.keystore`, password `android`) is generated
automatically on the first build.

---

## 4. Manual build

If you'd rather run the pipeline by hand (or need to customize it), here's every
step. This is what `make-apk.sh --mode baremetal` automates.

### 4.1 Host OS

Developed and tested on **Debian 13 (trixie)**. **Ubuntu 22.04 / 24.04** work
identically — the package names below are the same on both. Any glibc Linux with
a JDK and the tools listed will do; the pipeline is plain shell.

### 4.2 A JDK (17 or newer)

`javac`/`keytool` come from the JDK. The build was run with **OpenJDK 21**;
17 and 21 are both fine. The Java *sources* are compiled with `-source 8
-target 8`, so the language level is Java 8 regardless of which JDK you use — you
only need a modern JDK to *run* the toolchain, not to target it.

```bash
sudo apt update
sudo apt install -y openjdk-21-jdk-headless
java -version    # expect 17.x or 21.x
javac -version
```

If you have several JDKs installed, make sure the 17+ one is default:

```bash
sudo update-alternatives --config java
sudo update-alternatives --config javac
```

### 4.3 Shell utilities

```bash
sudo apt install -y bash coreutils findutils zip unzip curl
```

- `zip` / `unzip` — d8 output is zipped into the APK; the SDK archives are unzipped.
- `curl` — to download the command-line tools (section 4.5).
- `sha256sum` (from coreutils) — asset integrity check in `apply.sh`.

### 4.4 The Android SDK components

The build expects **exactly** this layout under `.android-sdk/` (relative to the
repo root):

```
.android-sdk/
├── cmdline-tools/latest/      # sdkmanager lives here
├── platform-tools/            # adb (for installing)
├── platforms/android-34/      # android.jar (compile target)
└── build-tools/34.0.0/        # aapt2, d8, zipalign, apksigner
```

`build.sh` hard-codes `build-tools/34.0.0` and `platforms/android-34`. If you
install different versions, either match these or edit the `BT` / `PLATFORM`
variables at the top of `build.sh`.

### 4.5 Download the command-line tools

> `make-apk.sh` does all of this automatically. These steps are the manual
> equivalent.

```bash
cd ~/projects/moonrider-android
mkdir -p .android-sdk/cmdline-tools

# Linux command-line tools (check https://developer.android.com/studio for the
# current build number; 11076708 is a known-good one).
curl -L -o /tmp/cmdline-tools.zip \
  https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip

unzip -q /tmp/cmdline-tools.zip -d .android-sdk/cmdline-tools
# The zip unpacks to a folder literally named "cmdline-tools"; sdkmanager wants
# it under a version dir called "latest":
mv .android-sdk/cmdline-tools/cmdline-tools .android-sdk/cmdline-tools/latest
```

### 4.6 Install the required packages

```bash
cd ~/projects/moonrider-android
export ANDROID_SDK_ROOT="$PWD/.android-sdk"
SDKMANAGER=".android-sdk/cmdline-tools/latest/bin/sdkmanager"

# Accept licenses (writes into .android-sdk/licenses/)
yes | "$SDKMANAGER" --sdk_root="$ANDROID_SDK_ROOT" --licenses

# Install exactly what build.sh needs
"$SDKMANAGER" --sdk_root="$ANDROID_SDK_ROOT" \
  "platform-tools" \
  "platforms;android-34" \
  "build-tools;34.0.0"
```

Verify the layout matches section 4.4:

```bash
ls .android-sdk/build-tools/34.0.0/aapt2
ls .android-sdk/platforms/android-34/android.jar
```

> **32-bit note:** `aapt2` and friends are 64-bit ELF binaries. On a bare-bones
> or containerized system you may need `sudo apt install -y libc6 zlib1g`
> (already present on a normal desktop Debian/Ubuntu).

### 4.7 Assemble assets + build

```bash
./apply.sh ./game-assets --build
```

`apply.sh`:
1. validates the folder actually holds the game (`c2runtime.js`, `data.js`,
   `asteristic_logo.mp4`),
2. verifies it against `dist/assets.sha256` (warns, doesn't block, on mismatch),
3. copies everything into `assets/www/`,
4. removes leftover Electron/NW.js/Steam junk (`greenworks/`, `node_modules/`,
   `steam_settings/`, `*.node`, `package.json`, …),
5. lays the port overrides on top (`index.html`, `settings.js`,
   `options-menu.js`, `touch-controls.js`),
6. with `--build`, calls `build.sh`.

### 4.8 Build only (assets already staged)

If `assets/www/` is already populated from a previous `apply.sh` run:

```bash
./build.sh
```

### 4.9 What build.sh does, step by step

| Step | Tool       | Purpose                                                      |
|------|------------|-------------------------------------------------------------|
| 1/6  | `aapt2 compile` | compile `res/` (launcher icons) to `flat/res.zip`      |
| 2/6  | `aapt2 link`    | link resources + `assets/` into `base.apk`, emit `R.java` |
| 3/6  | `javac`         | compile `src/` + generated `R.java` (Java 8 level)     |
| 4/6  | `d8`            | dex the classes into `classes.dex`                     |
| 5/6  | `zip` + `zipalign` | inject `classes.dex`, 4-byte align                  |
| 6/6  | `apksigner`     | sign with the debug keystore, then verify              |

All intermediates land in `build/` (gitignored).

---

## 5. Install

```bash
.android-sdk/platform-tools/adb install -r build/Moonrider-debug.apk
# or, if platform-tools is on your PATH:
adb install -r build/Moonrider-debug.apk
```

Enable USB debugging on the device first (Settings → Developer options).

If you built in Docker, `adb install` is easiest from the **host** (USB
passthrough into a container is fiddly) — build in Docker, install from the host.

---

## 6. Build in Docker — the manual command

`make-apk.sh --mode docker` (section 3) is the easy path. If you want to drive
Docker yourself, here's what it runs under the hood.

The repo ships a ready-to-use `Dockerfile.build` (Debian trixie + JDK + shell
tools). The SDK and game assets are bind-mounted from the host — never copied
into the image.

Build the image once:

```bash
docker build -f Dockerfile.build -t moonrider-build .
```

Run a build (host repo at `/app`, assets read-only, artifacts owned by you):

```bash
docker run --rm \
  --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD":/app \
  -v /path/to/game-assets:/assets:ro \
  -w /app \
  moonrider-build \
  ./make-apk.sh --mode baremetal /assets
```

The resulting `build/Moonrider-debug.apk` appears in your host repo because
`/app` is the bind mount.

> **Why `--user` + `HOME=/tmp`:** without `--user`, the container writes `build/`
> and `.android-sdk/` as root and you can't clean or rebuild them without sudo.
> Running as your host UID keeps everything yours. `HOME=/tmp` gives the
> non-root UID a writable home for `sdkmanager` (`~/.android`).

---

## 7. Troubleshooting

**`aapt2: not found` / `No such file or directory`**
The SDK isn't populated. Re-run `make-apk.sh` (it bootstraps the SDK), or check
section 4.6 and confirm `.android-sdk/build-tools/34.0.0/aapt2` exists.

**`build.sh` fails at step 3 with `class file has wrong version`**
A stray old JDK is first on PATH. Confirm `javac -version` is 17+ and re-run.
The `-source 8 -target 8` flags are correct — don't change them.

**`apksigner` complains about the keystore**
Delete `debug.keystore` and rebuild; `build.sh` regenerates it. The password is
`android` for both store and key (`alias androiddebugkey`).

**`extract-assets.sh` says "nao achei app.asar nem assets soltos"**
Point it at the folder that actually contains the game — the one with
`game/resources/app.asar`, or `resources/app.asar`, or `app.asar`. If your copy
is inside a `.rar`/`.7z`, extract that archive first.

**`extract-assets.sh` fails on `npx asar`**
Install Node 16+ (`sudo apt install -y nodejs npm`). The script tries
`asar@3.2.0` first (works on Node 16-22) and `@electron/asar` as a fallback
(needs Node ≥ 22.12).

**Build artifacts owned by root (after an old Docker build)**
Older builds ran the container as root. Fix ownership without sudo via the
container itself:
`docker run --rm -v "$PWD":/app -w /app moonrider-build chown -R $(id -u):$(id -g) build .android-sdk debug.keystore`.
Current `make-apk.sh` uses `--user`, so new builds don't have this problem.

**Asset SHA-256 warnings from `apply.sh`**
Non-fatal. It means your game copy differs from the launch build the manifest
was made against (e.g. a patched build). The build still proceeds; see the
"About the assets" section in `README.md`.

**Black/silent screen after install**
Your asset folder is missing `asteristic_logo.mp4`. It's mandatory — the engine
waits on it before the menu and it unlocks WebView audio. Re-run the extract/
build with the correct assets folder.

**Different SDK versions installed**
If you can't get `build-tools;34.0.0` / `platforms;android-34`, edit the `BT`
and `PLATFORM` lines at the top of `build.sh` to match what you have. The
pipeline itself is version-agnostic as long as the tools exist.

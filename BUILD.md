# Building Moonrider Android

This project builds a signed debug APK **without Gradle**. `build.sh` drives the
raw Android SDK build-tools directly:

```
aapt2 compile  ->  aapt2 link  ->  javac  ->  d8  ->  zipalign  ->  apksigner
```

Everything lives in a self-contained SDK under `.android-sdk/`, so once that
folder is populated the build touches nothing else on your machine and needs no
`ANDROID_HOME`, no Android Studio, no Gradle daemon.

> **You still need to supply the game assets.** This repo ships only the port
> code. See the "Assets" section in [`README.md`](README.md). The steps below
> assume you have a legit copy of *Vengeful Guardian: Moonrider* whose Construct
> 2 / HTML5 files you can point `apply.sh` at.

---

## 1. What you need

### 1.1 Host OS

Developed and tested on **Debian 13 (trixie)**. **Ubuntu 22.04 / 24.04** work
identically — the package names below are the same on both. Any glibc Linux with
a JDK and the tools listed will do; the pipeline is plain shell.

### 1.2 A JDK (17 or newer)

`javac`/`keytool` come from the JDK. The build was run with **OpenJDK 21**;
17 and 21 are both fine. The Java *sources* are compiled with `-source 8
-target 8`, so the language level is Java 8 regardless of which JDK you use — you
only need a modern JDK to *run* the toolchain, not to target it.

Debian / Ubuntu:

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

### 1.3 Shell utilities

The scripts call these directly. All are in the base repos:

```bash
sudo apt install -y bash coreutils findutils zip unzip curl
```

- `zip` / `unzip` — d8 output is zipped into the APK; the SDK archives are unzipped.
- `curl` — to download the command-line tools (step 2.1).
- `sha256sum` (from coreutils) — asset integrity check in `apply.sh`.

### 1.4 The Android SDK components

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

---

## 2. One-time SDK setup

You do **not** need Android Studio. Bootstrap the SDK with the standalone
command-line tools.

### 2.1 Download the command-line tools

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

### 2.2 Install the required packages

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

Verify the layout matches section 1.4:

```bash
ls .android-sdk/build-tools/34.0.0/aapt2
ls .android-sdk/platforms/android-34/android.jar
```

> **32-bit note:** `aapt2` and friends are 64-bit ELF binaries. On a bare-bones
> or containerized system you may need `sudo apt install -y libc6 zlib1g`
> (already present on a normal desktop Debian/Ubuntu).

---

## 3. Build

### 3.1 Assemble assets + build in one step

```bash
./apply.sh /path/to/game/assets --build
```

`apply.sh`:
1. validates the folder actually holds the game (`c2runtime.js`, `data.js`,
   `asteristic_logo.mp4`),
2. verifies it against `dist/assets.sha256` (warns, doesn't block, on mismatch),
3. copies everything into `assets/www/`,
4. lays the port overrides on top (`index.html`, `settings.js`,
   `options-menu.js`, `touch-controls.js`),
5. with `--build`, calls `build.sh`.

### 3.2 Build only (assets already staged)

If `assets/www/` is already populated from a previous `apply.sh` run:

```bash
./build.sh
```

Output:

```
build/Moonrider-debug.apk    (~130 MB — most of it is the game assets)
```

The debug keystore (`debug.keystore`, password `android`) is generated
automatically on the first build if it doesn't exist.

### 3.3 What build.sh does, step by step

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

## 4. Install

```bash
.android-sdk/platform-tools/adb install -r build/Moonrider-debug.apk
# or, if platform-tools is on your PATH:
adb install -r build/Moonrider-debug.apk
```

Enable USB debugging on the device first (Settings → Developer options).

---

## 5. Build in Docker (optional, fully reproducible)

Useful if you don't want a JDK/SDK on your host, or want a clean CI-style build.
The container needs the SDK too; the fastest path is to bind-mount the repo (so
your already-downloaded `.android-sdk/` and game assets are reused) and just run
the scripts inside.

The repo ships a ready-to-use `Dockerfile.build`. The container provides only
the JDK + shell tools; the SDK and game assets are bind-mounted from the host
(so your already-downloaded `.android-sdk/` and game copy are reused).

Build the image once:

```bash
docker build -f Dockerfile.build -t moonrider-build .
```

Run a build (host repo mounted at `/app`, game assets mounted read-only):

```bash
docker run --rm \
  -v "$PWD":/app \
  -v /path/to/game/assets:/assets:ro \
  moonrider-build \
  ./apply.sh /assets --build
```

The resulting `build/Moonrider-debug.apk` appears in your host repo because
`/app` is the bind mount.

Notes:
- If you haven't run the SDK bootstrap (section 2) on the host yet, do it once —
  either on the host, or inside the container by opening a shell
  (`docker run --rm -it -v "$PWD":/app moonrider-build bash`) and following the
  same `sdkmanager` steps. The SDK persists on the host via the bind mount.
- `adb install` is easiest from the host (USB passthrough into a container is
  fiddly). Build in Docker, install from the host.

---

## 6. Troubleshooting

**`aapt2: not found` / `No such file or directory`**
The SDK isn't populated. Re-check section 2.2 and confirm
`.android-sdk/build-tools/34.0.0/aapt2` exists.

**`build.sh` fails at step 3 with `class file has wrong version`**
A stray old JDK is first on PATH. Confirm `javac -version` is 17+ and re-run.
The `-source 8 -target 8` flags are correct — don't change them.

**`apksigner` complains about the keystore**
Delete `debug.keystore` and rebuild; `build.sh` regenerates it. The password is
`android` for both store and key (`alias androiddebugkey`).

**Asset SHA-256 warnings from `apply.sh`**
Non-fatal. It means your game copy differs from the launch build the manifest
was made against (e.g. a patched build). The build still proceeds; see the
"About the assets" section in `README.md`.

**Black/silent screen after install**
Your asset folder is missing `asteristic_logo.mp4`. It's mandatory — the engine
waits on it before the menu and it unlocks WebView audio. Re-run `apply.sh` with
the correct assets folder.

**Different SDK versions installed**
If you can't get `build-tools;34.0.0` / `platforms;android-34`, edit the `BT`
and `PLATFORM` lines at the top of `build.sh` to match what you have. The
pipeline itself is version-agnostic as long as the tools exist.

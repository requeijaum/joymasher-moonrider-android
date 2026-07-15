#!/usr/bin/env bash
#
# make-apk.sh - Interactive helper to build the Moonrider Android APK.
#
# Offers two paths:
#   * docker    - everything inside a Debian container; installs nothing on the
#                 host (beyond Docker itself). Reuses .android-sdk/ and the assets
#                 via bind-mount.
#   * baremetal - installs the dependencies (JDK + utilities) on the system via
#                 apt and builds directly on the host.
#
# In both cases, if .android-sdk/ is not populated yet, the script bootstraps it
# (cmdline-tools -> platform-tools, platforms;android-34, build-tools;34.0.0)
# automatically.
#
# USAGE:
#   ./make-apk.sh                         # interactive mode (asks everything)
#   ./make-apk.sh --mode docker    <assets-dir>
#   ./make-apk.sh --mode baremetal <assets-dir>
#   ./make-apk.sh --help
#
# NO commercial asset is distributed here: <assets-dir> is YOUR legit copy of the
# game (folder with c2runtime.js, data.js, asteristic_logo.mp4, media/, ...).
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SDK="$HERE/.android-sdk"
IMAGE="moonrider-build"

# Components required by build.sh (keep in sync with it).
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
SDK_PACKAGES=("platform-tools" "platforms;android-34" "build-tools;34.0.0")

c_blue()  { printf '\033[1;34m%s\033[0m\n' "$*"; }
c_green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_yellow(){ printf '\033[1;33m%s\033[0m\n' "$*"; }
die()     { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------
MODE=""
ASSETS_DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --mode)  MODE="${2:-}"; shift 2 ;;
        --mode=*) MODE="${1#*=}"; shift ;;
        -h|--help) usage 0 ;;
        --*) die "unknown option: $1 (use --help)" ;;
        *)   [ -z "$ASSETS_DIR" ] && ASSETS_DIR="$1" || die "extra argument: $1"; shift ;;
    esac
done

# --------------------------------------------------------------------------
# Interactive mode (if not provided via flag)
# --------------------------------------------------------------------------
if [ -z "$MODE" ]; then
    c_blue "How do you want to build the APK?"
    echo "  1) docker    - everything in a Debian container, nothing installed on the host"
    echo "  2) baremetal - installs JDK + deps on the system (apt) and builds directly"
    printf "Choose [1/2]: "
    read -r choice
    case "$choice" in
        1) MODE="docker" ;;
        2) MODE="baremetal" ;;
        *) die "invalid choice" ;;
    esac
fi

case "$MODE" in docker|baremetal) ;; *) die "invalid mode: '$MODE' (use docker or baremetal)";; esac

# --------------------------------------------------------------------------
# Game assets folder
# --------------------------------------------------------------------------
if [ -z "$ASSETS_DIR" ]; then
    c_blue "Where are the game assets (folder with c2runtime.js, data.js, asteristic_logo.mp4)?"
    printf "Path: "
    read -r ASSETS_DIR
fi
ASSETS_DIR="${ASSETS_DIR/#\~/$HOME}"
[ -n "$ASSETS_DIR" ] || die "you must provide the game assets folder"
[ -d "$ASSETS_DIR" ] || die "assets folder not found: $ASSETS_DIR"
for f in c2runtime.js data.js asteristic_logo.mp4; do
    [ -e "$ASSETS_DIR/$f" ] || die "essential asset missing in '$ASSETS_DIR': $f (this doesn't look like the game folder)"
done
ASSETS_DIR="$(cd "$ASSETS_DIR" && pwd)"   # normalize to absolute path
c_green "Game assets: $ASSETS_DIR"

# ==========================================================================
# Shared functions
# ==========================================================================

# Bootstrap the Android SDK into $SDK. Idempotent: only downloads what's missing.
# Runs both on the host (baremetal) and inside the container (docker), so it only
# depends on: curl, unzip, and a JDK (for sdkmanager).
bootstrap_sdk() {
    local bt="$SDK/build-tools/34.0.0/aapt2"
    local plat="$SDK/platforms/android-34/android.jar"
    if [ -f "$bt" ] && [ -f "$plat" ]; then
        c_green "SDK already present in .android-sdk/ (build-tools 34.0.0 + platform 34)."
        return 0
    fi

    c_yellow "SDK incomplete - bootstrapping into .android-sdk/ ..."
    local sdkmgr="$SDK/cmdline-tools/latest/bin/sdkmanager"
    if [ ! -x "$sdkmgr" ]; then
        c_blue "==> downloading cmdline-tools ..."
        mkdir -p "$SDK/cmdline-tools"
        local tmp; tmp="$(mktemp -d)"
        curl -fL -o "$tmp/cmdline-tools.zip" "$CMDLINE_TOOLS_URL"
        unzip -q "$tmp/cmdline-tools.zip" -d "$tmp"
        rm -rf "$SDK/cmdline-tools/latest"
        mv "$tmp/cmdline-tools" "$SDK/cmdline-tools/latest"
        rm -rf "$tmp"
    fi

    c_blue "==> accepting licenses and installing SDK packages ..."
    yes | "$sdkmgr" --sdk_root="$SDK" --licenses >/dev/null 2>&1 || true
    "$sdkmgr" --sdk_root="$SDK" "${SDK_PACKAGES[@]}"

    [ -f "$bt" ]   || die "bootstrap failed: aapt2 not found after installing build-tools"
    [ -f "$plat" ] || die "bootstrap failed: android.jar not found after installing the platform"
    c_green "SDK ready."
}

# ==========================================================================
# BAREMETAL MODE
# ==========================================================================
run_baremetal() {
    c_blue "=== Baremetal mode ==="

    # 1. system dependencies
    local need=()
    command -v javac    >/dev/null 2>&1 || need+=("openjdk-21-jdk-headless")
    command -v zip      >/dev/null 2>&1 || need+=("zip")
    command -v unzip    >/dev/null 2>&1 || need+=("unzip")
    command -v curl     >/dev/null 2>&1 || need+=("curl")
    command -v sha256sum>/dev/null 2>&1 || need+=("coreutils")

    if [ ${#need[@]} -gt 0 ]; then
        if command -v apt-get >/dev/null 2>&1; then
            c_yellow "Installing dependencies via apt: ${need[*]}"
            local SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
            $SUDO apt-get update
            $SUDO apt-get install -y --no-install-recommends "${need[@]}"
        else
            die "missing dependencies (${need[*]}) and this host doesn't use apt. Install them manually."
        fi
    else
        c_green "System dependencies already present (JDK, zip, unzip, curl)."
    fi

    command -v javac >/dev/null 2>&1 || die "javac still missing after installation"

    # 2. SDK
    bootstrap_sdk

    # 3. build
    c_blue "==> assembling assets and building (apply.sh --build) ..."
    "$HERE/apply.sh" "$ASSETS_DIR" --build
}

# ==========================================================================
# DOCKER MODE
# ==========================================================================
run_docker() {
    c_blue "=== Docker mode ==="
    command -v docker >/dev/null 2>&1 || die "docker not found on the host"
    docker info >/dev/null 2>&1 || die "the Docker daemon is not reachable (permissions? 'sudo usermod -aG docker \$USER' or run with sudo)"
    [ -f "$HERE/Dockerfile.build" ] || die "Dockerfile.build not found in the repo"

    c_blue "==> building the '$IMAGE' image ..."
    docker build -f "$HERE/Dockerfile.build" -t "$IMAGE" "$HERE"

    # Run the helper again INSIDE the container, in baremetal mode: there the apt and
    # SDK bootstrap happen in the container's isolated environment, writing into
    # .android-sdk/ (bind-mount) for later reuse. The assets come in read-only.
    # --user with the host UID/GID: prevents build/, .android-sdk/ and debug.keystore
    # from ending up owned by root (otherwise the host can't clean/rebuild without sudo).
    # HOME=/tmp: writable by any UID (sdkmanager writes ~/.android).
    c_blue "==> building inside the container (as UID $(id -u):$(id -g)) ..."
    docker run --rm \
        --user "$(id -u):$(id -g)" \
        -e HOME=/tmp \
        -v "$HERE":/app \
        -v "$ASSETS_DIR":/assets:ro \
        -w /app \
        "$IMAGE" \
        ./make-apk.sh --mode baremetal /assets
}

# ==========================================================================
case "$MODE" in
    baremetal) run_baremetal ;;
    docker)    run_docker ;;
esac

APK="$HERE/build/Moonrider-debug.apk"
if [ -f "$APK" ]; then
    echo
    c_green "APK generated: $APK"
    ls -lh "$APK"
    echo
    echo "Install on the device (USB debugging enabled):"
    echo "  ${SDK}/platform-tools/adb install -r \"$APK\""
else
    die "the build finished but the APK was not found at $APK"
fi

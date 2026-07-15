#!/usr/bin/env bash
#
# apply.sh - Assemble the Android project by overlaying the port's files on top of
#            the original game assets (Vengeful Guardian: Moonrider, Construct 2 build).
#
# USAGE:
#   ./apply.sh /path/to/game/assets [--build]
#
# The "game assets folder" is the directory holding c2runtime.js, data.js, the
# media/ and images/ folders, the localization .csv files and asteristic_logo.mp4 —
# extracted from your own legit copy of the game (Construct 2 / HTML5).
#
# This script:
#   1. Validates the folder has the essential assets.
#   2. Copies ALL game assets into assets/www/ (nothing commercial goes to git).
#   3. Overlays the port overrides (dist/www-overrides/*).
#   4. Optionally builds the APK (--build) by calling build.sh.
#
# No commercial asset is distributed with this repository; you must supply your
# own legit copy of the game.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GAME_DIR="${1:-}"
DO_BUILD="${2:-}"

die() { echo "ERROR: $*" >&2; exit 1; }

[ -n "$GAME_DIR" ] || die "provide the game assets folder. Usage: ./apply.sh <game-folder> [--build]"
[ -d "$GAME_DIR" ] || die "folder not found: $GAME_DIR"

# --- 1. validate essential assets -----------------------------------------
REQUIRED=(c2runtime.js data.js asteristic_logo.mp4)
for f in "${REQUIRED[@]}"; do
    [ -e "$GAME_DIR/$f" ] || die "essential asset missing in '$GAME_DIR': $f
       (this doesn't look like the Moonrider game folder; look for c2runtime.js and data.js)"
done
echo "==> game assets validated in: $GAME_DIR"

# --- 1b. integrity check (SHA-256) ----------------------------------------
# Not fatal: only warns if something differs from the expected content (dist/assets.sha256).
MANIFEST="$HERE/dist/assets.sha256"
if [ -f "$MANIFEST" ] && command -v sha256sum >/dev/null 2>&1; then
    echo "==> verifying asset integrity (SHA-256) ..."
    if ( cd "$GAME_DIR" && sha256sum -c "$MANIFEST" --quiet ) 2>/dev/null; then
        echo "    essential files: OK"
    else
        echo "    WARNING: one or more files differ from the expected manifest."
        echo "             (different game version? proceeding anyway)"
    fi
    # aggregate hashes of media/ and images/ (compared to the values in the manifest)
    for pair in "media a737afecbf6c388b09ab1cac7be124348befeade3211f3e45c4e1dacb5701919" \
                "images 359ceb439184ae644d30464f0f6332266cef1deae3188d1f9c580cca0e40e5fc"; do
        d="${pair%% *}"; want="${pair##* }"
        if [ -d "$GAME_DIR/$d" ]; then
            got=$( cd "$GAME_DIR" && find "$d" -type f | sort | xargs sha256sum | sha256sum | awk '{print $1}' )
            [ "$got" = "$want" ] && echo "    $d/: OK" || echo "    WARNING: $d/ differs (expected $want, got $got)"
        fi
    done
fi

# --- 2. copy game assets --------------------------------------------------
WWW="$HERE/assets/www"
mkdir -p "$WWW"
echo "==> copying game assets into assets/www/ ..."
# copy everything from the game (js, csv, png, mp4, media/, images/) preserving structure
cp -a "$GAME_DIR/." "$WWW/"

# remove Electron/NW.js/Steam build leftovers that are useless on Android (optional)
for junk in main.js preload.js offline.js offlineClient.js user.js config.js \
            greenworks.js greenworks-*.node package.json yarn.lock steam_appid.txt \
            sw.js testdemo.mp4; do
    rm -f "$WWW/$junk"
done
# native/Steam dependency dirs (greenworks/, node_modules/, steam_settings/):
# Windows/Linux/macOS .node binaries that only bloat the APK — the WebView never uses them.
# (kept in sync with JUNK_DIRS in extract-assets.sh)
for junkdir in greenworks node_modules steam_settings; do
    rm -rf "$WWW/$junkdir"
done

# --- 3. overlay the port overrides ----------------------------------------
echo "==> applying port overrides (index.html + settings/options/touch) ..."
cp -f "$HERE/dist/www-overrides/index.html"       "$WWW/index.html"
cp -f "$HERE/dist/www-overrides/settings.js"      "$WWW/settings.js"
cp -f "$HERE/dist/www-overrides/options-menu.js"  "$WWW/options-menu.js"
cp -f "$HERE/dist/www-overrides/touch-controls.js" "$WWW/touch-controls.js"

echo "==> done. assets/www/ assembled with the port applied."

# --- 4. optional build -----------------------------------------------------
if [ "$DO_BUILD" = "--build" ] || [ "$GAME_DIR" = "--build" ]; then
    [ -x "$HERE/build.sh" ] || die "build.sh not found/executable"
    echo "==> starting APK build ..."
    ( cd "$HERE" && ./build.sh )
    echo "==> APK generated at build/Moonrider-debug.apk"
else
    echo "    To build the APK now:  ./build.sh"
    echo "    Or run:                ./apply.sh \"$GAME_DIR\" --build"
fi

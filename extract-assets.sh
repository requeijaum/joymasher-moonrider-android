#!/usr/bin/env bash
#
# extract-assets.sh - Extract the Construct 2 game assets (Vengeful Guardian:
#                     Moonrider) into a clean folder, ready for apply.sh.
#
# The commercial game (Steam/GOG) is an Electron app: the Construct 2 assets
# (c2runtime.js, data.js, media/, images/, asteristic_logo.mp4) live INSIDE
# resources/app.asar. This script locates and extracts that asar — or accepts a
# folder that already has the assets unpacked — and delivers everything to an
# output directory.
#
# USAGE:
#   ./extract-assets.sh <input> [output-folder]
#
#   <input> can be:
#     * an app.asar file
#     * the game install folder (containing game/resources/app.asar,
#       resources/app.asar, or app.asar itself at some level)
#     * a folder that ALREADY has the assets extracted (with c2runtime.js at its root)
#
#   [output-folder]  default: ./game-assets/
#
# Afterwards:
#   ./apply.sh ./game-assets --build      # assemble assets/www/ and build the APK
#   # or, in a single step:
#   ./extract-assets.sh <input> && ./apply.sh ./game-assets --build
#
# NO commercial asset is distributed with this repository. You supply your own
# legit copy of the game.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
IN="${1:-}"
OUT="${2:-$HERE/game-assets}"

# Assets that prove we reached the correct Construct 2 root.
REQUIRED=(c2runtime.js data.js asteristic_logo.mp4)
# Electron/NW.js/Steam junk that is useless on Android (mirrors apply.sh).
JUNK_FILES=(main.js preload.js offline.js offlineClient.js user.js config.js
            greenworks.js package.json yarn.lock steam_appid.txt sw.js testdemo.mp4)
JUNK_DIRS=(greenworks node_modules steam_settings)

die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m    %s\033[0m\n' "$*"; }

[ -n "$IN" ] || die "provide the input. Usage: ./extract-assets.sh <app.asar | game-folder | extracted-folder> [output]"
[ -e "$IN" ] || die "input not found: $IN"

# Check whether a directory has the essential assets at its root.
has_assets() {
    local d="$1" f
    for f in "${REQUIRED[@]}"; do
        [ -e "$d/$f" ] || return 1
    done
    return 0
}

# Locate an app.asar from the input (direct file or install folder).
find_asar() {
    local base="$1"
    if [ -f "$base" ] && [[ "$base" == *.asar ]]; then
        printf '%s\n' "$base"; return 0
    fi
    if [ -d "$base" ]; then
        local cand
        for cand in \
            "$base/game/resources/app.asar" \
            "$base/resources/app.asar" \
            "$base/app.asar"; do
            [ -f "$cand" ] && { printf '%s\n' "$cand"; return 0; }
        done
        # deep search as a last resort
        cand="$(find "$base" -maxdepth 5 -name app.asar -type f 2>/dev/null | head -1)"
        [ -n "$cand" ] && { printf '%s\n' "$cand"; return 0; }
    fi
    return 1
}

# Remove the Electron/Steam junk from an assets directory.
strip_junk() {
    local d="$1" j
    for j in "${JUNK_FILES[@]}"; do rm -f  "$d/$j"; done
    rm -f "$d"/greenworks-*.node
    for j in "${JUNK_DIRS[@]}";  do rm -rf "$d/$j"; done
}

# --------------------------------------------------------------------------
# Case A: the input is ALREADY a folder with the extracted assets.
# --------------------------------------------------------------------------
if [ -d "$IN" ] && has_assets "$IN"; then
    info "input already contains the extracted assets (c2runtime.js found)."
    SRC="$IN"
    COPY_MODE="dir"
else
    # ----------------------------------------------------------------------
    # Case B: we need to extract from an app.asar.
    # ----------------------------------------------------------------------
    info "looking for app.asar in: $IN"
    ASAR="$(find_asar "$IN")" || die "no app.asar nor loose assets found in '$IN'.
       Point to the game install folder, to the app.asar, or to an already
       extracted folder containing c2runtime.js."
    ok "app.asar: $ASAR"

    command -v npx  >/dev/null 2>&1 || die "npx not found (install Node.js >= 16: apt install nodejs npm)"

    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    info "extracting app.asar (npx asar) ... this may take ~1 min"
    # asar@3.2.0 works on Node 16-22; @electron/asar requires Node >= 22.12.
    npx --yes asar@3.2.0 extract "$ASAR" "$TMP/asar" \
        || npx --yes @electron/asar extract "$ASAR" "$TMP/asar" \
        || die "failed to extract the asar (neither asar@3.2.0 nor @electron/asar worked)"

    # Construct 2 is usually at the asar root; if not, find the right subfolder.
    if has_assets "$TMP/asar"; then
        SRC="$TMP/asar"
    else
        SUB="$(find "$TMP/asar" -maxdepth 4 -name c2runtime.js -type f 2>/dev/null | head -1)"
        [ -n "$SUB" ] || die "asar extracted, but c2runtime.js was not found inside it."
        SRC="$(dirname "$SUB")"
        ok "C2 assets found in: ${SRC#$TMP/asar/}"
    fi
    COPY_MODE="dir"
fi

# --------------------------------------------------------------------------
# Copy to the output and clean the junk.
# --------------------------------------------------------------------------
has_assets "$SRC" || die "final validation failed: essential assets missing in $SRC"

info "copying assets to: $OUT"
mkdir -p "$OUT"
# preserve structure (media/, images/, .csv, .mp4, .js)
cp -a "$SRC/." "$OUT/"

info "removing Electron/NW.js/Steam leftovers (greenworks, node_modules, ...)"
strip_junk "$OUT"

# Final check + summary
for f in "${REQUIRED[@]}"; do
    [ -e "$OUT/$f" ] || die "post-copy: essential asset vanished: $f"
done
ok "essential assets: OK (c2runtime.js, data.js, asteristic_logo.mp4)"
[ -d "$OUT/media" ]  && ok "media/:  present" || echo "    WARNING: media/ missing (audio may be absent)"
[ -d "$OUT/images" ] && ok "images/: present" || echo "    WARNING: images/ missing (sprites may be absent)"

echo
info "done. Clean assets in: $OUT"
echo "    Size: $(du -sh "$OUT" 2>/dev/null | cut -f1)"
echo
echo "Next step:"
echo "    ./apply.sh \"$OUT\" --build        # assemble assets/www/ and build the APK"
echo "    ./make-apk.sh --mode docker \"$OUT\"  # isolated build in a Debian container"

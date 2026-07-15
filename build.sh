#!/bin/bash
# Build Moonrider Android APK (debug) using the raw SDK build-tools, no Gradle.
# Pipeline: aapt2 compile -> aapt2 link -> javac -> d8 -> zipalign -> apksigner
set -euo pipefail

PROJ="$(cd "$(dirname "$0")" && pwd)"
SDK="$PROJ/.android-sdk"
BT="$SDK/build-tools/34.0.0"
PLATFORM="$SDK/platforms/android-34/android.jar"
AAPT2="$BT/aapt2"
D8="$BT/d8"
ZIPALIGN="$BT/zipalign"
APKSIGNER="$BT/apksigner"

OUT="$PROJ/build"
GEN="$OUT/gen"
OBJ="$OUT/obj"
DEX="$OUT/dex"
FLAT="$OUT/flat"
rm -rf "$OUT"
mkdir -p "$GEN" "$OBJ" "$DEX" "$FLAT"

echo "==> [1/6] aapt2 compile resources"
"$AAPT2" compile --dir "$PROJ/res" -o "$FLAT/res.zip"

echo "==> [2/6] aapt2 link (generates R.java + base APK with resources+assets)"
"$AAPT2" link \
    -o "$OUT/base.apk" \
    -I "$PLATFORM" \
    --manifest "$PROJ/AndroidManifest.xml" \
    -R "$FLAT/res.zip" \
    -A "$PROJ/assets" \
    --java "$GEN" \
    --min-sdk-version 21 \
    --target-sdk-version 34 \
    --auto-add-overlay

echo "==> [3/6] javac (compile Java sources)"
find "$PROJ/src" "$GEN" -name '*.java' > "$OUT/sources.txt"
javac -source 8 -target 8 \
    -bootclasspath "$PLATFORM" \
    -classpath "$PLATFORM" \
    -d "$OBJ" \
    @"$OUT/sources.txt"

echo "==> [4/6] d8 (dex)"
( cd "$OBJ" && jar cf "$OUT/classes.jar" . )
"$D8" "$OUT/classes.jar" \
    --min-api 21 \
    --lib "$PLATFORM" \
    --output "$DEX"

echo "==> [5/6] assemble + zipalign"
# Add classes.dex into the aapt2-produced base APK
cp "$OUT/base.apk" "$OUT/unaligned.apk"
( cd "$DEX" && zip -q "$OUT/unaligned.apk" classes.dex )
"$ZIPALIGN" -f -p 4 "$OUT/unaligned.apk" "$OUT/aligned.apk"

echo "==> [6/6] sign (debug keystore)"
KS="$PROJ/debug.keystore"
if [ ! -f "$KS" ]; then
    keytool -genkeypair -v -keystore "$KS" -storepass android -keypass android \
        -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "CN=Android Debug,O=Android,C=US"
fi
"$APKSIGNER" sign \
    --ks "$KS" --ks-pass pass:android --key-pass pass:android \
    --ks-key-alias androiddebugkey \
    --min-sdk-version 21 \
    --out "$OUT/Moonrider-debug.apk" \
    "$OUT/aligned.apk"

"$APKSIGNER" verify --verbose "$OUT/Moonrider-debug.apk" | head -8

echo ""
echo "==> DONE: $OUT/Moonrider-debug.apk"
ls -lh "$OUT/Moonrider-debug.apk"

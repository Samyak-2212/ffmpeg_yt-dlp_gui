#!/usr/bin/env bash
# package-release.sh — Package built .so files into distributable zip archives
#
# Creates per-ABI zip files suitable for:
#   1. GitHub Releases (downloaded at runtime by FFmpegLoader.kt)
#   2. Direct inclusion in the main Android_yt-dlp_GUI app as assets
#
# Run after build.sh has completed successfully.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"
RELEASE_DIR="$SCRIPT_DIR/release"
VERSION="9.1"

mkdir -p "$RELEASE_DIR"

echo "=== Packaging FFmpeg Android $VERSION release ==="
echo ""

ABIS=("arm64-v8a" "armeabi-v7a" "x86_64")
TOTAL_SIZE=0

for abi in "${ABIS[@]}"; do
    LIB_DIR="$OUTPUT_DIR/$abi/lib"
    if [[ ! -d "$LIB_DIR" ]]; then
        echo "  [SKIP] $abi — no output found at $LIB_DIR"
        continue
    fi

    ZIP_NAME="ffmpeg-android-$VERSION-$abi.zip"
    ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"

    echo "  Packaging $abi..."

    # Count and list .so files
    SO_COUNT=$(find "$LIB_DIR" -name "*.so" | wc -l)
    echo "    Found $SO_COUNT .so files:"
    find "$LIB_DIR" -name "*.so" | sort | while read -r f; do
        size=$(du -h "$f" | cut -f1)
        echo "      $size  $(basename "$f")"
    done

    # Create zip (flat — no subdirectory)
    cd "$LIB_DIR"
    zip -9 "$ZIP_PATH" ./*.so
    cd "$SCRIPT_DIR"

    ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
    echo "    → $ZIP_NAME ($ZIP_SIZE)"
    echo ""
done

# Also create a combined zip with all ABIs (jniLibs structure)
COMBINED_ZIP="$RELEASE_DIR/ffmpeg-android-$VERSION-all-abis.zip"
echo "  Creating combined jniLibs archive..."

TEMP_DIR="$RELEASE_DIR/tmp_jnilibs"
mkdir -p "$TEMP_DIR"

for abi in "${ABIS[@]}"; do
    LIB_DIR="$OUTPUT_DIR/$abi/lib"
    if [[ -d "$LIB_DIR" ]]; then
        mkdir -p "$TEMP_DIR/jniLibs/$abi"
        cp "$LIB_DIR"/*.so "$TEMP_DIR/jniLibs/$abi/" 2>/dev/null || true
    fi
done

cd "$TEMP_DIR"
zip -9 -r "$COMBINED_ZIP" jniLibs/
cd "$SCRIPT_DIR"
rm -rf "$TEMP_DIR"

echo "    → ffmpeg-android-$VERSION-all-abis.zip ($(du -h "$COMBINED_ZIP" | cut -f1))"

# Generate checksums
echo ""
echo "  Generating SHA256 checksums..."
cd "$RELEASE_DIR"
sha256sum ffmpeg-android-$VERSION*.zip > "ffmpeg-android-$VERSION-checksums.txt" 2>/dev/null || \
    openssl dgst -sha256 ffmpeg-android-$VERSION*.zip > "ffmpeg-android-$VERSION-checksums.txt"
echo "    → ffmpeg-android-$VERSION-checksums.txt"

# Summary
echo ""
echo "=== Release packages ready in: $RELEASE_DIR ==="
ls -lh "$RELEASE_DIR"
echo ""
echo "Next steps:"
echo "  1. Upload zip files to GitHub Releases as tag '9.1'"
echo "  2. Update FFmpegLoader.RELEASES_BASE URL if needed"
echo "  3. Or copy jniLibs/ contents to the main Android app's jniLibs/"

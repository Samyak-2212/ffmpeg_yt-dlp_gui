#!/usr/bin/env bash
# build-jni-wrapper.sh — Build libffmpeg_jni.so (JNI bridge + fftools)
#
# Compiles ffmpeg_jni.c + all fftools/*.c sources into libffmpeg_jni.so,
# linked against the pre-built FFmpeg shared libs from build.sh.
#
# KEY: All fftools sources MUST be in the SAME .so as ffmpeg_jni.c because
# they share file-scope globals (received_nb_signals, nb_input_files, etc.)
#
# Prerequisites:
#   - build.sh must have run first (output/<abi>/lib/*.so must exist)
#   - NDK r27c at /c/android-ndk-r27c (or NDK_HOME env var)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config/env.sh" 2>/dev/null || true

NDK_HOME="${NDK_HOME:-/c/android-ndk-r27c}"
ANDROID_MIN_API="${ANDROID_MIN_API:-24}"
FFMPEG_SRC="${FFMPEG_SRC:-$(dirname "$SCRIPT_DIR")/ffmpeg-9.1}"
OUTPUT_DIR="$SCRIPT_DIR/output"
JNI_DIR="$SCRIPT_DIR/jni"

ABIS=("arm64-v8a" "armeabi-v7a" "x86_64")

[[ -d "$NDK_HOME" ]] || { echo "ERROR: NDK not found at $NDK_HOME"; exit 1; }
[[ -f "$FFMPEG_SRC/fftools/ffmpeg.c" ]] || { echo "ERROR: fftools not found at $FFMPEG_SRC/fftools"; exit 1; }

TOOLCHAIN="$NDK_HOME/toolchains/llvm/prebuilt/windows-x86_64"

# fftools source files (all compiled into libffmpeg_jni.so)
FFTOOLS_SOURCES=(
    "$FFMPEG_SRC/fftools/ffmpeg.c"
    "$FFMPEG_SRC/fftools/ffmpeg_opt.c"
    "$FFMPEG_SRC/fftools/ffmpeg_dec.c"
    "$FFMPEG_SRC/fftools/ffmpeg_demux.c"
    "$FFMPEG_SRC/fftools/ffmpeg_enc.c"
    "$FFMPEG_SRC/fftools/ffmpeg_filter.c"
    "$FFMPEG_SRC/fftools/ffmpeg_hw.c"
    "$FFMPEG_SRC/fftools/ffmpeg_mux.c"
    "$FFMPEG_SRC/fftools/ffmpeg_mux_init.c"
    "$FFMPEG_SRC/fftools/ffmpeg_sched.c"
    "$FFMPEG_SRC/fftools/cmdutils.c"
    "$FFMPEG_SRC/fftools/opt_common.c"
    "$FFMPEG_SRC/fftools/sync_queue.c"
    "$FFMPEG_SRC/fftools/thread_queue.c"
)

build_jni_for_abi() {
    local ABI="$1"
    local LIB_OUT="$OUTPUT_DIR/$ABI/lib"
    local FFMPEG_INCLUDE="$OUTPUT_DIR/$ABI/include"

    if [[ ! -d "$LIB_OUT" ]]; then
        echo "  [SKIP] $ABI — no FFmpeg libs at $LIB_OUT (run build.sh first)"
        return
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Building libffmpeg_jni.so for: $ABI"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    case "$ABI" in
        arm64-v8a)   TRIPLE="aarch64-linux-android"    ;;
        armeabi-v7a) TRIPLE="armv7a-linux-androideabi" ;;
        x86_64)      TRIPLE="x86_64-linux-android"     ;;
        *) echo "Unknown ABI: $ABI"; return 1 ;;
    esac

    local CC="$TOOLCHAIN/bin/${TRIPLE}${ANDROID_MIN_API}-clang"
    [[ -f "$CC" ]] || { echo "ERROR: Compiler not found: $CC"; exit 1; }
    echo "  CC: $CC"

    local ABI_BUILD_DIR="$SCRIPT_DIR/build/$ABI"
    local OUTPUT_SO="$LIB_OUT/libffmpeg_jni.so"

    # Compile all sources in one clang invocation
    "$CC" \
        -shared \
        -fPIC \
        -Os \
        -ffunction-sections \
        -fdata-sections \
        -std=c17 \
        -Wall \
        -Wno-deprecated-declarations \
        -Wno-unused-parameter \
        \
        -DANDROID \
        -Dmain=ffmpeg_main \
        -D_ISOC11_SOURCE \
        -D_FILE_OFFSET_BITS=64 \
        -D_LARGEFILE_SOURCE \
        \
        -I"$ABI_BUILD_DIR" \
        -I"$FFMPEG_INCLUDE" \
        -I"$FFMPEG_SRC" \
        -I"$FFMPEG_SRC/fftools" \
        -I"$FFMPEG_SRC/compat/stdbit" \
        \
        "$JNI_DIR/ffmpeg_jni.c" \
        "${FFTOOLS_SOURCES[@]}" \
        \
        -L"$LIB_OUT" \
        -lavfilter \
        -lavformat \
        -lavcodec \
        -lswscale \
        -lswresample \
        -lavutil \
        -llog \
        -landroid \
        -lm \
        -ldl \
        -lz \
        \
        -Wl,--build-id=sha1 \
        -Wl,--no-undefined \
        -Wl,--gc-sections \
        "-Wl,-z,max-page-size=16384" \
        \
        -o "$OUTPUT_SO"

    # Strip debug symbols
    "$TOOLCHAIN/bin/llvm-strip" --strip-unneeded "$OUTPUT_SO"

    local SIZE
    SIZE=$(du -h "$OUTPUT_SO" | cut -f1)
    echo "  [OK] $OUTPUT_SO ($SIZE)"

    # Copy to jniLibs
    local JNILIB_DEST="$SCRIPT_DIR/android-lib/src/main/jniLibs/$ABI"
    mkdir -p "$JNILIB_DEST"
    cp "$OUTPUT_SO" "$JNILIB_DEST/"
    echo "  Copied to jniLibs/$ABI/libffmpeg_jni.so"
}

echo "=== Building FFmpeg JNI wrapper ==="
echo "NDK:         $NDK_HOME"
echo "FFmpeg src:  $FFMPEG_SRC"
echo "Output:      $OUTPUT_DIR"

for abi in "${ABIS[@]}"; do
    build_jni_for_abi "$abi"
done

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  JNI wrapper build complete!"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  jniLibs are ready:"
find "$SCRIPT_DIR/android-lib/src/main/jniLibs" -name "*.so" 2>/dev/null | sort | while read -r f; do
    printf "    %-12s  %s\n" "$(du -h "$f" | cut -f1)" "${f/$SCRIPT_DIR\//}"
done
echo ""
echo "  Next: Build the AAR:"
echo "    cd android-lib && ./gradlew assembleRelease"

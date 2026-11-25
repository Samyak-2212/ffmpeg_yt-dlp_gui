#!/usr/bin/env bash
# build.sh — FFmpeg 9.0.2 Android cross-compilation
#
# Builds FFmpeg as shared libraries (.so) for Android ARM targets.
# Run from MSYS2 (MSYS shell, NOT MinGW64/UCRT64) on Windows.
#
# Usage:
#   ./build.sh                    # Build all ABIs
#   ./build.sh --abi=arm64-v8a   # Single ABI
#   ./build.sh --abi=armeabi-v7a
#   ./build.sh --abi=x86_64
#   ./build.sh --clean
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source environment config (written by setup-env.ps1)
ENV_FILE="$SCRIPT_DIR/config/env.sh"
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
fi

# Paths — override via config/env.sh or environment
NDK_HOME="${NDK_HOME:-/c/android-ndk-r27c}"
FFMPEG_SRC="${FFMPEG_SRC:-/c/Users/naska/OneDrive/Documents/GitHub/ffmpeg-9.1}"
BUILD_ROOT="${BUILD_ROOT:-$SCRIPT_DIR}"
ANDROID_MIN_API="${ANDROID_MIN_API:-24}"

BUILD_DIR="$BUILD_ROOT/build"
OUTPUT_DIR="$BUILD_ROOT/output"
TOOLCHAIN="$NDK_HOME/toolchains/llvm/prebuilt/windows-x86_64"
SYSROOT="$TOOLCHAIN/sysroot"

# ─────────────────────────────────────────────────────────────────────────────
# Parse args
# ─────────────────────────────────────────────────────────────────────────────
BUILD_ABI=""
DO_CLEAN=false
for arg in "$@"; do
    case "$arg" in
        --abi=*)    BUILD_ABI="${arg#--abi=}" ;;
        --clean)    DO_CLEAN=true ;;
        --ndk=*)    NDK_HOME="${arg#--ndk=}"; TOOLCHAIN="$NDK_HOME/toolchains/llvm/prebuilt/windows-x86_64" ;;
        --api=*)    ANDROID_MIN_API="${arg#--api=}" ;;
        -h|--help)  echo "Usage: $0 [--abi=arm64-v8a|armeabi-v7a|x86_64] [--clean] [--ndk=PATH] [--api=LEVEL]"; exit 0 ;;
        *)          echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

if $DO_CLEAN; then
    echo "Cleaning $BUILD_DIR ..."; rm -rf "$BUILD_DIR"; echo "Done."; exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Validation
# ─────────────────────────────────────────────────────────────────────────────
[[ -d "$NDK_HOME" ]]            || { echo "ERROR: NDK not found at $NDK_HOME (run setup-env.ps1)"; exit 1; }
[[ -f "$FFMPEG_SRC/configure" ]] || { echo "ERROR: FFmpeg source not at $FFMPEG_SRC"; exit 1; }
[[ -d "$TOOLCHAIN" ]]           || { echo "ERROR: NDK toolchain not found: $TOOLCHAIN"; exit 1; }

for tool in make nasm pkg-config; do
    command -v "$tool" &>/dev/null || { echo "ERROR: '$tool' not found — run setup-env.ps1"; exit 1; }
done

echo "=== FFmpeg 9.1 Android Build ==="
echo "NDK:        $NDK_HOME"
echo "Toolchain:  $TOOLCHAIN"
echo "FFmpeg src: $FFMPEG_SRC"
echo "Min API:    $ANDROID_MIN_API"
echo "Output:     $OUTPUT_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# Build function
# ─────────────────────────────────────────────────────────────────────────────
build_abi() {
    local ABI="$1"
    local ABI_BUILD="$BUILD_DIR/$ABI"
    local ABI_OUT="$OUTPUT_DIR/$ABI"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Building: $ABI"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    source "$SCRIPT_DIR/config/build-${ABI}.sh"

    local CC="$TOOLCHAIN/bin/${CLANG_TARGET}${ANDROID_MIN_API}-clang"
    local CXX="$TOOLCHAIN/bin/${CLANG_TARGET}${ANDROID_MIN_API}-clang++"

    [[ -f "$CC" ]] || { echo "ERROR: Compiler not found: $CC"; exit 1; }
    echo "  CC: $CC"

    mkdir -p "$ABI_BUILD" "$ABI_OUT"

    # ─── configure ────────────────────────────────────────────────────────────
    pushd "$ABI_BUILD" > /dev/null

    "$FFMPEG_SRC/configure" \
        --prefix="$ABI_OUT" \
        --target-os=android \
        --arch="${FFMPEG_ARCH}" \
        --cpu="${FFMPEG_CPU}" \
        --enable-cross-compile \
        --cross-prefix="$TOOLCHAIN/bin/llvm-" \
        --cc="$CC" \
        --cxx="$CXX" \
        --ar="$TOOLCHAIN/bin/llvm-ar" \
        --ranlib="$TOOLCHAIN/bin/llvm-ranlib" \
        --strip="$TOOLCHAIN/bin/llvm-strip" \
        --nm="$TOOLCHAIN/bin/llvm-nm" \
        --sysroot="$SYSROOT" \
        \
        --enable-shared \
        --disable-static \
        --disable-programs \
        --disable-doc \
        --disable-avdevice \
        --disable-debug \
        --enable-pic \
        --enable-pthreads \
        \
        --disable-everything \
        \
        --enable-decoder=h264 \
        --enable-decoder=hevc \
        --enable-decoder=vp8 \
        --enable-decoder=vp9 \
        --enable-decoder=av1 \
        --enable-decoder=aac \
        --enable-decoder=aac_latm \
        --enable-decoder=mp3 \
        --enable-decoder=mp3float \
        --enable-decoder=flac \
        --enable-decoder=opus \
        --enable-decoder=vorbis \
        --enable-decoder=alac \
        --enable-decoder=pcm_s16le \
        --enable-decoder=pcm_s24le \
        --enable-decoder=pcm_s32le \
        --enable-decoder=pcm_f32le \
        --enable-decoder=pcm_u8 \
        --enable-decoder=srt \
        --enable-decoder=subrip \
        --enable-decoder=ass \
        --enable-decoder=ssa \
        --enable-decoder=webvtt \
        --enable-decoder=movtext \
        --enable-decoder=mjpeg \
        --enable-decoder=png \
        --enable-decoder=webp \
        \
        --enable-encoder=aac \
        --enable-encoder=flac \
        --enable-encoder=opus \
        --enable-encoder=alac \
        --enable-encoder=pcm_s16le \
        --enable-encoder=pcm_f32le \
        --enable-encoder=srt \
        --enable-encoder=subrip \
        --enable-encoder=ass \
        --enable-encoder=ssa \
        --enable-encoder=webvtt \
        --enable-encoder=movtext \
        --enable-encoder=mjpeg \
        --enable-encoder=png \
        \
        --enable-parser=h264 \
        --enable-parser=hevc \
        --enable-parser=vp8 \
        --enable-parser=vp9 \
        --enable-parser=av1 \
        --enable-parser=aac \
        --enable-parser=aac_latm \
        --enable-parser=flac \
        --enable-parser=opus \
        --enable-parser=vorbis \
        --enable-parser=mpegaudio \
        --enable-parser=mjpeg \
        --enable-parser=png \
        --enable-parser=webp \
        \
        --enable-demuxer=mov \
        --enable-demuxer=matroska \
        --enable-demuxer=ogg \
        --enable-demuxer=aac \
        --enable-demuxer=mp3 \
        --enable-demuxer=flac \
        --enable-demuxer=wav \
        --enable-demuxer=concat \
        --enable-demuxer=data \
        --enable-demuxer=srt \
        --enable-demuxer=ass \
        --enable-demuxer=webvtt \
        --enable-demuxer=image2 \
        --enable-demuxer=image_png_pipe \
        --enable-demuxer=image_webp_pipe \
        --enable-demuxer=mjpeg \
        \
        --enable-muxer=mp4 \
        --enable-muxer=mov \
        --enable-muxer=ipod \
        --enable-muxer=matroska \
        --enable-muxer=webm \
        --enable-muxer=ogg \
        --enable-muxer=opus \
        --enable-muxer=flac \
        --enable-muxer=mp3 \
        --enable-muxer=wav \
        --enable-muxer=adts \
        --enable-muxer=data \
        --enable-muxer=srt \
        --enable-muxer=ass \
        --enable-muxer=webvtt \
        --enable-muxer=image2 \
        --enable-muxer=mjpeg \
        \
        --enable-filter=aresample \
        --enable-filter=aformat \
        --enable-filter=anull \
        --enable-filter=atrim \
        --enable-filter=volume \
        --enable-filter=pan \
        --enable-filter=concat \
        --enable-filter=null \
        --enable-filter=trim \
        --enable-filter=setpts \
        --enable-filter=format \
        --enable-filter=scale \
        \
        --enable-protocol=file \
        --enable-protocol=pipe \
        --enable-protocol=data \
        --enable-protocol=cache \
        --enable-protocol=concat \
        \
        --enable-bsf=aac_adtstoasc \
        --enable-bsf=h264_mp4toannexb \
        --enable-bsf=hevc_mp4toannexb \
        --enable-bsf=vp9_superframe \
        --enable-bsf=vp9_superframe_split \
        --enable-bsf=text2movsub \
        --enable-bsf=mov2textsub \
        --enable-bsf=mjpeg2jpeg \
        --enable-bsf=setts \
        \
        --disable-hwaccels \
        --disable-network \
        \
        --extra-cflags="${EXTRA_CFLAGS} -fPIC -DANDROID -Os -ffunction-sections -fdata-sections" \
        --extra-ldflags="${EXTRA_LDFLAGS} -Wl,--build-id=sha1 -Wl,--no-undefined -Wl,--gc-sections -Wl,-z,max-page-size=16384" \
        --extra-libs="-lm -lz -ldl" \
        2>&1 | tee configure.log

    local cfg_exit=${PIPESTATUS[0]}
    if [[ $cfg_exit -ne 0 ]]; then
        echo ""; echo "ERROR: configure failed for $ABI (exit $cfg_exit)"
        echo "  See: $ABI_BUILD/configure.log"
        # Print last relevant error lines
        grep -E "(Unknown option|error:|ERROR)" configure.log | tail -5 || true
        exit 1
    fi

    # ─── make ─────────────────────────────────────────────────────────────────
    echo ""; echo "  Compiling ($(nproc) jobs)..."
    make -j"$(nproc)" 2>&1 | tee build.log
    local make_exit=${PIPESTATUS[0]}
    if [[ $make_exit -ne 0 ]]; then
        echo ""; echo "ERROR: make failed for $ABI"
        grep -E "^.*error:" build.log | tail -10 || true
        exit 1
    fi

    make install 2>&1 | tee install.log
    popd > /dev/null

    # ─── Strip & report ───────────────────────────────────────────────────────
    echo ""; echo "  Stripping debug symbols..."
    find "$ABI_OUT/lib" -name "*.so" -exec "$TOOLCHAIN/bin/llvm-strip" --strip-unneeded {} \;

    echo ""; echo "  [OK] $ABI → $ABI_OUT/lib/"
    find "$ABI_OUT/lib" -name "*.so" | sort | while read -r f; do
        printf "       %-12s  %s\n" "$(du -h "$f" | cut -f1)" "$(basename "$f")"
    done

    # Copy to android-lib jniLibs for AAR bundling
    local JNILIB_DEST="$BUILD_ROOT/android-lib/src/main/jniLibs/$ABI"
    mkdir -p "$JNILIB_DEST"
    find "$ABI_OUT/lib" -name "*.so" -exec cp {} "$JNILIB_DEST/" \;
    echo "  Copied to jniLibs/$ABI/"
}

# ─────────────────────────────────────────────────────────────────────────────
# Run
# ─────────────────────────────────────────────────────────────────────────────
ALL_ABIS=("arm64-v8a" "armeabi-v7a" "x86_64")

if [[ -n "$BUILD_ABI" ]]; then
    [[ " ${ALL_ABIS[*]} " =~ " $BUILD_ABI " ]] || { echo "Unknown ABI: $BUILD_ABI"; exit 1; }
    build_abi "$BUILD_ABI"
else
    for abi in "${ALL_ABIS[@]}"; do build_abi "$abi"; done
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  FFmpeg shared libraries built successfully!"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  Next steps:"
echo "    1. Build JNI wrapper:   ./build-jni-wrapper.sh"
echo "    2. Or build full AAR:   cd android-lib && ./gradlew assembleRelease"
echo "    3. Package release:     ./package-release.sh"

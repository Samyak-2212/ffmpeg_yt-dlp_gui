#!/usr/bin/env bash
# config/build-armeabi-v7a.sh — ABI configuration for ARMv7 (armeabi-v7a)
# Sourced by build.sh

# Clang target triple for NDK r27+
CLANG_TARGET="armv7a-linux-androideabi"

# FFmpeg arch/cpu
FFMPEG_ARCH="arm"
FFMPEG_CPU="armv7-a"

# Extra compiler flags — thumb2 + NEON for ARMv7
EXTRA_CFLAGS="-march=armv7-a -mfpu=neon -mfloat-abi=softfp -mthumb"
EXTRA_LDFLAGS="-march=armv7-a -Wl,--fix-cortex-a8"

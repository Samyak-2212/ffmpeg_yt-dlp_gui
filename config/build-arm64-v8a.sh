#!/usr/bin/env bash
# config/build-arm64-v8a.sh — ABI configuration for ARM64 (arm64-v8a)
# Sourced by build.sh

# Clang target triple for NDK r27+
CLANG_TARGET="aarch64-linux-android"

# FFmpeg arch/cpu
FFMPEG_ARCH="aarch64"
FFMPEG_CPU="armv8-a"

# Extra compiler flags
EXTRA_CFLAGS="-march=armv8-a"
EXTRA_LDFLAGS=""

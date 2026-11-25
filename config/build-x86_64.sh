#!/usr/bin/env bash
# config/build-x86_64.sh — ABI configuration for x86_64 (emulator)
# Sourced by build.sh

# Clang target triple for NDK r27+
CLANG_TARGET="x86_64-linux-android"

# FFmpeg arch/cpu
FFMPEG_ARCH="x86_64"
FFMPEG_CPU="x86-64"

# Extra compiler flags
# Disable assembly for x86_64 on MSYS2 (nasm path issues on Windows)
EXTRA_CFLAGS="-march=x86-64"
EXTRA_LDFLAGS=""

# CMakeLists.txt — FFmpeg 9.0.2 JNI wrapper for Android
#
# Builds libffmpeg_jni.so which contains:
#   1. All fftools/*.c sources (compiled with -Dmain=ffmpeg_main)
#   2. ffmpeg_jni.c (the JNI bridge)
#
# Linked against the pre-built FFmpeg shared libraries produced by build.sh.
#
# IMPORTANT: All fftools sources MUST be compiled into the same shared library
# as the JNI bridge, because fftools/*.c share file-scope globals:
#   nb_input_files, nb_output_files, input_files[], output_files[],
#   received_nb_signals, transcode_init_done, etc.
# Splitting them into a static lib that's then linked into the shared lib
# also works, but a separate .so would have its own copy of these globals
# (wrong behavior).
#
# Variable set by Android Gradle CMake integration:
#   ANDROID_ABI     → "arm64-v8a", "armeabi-v7a", "x86_64"
#   ANDROID_PLATFORM → "android-24"
#   CMAKE_ANDROID_NDK → path to NDK

cmake_minimum_required(VERSION 3.22.1)
project(ffmpeg_jni C)

set(CMAKE_C_STANDARD 11)

# ─────────────────────────────────────────────────────────────────────────────
# Paths
# ─────────────────────────────────────────────────────────────────────────────

# Pre-built FFmpeg .so and headers (produced by build.sh)
# CMakeLists.txt is at ffmpeg_yt-dlp_gui/jni/
# output/ is at ffmpeg_yt-dlp_gui/output/  → one level up: ../output/
set(FFMPEG_OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../output/${ANDROID_ABI}")
set(FFMPEG_INCLUDE_DIR "${FFMPEG_OUTPUT_DIR}/include")
set(FFMPEG_LIB_DIR "${FFMPEG_OUTPUT_DIR}/lib")

# FFmpeg 9.0.2 source tree (for compiling fftools/)
# CMakeLists.txt is at ffmpeg_yt-dlp_gui/jni/
# ffmpeg-9.0.2 is at GitHub/ffmpeg-9.0.2/ (sibling of ffmpeg_yt-dlp_gui)
# → ../.. goes up to GitHub/
set(FFMPEG_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../ffmpeg-9.1")

message(STATUS "=== FFmpeg JNI CMake Configuration ===")
message(STATUS "ABI:           ${ANDROID_ABI}")
message(STATUS "Platform:      ${ANDROID_PLATFORM}")
message(STATUS "FFmpeg output: ${FFMPEG_OUTPUT_DIR}")
message(STATUS "FFmpeg src:    ${FFMPEG_SRC_DIR}")

# ─────────────────────────────────────────────────────────────────────────────
# Import pre-built FFmpeg shared libraries as IMPORTED targets
# ─────────────────────────────────────────────────────────────────────────────

foreach(LIB avutil swresample swscale avcodec avformat avfilter)
    add_library(${LIB} SHARED IMPORTED)
    set_target_properties(${LIB} PROPERTIES
        IMPORTED_LOCATION "${FFMPEG_LIB_DIR}/lib${LIB}.so"
    )
endforeach()

# ─────────────────────────────────────────────────────────────────────────────
# fftools sources — compiled together with the JNI bridge
#
# We use -Dmain=ffmpeg_main to rename main() without patching FFmpeg source.
# ffmpeg_sched.c is new in FFmpeg 9.x (replaces older thread_queue.c usage).
# ─────────────────────────────────────────────────────────────────────────────

set(FFTOOLS_SOURCES
    "${FFMPEG_SRC_DIR}/fftools/ffmpeg.c"
    "${FFMPEG_SRC_DIR}/fftools/ffmpeg_opt.c"
    "${FFMPEG_SRC_DIR}/fftools/ffmpeg_dec.c"
    "${FFMPEG_SRC_DIR}/fftools/ffmpeg_demux.c"
    "${FFMPEG_SRC_DIR}/fftools/ffmpeg_enc.c"
    "${FFMPEG_SRC_DIR}/fftools/ffmpeg_filter.c"
    "${FFMPEG_SRC_DIR}/fftools/ffmpeg_hw.c"
    "${FFMPEG_SRC_DIR}/fftools/ffmpeg_mux.c"
    "${FFMPEG_SRC_DIR}/fftools/ffmpeg_mux_init.c"
    "${FFMPEG_SRC_DIR}/fftools/ffmpeg_sched.c"
    "${FFMPEG_SRC_DIR}/fftools/cmdutils.c"
    "${FFMPEG_SRC_DIR}/fftools/opt_common.c"
    "${FFMPEG_SRC_DIR}/fftools/sync_queue.c"
    "${FFMPEG_SRC_DIR}/fftools/thread_queue.c"
    # ffplay_renderer.c, ffplay.c, ffprobe.c are NOT included (not needed)
)

# Validate all sources exist
foreach(SRC ${FFTOOLS_SOURCES})
    if(NOT EXISTS "${SRC}")
        message(FATAL_ERROR "FFtools source not found: ${SRC}\n"
            "Expected FFmpeg 9.0.2 source at: ${FFMPEG_SRC_DIR}")
    endif()
endforeach()

# ─────────────────────────────────────────────────────────────────────────────
# libffmpeg_jni.so — JNI bridge + fftools compiled into one shared library
# ─────────────────────────────────────────────────────────────────────────────

add_library(ffmpeg_jni SHARED
    "${CMAKE_CURRENT_SOURCE_DIR}/ffmpeg_jni.c"
    ${FFTOOLS_SOURCES}
)

target_include_directories(ffmpeg_jni PRIVATE
    "${FFMPEG_INCLUDE_DIR}"
    "${FFMPEG_SRC_DIR}"
    "${FFMPEG_SRC_DIR}/fftools"
)

target_compile_definitions(ffmpeg_jni PRIVATE
    # Rename main() → ffmpeg_main() without patching FFmpeg source
    main=ffmpeg_main
    # Android-specific
    ANDROID
    __ANDROID_API__=24
)

target_compile_options(ffmpeg_jni PRIVATE
    -Wall
    -Wextra
    -Wno-deprecated-declarations
    -Wno-unused-parameter
    -fPIC
    -Os
    -ffunction-sections
    -fdata-sections
    # Required for Android 15+ (API 35) 16KB page size enforcement
    -DANDROID_MIN_SDK_VERSION=24
)

# System libraries
find_library(LOG_LIB log)
find_library(ANDROID_LIB android)
find_library(MEDIANDK_LIB mediandk)

target_link_libraries(ffmpeg_jni PRIVATE
    # FFmpeg shared libs (dependency order matters for dlopen)
    avfilter
    avformat
    avcodec
    swscale
    swresample
    avutil
    # Android system
    ${LOG_LIB}
    ${ANDROID_LIB}
    # mediandk is optional (for MediaCodec HW decode, disabled in our build)
    # ${MEDIANDK_LIB}
    # POSIX
    m
    z
    dl
)

target_link_options(ffmpeg_jni PRIVATE
    # Embed build ID for crash symbolication
    -Wl,--build-id=sha1
    # Error on undefined symbols (catches missing FFmpeg API early)
    -Wl,--no-undefined
    # Dead-code elimination
    -Wl,--gc-sections
    # 16KB page alignment — mandatory for Android 15+ (API 35) devices
    # NDK r27+ generates this by default, but explicit is safer
    -Wl,-z,max-page-size=16384
)

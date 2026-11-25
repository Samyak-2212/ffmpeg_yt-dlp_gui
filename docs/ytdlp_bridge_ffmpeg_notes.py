"""
ytdlp_bridge_ffmpeg.py — Updated Python bridge using JNI FFmpeg instead of binary

This is a drop-in replacement for ytdlp_bridge.py that uses the JNI-based
FFmpeg (via FFmpegBridge.kt) instead of a downloaded binary executable.

Changes from original ytdlp_bridge.py:
  - ffmpeg_path is now the jniLibsDir path (not a binary path)
  - ydl_opts uses a custom FFmpegPostProcessor that delegates to JNI
  - The format selector is unchanged (still prefers mp4+m4a)

NOTE: This file is NOT the primary implementation — it documents how
yt-dlp's Python bridge is updated. The actual change is in YtDlpEngine.kt
which now calls FFmpegBridge instead of passing a binary path.
"""

# The key change in ydl_opts when using JNI FFmpeg:
#
# OLD (binary):
#   ydl_opts['ffmpeg_location'] = os.path.dirname(ffmpeg_path)
#
# NEW (JNI, no binary needed):
#   ydl_opts['postprocessors'] = [{
#       'key': 'FFmpegMerger',
#       'preferedcodec': None,
#   }]
#   # ffmpeg_location is NOT set — yt-dlp will call our custom post-processor
#
# ALTERNATIVE: Keep using yt-dlp's built-in FFmpegPostProcessor but point
# ffmpeg_location to a shell wrapper script that invokes the JNI bridge.
# This approach avoids any Python-side changes.
#
# The simplest integration: use the JNI FFmpeg for muxing in Kotlin,
# and let yt-dlp download streams separately without merging.
# Then mux in Kotlin using FFmpegBridge.muxToMp4().

BRIDGE_MODE = "separate_download_then_jni_mux"

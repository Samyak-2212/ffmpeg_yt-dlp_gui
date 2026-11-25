# ProGuard rules for ffmpeg-android library
# Keep all JNI-accessible classes and methods

-keep class com.ytdlp.ffmpeg.** { *; }
-keepclassmembers class com.ytdlp.ffmpeg.FFmpegBridge {
    native <methods>;
    public static *;
}
-keepclassmembers class com.ytdlp.ffmpeg.FFmpegLoader {
    public *;
}

# Keep native method names
-keepclasseswithmembernames class * {
    native <methods>;
}

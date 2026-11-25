package com.ytdlp.ffmpeg

import android.content.Context
import android.os.Build
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File

/**
 * FFmpegLoader — Runtime download and loading of FFmpeg shared libraries.
 *
 * This is the **fallback / alternative** to bundling FFmpeg .so files in the APK.
 * It downloads the pre-built .so files from GitHub Releases and loads them
 * via System.load() (absolute path) instead of System.loadLibrary().
 *
 * ## When to use this vs bundled mode
 *
 * | Mode        | APK size    | First run  | Offline support | API 34+ |
 * |-------------|-------------|------------|-----------------|---------|
 * | Bundled AAR | +20-50 MB   | Instant    | Always works    | ✅      |
 * | Runtime DL  | No overhead | Slow (~DL) | Requires net    | ✅*     |
 *
 * *API 34+: .so files must be set read-only before System.load().
 *
 * ## Android API 34+ W^X Policy — Critical Warning
 *
 * On Android 14+ (API 34), `dlopen()` on .so files written to `filesDir` or
 * `cacheDir` at runtime is **blocked by the linker** with:
 *   "W/linker: ... file is not read-only"
 * OR by SELinux with EACCES.
 *
 * **This means runtime-download mode only works on API 24–33.**
 * For API 34+, you MUST use bundled mode (jniLibs in APK).
 *
 * On API 24–33: .so files in filesDir CAN be dlopen'd as long as they are
 * set read-only (`chmod 444`) before loading. This loader enforces that.
 *
 * The bundled APK mode (jniLibs/) is always safe on all API levels because:
 * - Files are extracted by PackageManager to a trusted SELinux context
 * - System.loadLibrary() uses the trusted nativeLibraryDir namespace
 *
 * ## GitHub Release format
 *
 * The releases at github.com/naska-ai/ffmpeg-android-yt-dlp contain:
 *   ffmpeg-android-9.0.2-arm64-v8a.zip   → libavutil.so, libavcodec.so, ...
 *   ffmpeg-android-9.0.2-armeabi-v7a.zip → ...
 *   ffmpeg-android-9.0.2-x86_64.zip      → ...
 *
 * Each zip contains the .so files at the root (no subdirectory).
 */
class FFmpegLoader(
    private val context: Context,
    private val httpClient: OkHttpClient = OkHttpClient()
) {
    private val libDir = File(context.filesDir, "ffmpeg_libs")

    companion object {
        private const val TAG = "FFmpegLoader"

        // GitHub Releases base URL — update when publishing releases
        private const val RELEASES_BASE =
            "https://github.com/Samyak-2212/ffmpeg_yt-dlp_gui/releases/download/v9.1"

        // The .so files to load, in dependency order
        // (each depends on all previous ones)
        val LIBRARY_LOAD_ORDER = listOf(
            "avutil",
            "swresample",
            "swscale",
            "avcodec",
            "avformat",
            "avfilter",
            "ffmpeg_jni"
        )

        // Expected minimum size for a valid .so (anything smaller = corrupt)
        private const val MIN_SO_SIZE_BYTES = 64 * 1024L  // 64 KB
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Check if libraries are already loaded
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Returns true if all FFmpeg .so files are present in the private files dir
     * and appear to be valid (not corrupt).
     */
    fun isReady(): Boolean {
        return LIBRARY_LOAD_ORDER.all { lib ->
            val f = File(libDir, "lib$lib.so")
            f.exists() && f.length() >= MIN_SO_SIZE_BYTES
        }
    }

    /**
     * Returns the directory where .so files are stored.
     */
    fun getLibDir(): File = libDir

    // ─────────────────────────────────────────────────────────────────────────
    // Load pre-existing .so files
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Load FFmpeg .so files from the private files directory.
     * Call this if [isReady] returns true.
     *
     * **API 34+ note:** This method only works on API 24–33. On API 34+,
     * dlopen() to app-private data directories is blocked by the linker.
     * Use bundled mode (AAR with jniLibs) for API 34+ compatibility.
     *
     * Sets files read-only first (required for API 29+ as a best practice,
     * enforced more strictly on API 34+).
     *
     * @throws IllegalStateException if called on API 34+ (use bundled mode).
     * @throws UnsatisfiedLinkError if any .so fails to load.
     */
    fun loadFromFilesDir() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE /* API 34 */) {
            throw IllegalStateException(
                "Runtime .so loading from filesDir is blocked on Android 14+ (API 34+). " +
                "Use FFmpegBridge.init(fromJniLibs = true) with the bundled AAR instead."
            )
        }
        libDir.mkdirs()
        for (lib in LIBRARY_LOAD_ORDER) {
            val file = File(libDir, "lib$lib.so")
            if (!file.exists()) {
                throw UnsatisfiedLinkError("FFmpeg library not found: ${file.absolutePath}")
            }
            // API 34+: .so must be read-only for dlopen to map PROT_EXEC
            makeReadOnly(file)
            Log.d(TAG, "Loading: ${file.absolutePath}")
            System.load(file.absolutePath)
        }
        Log.i(TAG, "All FFmpeg libraries loaded from ${libDir.absolutePath}")
        // Mark bridge as loaded (without System.loadLibrary)
        FFmpegBridge.init(fromJniLibs = false)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Download from GitHub Releases
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Download FFmpeg .so files for the current device ABI from GitHub Releases.
     *
     * @param onProgress Progress callback: (downloadedBytes, totalBytes) → Unit
     * @return Result.success(Unit) on success, Result.failure(e) on error.
     */
    suspend fun downloadLibraries(
        onProgress: (Long, Long) -> Unit = { _, _ -> }
    ): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            val abi = getBestAbi()
            val zipName = "ffmpeg-android-9.1-$abi.zip"
            val url = "$RELEASES_BASE/$zipName"
            val tempZip = File(context.cacheDir, zipName)

            Log.i(TAG, "Downloading FFmpeg libraries for ABI: $abi")
            Log.i(TAG, "URL: $url")

            // Download
            val request = Request.Builder()
                .url(url)
                .header("User-Agent", "YtDlpAndroid/1.0 FFmpegLoader")
                .build()

            val response = httpClient.newCall(request).execute()
            if (!response.isSuccessful) {
                return@withContext Result.failure(
                    Exception("HTTP ${response.code} downloading $url")
                )
            }

            val body = response.body
                ?: return@withContext Result.failure(Exception("Empty response body"))

            val total = body.contentLength()
            var downloaded = 0L

            body.byteStream().use { input ->
                tempZip.outputStream().use { output ->
                    val buffer = ByteArray(8192)
                    var read: Int
                    while (input.read(buffer).also { read = it } >= 0) {
                        output.write(buffer, 0, read)
                        downloaded += read
                        onProgress(downloaded, total)
                    }
                }
            }

            Log.i(TAG, "Download complete: ${tempZip.length()} bytes")

            // Extract
            libDir.mkdirs()
            extractZip(tempZip, libDir)
            tempZip.delete()

            // Validate
            for (lib in LIBRARY_LOAD_ORDER) {
                val f = File(libDir, "lib$lib.so")
                if (!f.exists() || f.length() < MIN_SO_SIZE_BYTES) {
                    return@withContext Result.failure(
                        Exception("lib$lib.so missing or too small after extraction")
                    )
                }
                makeReadOnly(f)
            }

            Log.i(TAG, "FFmpeg libraries ready at ${libDir.absolutePath}")
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "Download failed", e)
            Result.failure(e)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Select the best ABI for the current device.
     * Prefer 64-bit ARM, fall back to 32-bit ARM.
     */
    private fun getBestAbi(): String {
        val supportedAbis = Build.SUPPORTED_ABIS
        return when {
            supportedAbis.contains("arm64-v8a") -> "arm64-v8a"
            supportedAbis.contains("x86_64")    -> "x86_64"
            else                                 -> "armeabi-v7a"
        }
    }

    /**
     * Set a file read-only.
     *
     * On Android 14+ (API 34), dynamically loaded native code must be
     * read-only. This is a strict requirement — loadLibrary will fail with
     * "W/linker: ... file is writable" on API 34+ if not enforced.
     *
     * Note: We use setReadable(true)/setWritable(false) rather than
     * file.setReadOnly() because setReadOnly() on Android also affects
     * group/other permissions inconsistently across API levels.
     */
    private fun makeReadOnly(file: File) {
        file.setReadable(true, false)   // owner + group + other: readable
        file.setWritable(false, false)  // nobody: writable
        file.setExecutable(false, false) // nobody needs +x for dlopen
        Log.d(TAG, "Set read-only: ${file.name} (${file.length()} bytes)")
    }

    /**
     * Extract a zip file to a destination directory.
     * Uses Java's ZipInputStream (available on all Android API levels).
     */
    private fun extractZip(zipFile: File, destDir: File) {
        java.util.zip.ZipInputStream(zipFile.inputStream().buffered()).use { zis ->
            var entry = zis.nextEntry
            while (entry != null) {
                if (!entry.isDirectory) {
                    val outFile = File(destDir, entry.name.substringAfterLast('/'))
                    outFile.parentFile?.mkdirs()
                    outFile.outputStream().use { out ->
                        zis.copyTo(out)
                    }
                    Log.d(TAG, "Extracted: ${outFile.name} (${outFile.length()} bytes)")
                }
                zis.closeEntry()
                entry = zis.nextEntry
            }
        }
    }
}

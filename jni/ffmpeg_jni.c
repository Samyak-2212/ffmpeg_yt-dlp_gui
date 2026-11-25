/*
 * ffmpeg_jni.c — JNI wrapper for FFmpeg 9.0.2
 *
 * Wraps fftools/ffmpeg.c main() as a callable JNI function using a simple
 * rename (#define main ffmpeg_main). No patching of FFmpeg source required.
 *
 * Cancellation uses FFmpeg's actual mechanism: raise(SIGINT), which triggers
 * the installed sigterm_handler() in ffmpeg.c. Once received_nb_signals > 0
 * and transcode_init_done == 1, the interrupt callback fires and the transcode
 * loop exits cleanly.
 *
 * Thread safety: ffmpeg_main() uses file-scope globals (nb_input_files, etc.)
 * shared across all fftools C sources. A mutex serializes calls. For concurrent
 * downloads, the yt-dlp Python bridge already sequences mux operations.
 *
 * JNI API (Kotlin package: com.ytdlp.ffmpeg):
 *   FFmpegBridge.nativeRunFFmpeg(args: Array<String>): Int
 *   FFmpegBridge.nativeCancelFFmpeg()
 *   FFmpegBridge.nativeGetFFmpegVersion(): String
 *
 * Build: Compiled by CMakeLists.txt along with all fftools C sources.
 */

#include <jni.h>
#include <android/log.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
#include <pthread.h>
#include <stdatomic.h>

/* ─────────────────────────────────────────────────────────────────────────── */
/* FFmpeg API declarations — resolved from linked shared libs                  */
/* ─────────────────────────────────────────────────────────────────────────── */

extern const char *av_version_info(void);
extern unsigned avutil_version(void);
extern unsigned avcodec_version(void);
extern unsigned avformat_version(void);

/*
 * ffmpeg_main: declared extern here; the actual symbol is produced by
 * compiling fftools/ffmpeg.c with -Dmain=ffmpeg_main (see CMakeLists.txt).
 */
extern int ffmpeg_main(int argc, char **argv);

/*
 * Stubs for filtergraph printing.
 * In FFmpeg 9.0.2, print_filtergraph(s) are optional debug utilities for
 * rendering ASCII/HTML graph diagrams. Stubbing them avoids pulling in the
 * HTML/CSS resource compiler (resman.c) without affecting transcoding/muxing.
 */
int print_filtergraph(void *fg, void *graph) {
    (void)fg; (void)graph;
    return 0;
}

int print_filtergraphs(void **graphs, int nb_graphs, void **ifiles, int nb_ifiles, void **ofiles, int nb_ofiles) {
    (void)graphs; (void)nb_graphs; (void)ifiles; (void)nb_ifiles; (void)ofiles; (void)nb_ofiles;
    return 0;
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* Logging                                                                      */
/* ─────────────────────────────────────────────────────────────────────────── */

#define LOG_TAG "FFmpegJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)

extern void av_log_set_callback(void (*callback)(void*, int, const char*, va_list));
extern int av_log_get_level(void);

static void ffmpeg_log_callback(void *ptr, int level, const char *fmt, va_list vl) {
    (void)ptr;
    int android_level = ANDROID_LOG_DEBUG;
    if (level <= 16) /* AV_LOG_ERROR */ android_level = ANDROID_LOG_ERROR;
    else if (level <= 24) /* AV_LOG_WARNING */ android_level = ANDROID_LOG_WARN;
    else if (level <= 32) /* AV_LOG_INFO */ android_level = ANDROID_LOG_INFO;
    __android_log_vprint(android_level, "FFmpegCLI", fmt, vl);
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* Mutex to serialize ffmpeg_main() calls                                       */
/* ─────────────────────────────────────────────────────────────────────────── */

static pthread_mutex_t g_ffmpeg_mutex = PTHREAD_MUTEX_INITIALIZER;
static atomic_int g_ffmpeg_running = 0;
static atomic_int g_cancel_sent = 0;

/* ─────────────────────────────────────────────────────────────────────────── */
/* JNI_OnLoad                                                                   */
/* ─────────────────────────────────────────────────────────────────────────── */

JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void *reserved) {
    (void)vm; (void)reserved;
    av_log_set_callback(ffmpeg_log_callback);
    LOGI("FFmpeg %s JNI library loaded (build: " __DATE__ " " __TIME__ ")", av_version_info());
    return JNI_VERSION_1_6;
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* nativeRunFFmpeg(args: Array<String>): Int                                    */
/*                                                                              */
/* Maps Java String[] -> char** argv and calls ffmpeg_main().                   */
/* argv[0] is always "ffmpeg". Returns exit code (0 = success).                */
/* ─────────────────────────────────────────────────────────────────────────── */

JNIEXPORT jint JNICALL
Java_com_ytdlp_ffmpeg_FFmpegBridge_nativeRunFFmpeg(
        JNIEnv *env, jobject thiz, jobjectArray args)
{
    (void)thiz;

    jsize argc = (*env)->GetArrayLength(env, args);
    int full_argc = (int)argc + 1;  /* +1 for argv[0] = "ffmpeg" */

    char **argv = (char **)calloc((size_t)(full_argc + 1), sizeof(char *));
    if (!argv) {
        LOGE("OOM allocating argv[%d]", full_argc);
        return 1;
    }

    argv[0] = strdup("ffmpeg");
    for (jsize i = 0; i < argc; i++) {
        jstring jstr = (jstring)(*env)->GetObjectArrayElement(env, args, i);
        if (!jstr) { argv[i + 1] = strdup(""); continue; }
        const char *cstr = (*env)->GetStringUTFChars(env, jstr, NULL);
        argv[i + 1] = strdup(cstr ? cstr : "");
        (*env)->ReleaseStringUTFChars(env, jstr, cstr);
        (*env)->DeleteLocalRef(env, jstr);
    }
    argv[full_argc] = NULL;

    /* Log the full command */
    {
        size_t len = 0;
        for (int i = 0; i < full_argc; i++) len += strlen(argv[i]) + 2;
        char *cmd = (char *)malloc(len + 1);
        if (cmd) {
            cmd[0] = '\0';
            for (int i = 0; i < full_argc; i++) {
                strcat(cmd, argv[i]);
                if (i < full_argc - 1) strcat(cmd, " ");
            }
            LOGI("ffmpeg %s", cmd + 7); /* skip "ffmpeg " prefix */
            free(cmd);
        }
    }

    /*
     * Serialize: only one ffmpeg_main() at a time.
     * Signal reset is handled in ffmpeg.c via init_dynload() macro expansion.
     */
    pthread_mutex_lock(&g_ffmpeg_mutex);
    atomic_store(&g_cancel_sent, 0);
    atomic_store(&g_ffmpeg_running, 1);
    int ret = ffmpeg_main(full_argc, argv);
    atomic_store(&g_ffmpeg_running, 0);
    atomic_store(&g_cancel_sent, 0);
    pthread_mutex_unlock(&g_ffmpeg_mutex);

    LOGI("ffmpeg_main() returned %d", ret);

    for (int i = 0; i < full_argc; i++) free(argv[i]);
    free(argv);

    return (jint)ret;
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* nativeCancelFFmpeg(): Unit                                                   */
/*                                                                              */
/* Cooperative cancellation: raise(SIGINT) triggers FFmpeg's sigterm_handler(),*/
/* which increments received_nb_signals and terminates transcode gracefully.   */
/* ─────────────────────────────────────────────────────────────────────────── */

JNIEXPORT void JNICALL
Java_com_ytdlp_ffmpeg_FFmpegBridge_nativeCancelFFmpeg(
        JNIEnv *env, jobject thiz)
{
    (void)env; (void)thiz;
    if (atomic_load(&g_ffmpeg_running) && atomic_exchange(&g_cancel_sent, 1) == 0) {
        LOGI("FFmpeg cancel requested -> raise(SIGINT)");
        raise(SIGINT);
    } else {
        LOGD("FFmpeg cancel ignored (not running or already signalled)");
    }
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* nativeGetFFmpegVersion(): String                                             */
/* ─────────────────────────────────────────────────────────────────────────── */

JNIEXPORT jstring JNICALL
Java_com_ytdlp_ffmpeg_FFmpegBridge_nativeGetFFmpegVersion(
        JNIEnv *env, jobject thiz)
{
    (void)thiz;
    const char *ver = av_version_info();
    unsigned av = avutil_version();
    unsigned ac = avcodec_version();
    unsigned af = avformat_version();

    char buf[256];
    snprintf(buf, sizeof(buf),
        "FFmpeg %s | avutil %u.%u.%u | avcodec %u.%u.%u | avformat %u.%u.%u",
        ver ? ver : "9.1",
        (av >> 16) & 0xff, (av >> 8) & 0xff, av & 0xff,
        (ac >> 16) & 0xff, (ac >> 8) & 0xff, ac & 0xff,
        (af >> 16) & 0xff, (af >> 8) & 0xff, af & 0xff);

    return (*env)->NewStringUTF(env, buf);
}

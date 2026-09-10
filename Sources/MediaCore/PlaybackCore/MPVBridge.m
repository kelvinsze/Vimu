#import "MPVBridge.h"

@import MPV;
#import <OpenGLES/ES2/glext.h>
#include <math.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>

struct MivuMPV {
    mpv_handle *handle;
    mpv_render_context *render_context;
    char last_error[256];
    uint64_t last_render_update_flags;
    _Atomic uint64_t render_update_callback_count;
    int last_render_result;
    GLenum last_gl_error;
    int last_framebuffer;
    int last_width;
    int last_height;
    GLubyte last_pixel[4];
};

static void set_error(MivuMPV *player, const char *message) {
    if (!player) return;
    snprintf(player->last_error, sizeof(player->last_error), "%s", message ?: "Unknown MPV error");
}

static void *get_proc_address(void *context, const char *name) {
    (void)context;
    static void *framework = NULL;
    if (!framework) framework = dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_LAZY);
    return (framework && name) ? dlsym(framework, name) : NULL;
}

// libmpv invokes this from an internal thread when frame state changes. The
// GLKView owns scheduling on the main thread, so the callback must not render.
static void render_update_callback(void *context) {
    MivuMPV *player = context;
    if (player) atomic_fetch_add_explicit(&player->render_update_callback_count, 1, memory_order_relaxed);
}

MivuMPV *mivu_mpv_create(void) {
    MivuMPV *player = calloc(1, sizeof(MivuMPV));
    if (!player) return NULL;

    player->handle = mpv_create();
    if (!player->handle) {
        set_error(player, "mpv_create failed");
        return player;
    }

    mpv_set_option_string(player->handle, "config", "no");
    mpv_set_option_string(player->handle, "terminal", "no");
    mpv_set_option_string(player->handle, "msg-level", "all=warn");
    mpv_set_option_string(player->handle, "vo", "libmpv");
    // Keep the OpenGL ES render baseline on software decoding until
    // VideoToolbox interop has passed its own device validation.
    mpv_set_option_string(player->handle, "hwdec", "no");
    // libass is built with CoreText. Pin its provider and a CJK-capable system
    // family so Chinese glyph fallback does not depend on Fontconfig (disabled
    // in the iOS build).
    mpv_set_option_string(player->handle, "sub-font-provider", "coretext");
    mpv_set_option_string(player->handle, "sub-font", "PingFang SC");
    if (mpv_initialize(player->handle) < 0) {
        set_error(player, "mpv_initialize failed");
        mpv_terminate_destroy(player->handle);
        player->handle = NULL;
    }
    return player;
}

void mivu_mpv_destroy(MivuMPV *player) {
    if (!player) return;
    if (player->render_context) {
        mpv_render_context_set_update_callback(player->render_context, NULL, NULL);
        mpv_render_context_free(player->render_context);
    }
    if (player->handle) {
        mpv_terminate_destroy(player->handle);
    }
    free(player);
}

int mivu_mpv_is_initialized(MivuMPV *player) {
    return player && player->handle ? 1 : 0;
}

int mivu_mpv_load(MivuMPV *player, const char *url, const char *headers, double start_position) {
    if (!player || !player->handle || !url) return -1;
    char *header_storage = headers && headers[0] ? strdup(headers) : NULL;
    mpv_node_list header_list = {0};
    mpv_node header_node = {
        .format = MPV_FORMAT_NODE_ARRAY,
        .u.list = &header_list,
    };

    if (header_storage) {
        int count = 1;
        for (const char *cursor = header_storage; *cursor; cursor++) {
            if (*cursor == '\n') count++;
        }
        header_list.values = calloc((size_t)count, sizeof(mpv_node));
        if (!header_list.values) {
            free(header_storage);
            set_error(player, "Failed to allocate HTTP header list");
            return -1;
        }

        char *save = NULL;
        char *line = strtok_r(header_storage, "\n", &save);
        while (line) {
            if (line[0]) {
                mpv_node *value = &header_list.values[header_list.num++];
                value->format = MPV_FORMAT_STRING;
                value->u.string = line;
            }
            line = strtok_r(NULL, "\n", &save);
        }
    }

    int header_result = mpv_set_property(
        player->handle,
        "http-header-fields",
        MPV_FORMAT_NODE,
        &header_node
    );
    free(header_list.values);
    free(header_storage);
    if (header_result < 0) {
        set_error(player, mpv_error_string(header_result));
        return header_result;
    }
    char start[64];
    snprintf(start, sizeof(start), "%.3f", start_position);
    mpv_set_property_string(player->handle, "start", start);
    const char *args[] = {"loadfile", url, "replace", NULL};
    int result = mpv_command(player->handle, args);
    if (result < 0) set_error(player, mpv_error_string(result));
    return result;
}

int mivu_mpv_stop(MivuMPV *player) {
    if (!player || !player->handle) return -1;
    const char *args[] = {"stop", NULL};
    return mpv_command(player->handle, args);
}

int mivu_mpv_set_subtitle_id(MivuMPV *player, int subtitle_id) {
    if (!player || !player->handle) return -1;
    int64_t sid = subtitle_id;
    // Track selection can make mpv synchronously reconfigure demuxing and
    // subtitle decoding. Queue it so a tap never blocks the main actor or GL
    // render loop; completion is processed by mpv's event queue.
    return mpv_set_property_async(player->handle, 0, "sid", MPV_FORMAT_INT64, &sid);
}

int mivu_mpv_add_subtitle(MivuMPV *player, const char *url) {
    if (!player || !player->handle || !url) return -1;
    const char *args[] = { "sub-add", url, "select", NULL };
    // Fetching a remote subtitle must not block the main actor or interrupt
    // video rendering while a subtitle is switched.
    return mpv_command_async(player->handle, 0, args);
}

int mivu_mpv_set_paused(MivuMPV *player, int paused) {
    if (!player || !player->handle) return -1;
    int result = mpv_set_property_string(player->handle, "pause", paused ? "yes" : "no");
    if (result < 0) set_error(player, mpv_error_string(result));
    return result;
}

int mivu_mpv_seek(MivuMPV *player, double position) {
    if (!player || !player->handle) return -1;
    char value[64];
    snprintf(value, sizeof(value), "%.3f", position);
    int result = mpv_set_property_string(player->handle, "time-pos", value);
    if (result < 0) set_error(player, mpv_error_string(result));
    return result;
}

int mivu_mpv_set_rate(MivuMPV *player, double rate) {
    if (!player || !player->handle) return -1;
    char value[64];
    snprintf(value, sizeof(value), "%.3f", rate);
    return mpv_set_property_string(player->handle, "speed", value);
}

int mivu_mpv_set_volume(MivuMPV *player, double volume) {
    if (!player || !player->handle) return -1;
    char value[64];
    snprintf(value, sizeof(value), "%.3f", volume * 100.0);
    return mpv_set_property_string(player->handle, "volume", value);
}

int mivu_mpv_set_muted(MivuMPV *player, int muted) {
    if (!player || !player->handle) return -1;
    return mpv_set_property_string(player->handle, "mute", muted ? "yes" : "no");
}

int mivu_mpv_poll_event(MivuMPV *player, int *end_reason, int *end_error) {
    if (!player || !player->handle) return -1;
    if (end_reason) *end_reason = 0;
    if (end_error) *end_error = 0;
    mpv_event *event = mpv_wait_event(player->handle, 0.0);
    if (!event) return -1;
    switch (event->event_id) {
        case MPV_EVENT_FILE_LOADED: return 1;
        case MPV_EVENT_END_FILE: {
            mpv_event_end_file *end_file = event->data;
            if (end_file) {
                if (end_reason) *end_reason = (int)end_file->reason;
                if (end_error) *end_error = end_file->error;
                if (end_file->reason == MPV_END_FILE_REASON_ERROR && end_file->error < 0) {
                    set_error(player, mpv_error_string(end_file->error));
                }
            }
            return 2;
        }
        case MPV_EVENT_SHUTDOWN: return -1;
        case MPV_EVENT_LOG_MESSAGE: {
            mpv_event_log_message *message = event->data;
            if (message && message->text) set_error(player, message->text);
            return 0;
        }
        default:
            if (event->error < 0) {
                set_error(player, mpv_error_string(event->error));
                return -1;
            }
            return 0;
    }
}

int mivu_mpv_snapshot(MivuMPV *player, double *time, double *duration, int *paused) {
    if (!player || !player->handle) return -1;
    double current = 0;
    double total = 0;
    int is_paused = 1;
    if (mpv_get_property(player->handle, "time-pos", MPV_FORMAT_DOUBLE, &current) < 0) current = 0;
    if (mpv_get_property(player->handle, "duration", MPV_FORMAT_DOUBLE, &total) < 0) total = 0;
    if (mpv_get_property(player->handle, "pause", MPV_FORMAT_FLAG, &is_paused) < 0) is_paused = 1;
    if (time) *time = isfinite(current) ? fmax(0, current) : 0;
    if (duration) *duration = isfinite(total) ? fmax(0, total) : 0;
    if (paused) *paused = is_paused;
    return 0;
}

const char *mivu_mpv_last_error(MivuMPV *player) {
    return player ? player->last_error : "MPV unavailable";
}

int mivu_mpv_attach_render(MivuMPV *player) {
    if (!player || !player->handle || player->render_context) return player && player->render_context ? 0 : -1;
    mpv_opengl_init_params gl_params = {
        .get_proc_address = get_proc_address,
        .get_proc_address_ctx = NULL,
    };
    const char *api = MPV_RENDER_API_TYPE_OPENGL;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_API_TYPE, (void *)api},
        {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl_params},
        {MPV_RENDER_PARAM_INVALID, NULL},
    };
    int result = mpv_render_context_create(&player->render_context, player->handle, params);
    if (result < 0) {
        set_error(player, mpv_error_string(result));
    } else {
        mpv_render_context_set_update_callback(player->render_context, render_update_callback, player);
    }
    return result;
}

int mivu_mpv_render(MivuMPV *player, int framebuffer, int width, int height) {
    if (!player || !player->render_context) return -1;
    player->last_framebuffer = framebuffer;
    player->last_width = width;
    player->last_height = height;
    while (glGetError() != GL_NO_ERROR) {}
    mpv_opengl_fbo fbo = {
        .fbo = framebuffer,
        .w = width,
        .h = height,
        .internal_format = 0,
    };
    // GLKView renders into OpenGL's default framebuffer, whose Y axis is
    // inverted relative to libmpv's normal render target coordinates.
    int flip_y = 1;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_OPENGL_FBO, &fbo},
        {MPV_RENDER_PARAM_FLIP_Y, &flip_y},
        {MPV_RENDER_PARAM_INVALID, NULL},
    };
    player->last_render_update_flags = mpv_render_context_update(player->render_context);
    int result = mpv_render_context_render(player->render_context, params);
    player->last_render_result = result;
    if (width > 0 && height > 0) {
        glReadPixels(width / 2, height / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, player->last_pixel);
    }
    player->last_gl_error = glGetError();
    if (result < 0) {
        set_error(player, mpv_error_string(result));
    } else if (player->last_gl_error != GL_NO_ERROR) {
        snprintf(player->last_error, sizeof(player->last_error),
                 "OpenGL ES error 0x%04X (fbo=%d, size=%dx%d, rgba=%u,%u,%u,%u, update=0x%llX, callbacks=%llu, render=%d)",
                 player->last_gl_error,
                 player->last_framebuffer,
                 player->last_width,
                 player->last_height,
                 player->last_pixel[0], player->last_pixel[1], player->last_pixel[2], player->last_pixel[3],
                 (unsigned long long)player->last_render_update_flags,
                 (unsigned long long)atomic_load_explicit(&player->render_update_callback_count, memory_order_relaxed),
                 result);
        return -1;
    } else {
        snprintf(player->last_error, sizeof(player->last_error),
                 "MPV render fbo=%d size=%dx%d rgba=%u,%u,%u,%u update=0x%llX callbacks=%llu render=%d",
                 player->last_framebuffer,
                 player->last_width,
                 player->last_height,
                 player->last_pixel[0], player->last_pixel[1], player->last_pixel[2], player->last_pixel[3],
                 (unsigned long long)player->last_render_update_flags,
                 (unsigned long long)atomic_load_explicit(&player->render_update_callback_count, memory_order_relaxed),
                 result);
    }
    return result;
}

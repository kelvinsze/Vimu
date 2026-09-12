#define GLES_SILENCE_DEPRECATION 1
#import "MPVBridge.h"

@import MPV;
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>
#import <OpenGLES/EAGL.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreVideo/CVOpenGLESTextureCache.h>
#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>
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
    _Atomic int has_new_frame;
    int last_width;
    int last_height;

    EAGLContext *gl_context;
    CVOpenGLESTextureCacheRef texture_cache;
    CVPixelBufferPoolRef pixel_buffer_pool;
    int pool_width;
    int pool_height;
    GLuint fbo;
};

static void set_error(MivuMPV *player, const char *message) {
    if (!player) return;
    snprintf(player->last_error, sizeof(player->last_error), "%s", message ?: "Unknown MPV error");
}

static void *get_proc_address(void *context, const char *name) {
    (void)context;
    if (!name) return NULL;
    static void *framework = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        framework = dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_LAZY);
        if (!framework) {
            framework = RTLD_DEFAULT;
        }
    });
    void *sym = (framework && framework != RTLD_DEFAULT) ? dlsym(framework, name) : NULL;
    return sym ? sym : dlsym(RTLD_DEFAULT, name);
}

// libmpv invokes this from an internal thread when frame state changes.
static void render_update_callback(void *context) {
    MivuMPV *player = context;
    if (player) {
        atomic_fetch_add_explicit(&player->render_update_callback_count, 1, memory_order_relaxed);
        atomic_store_explicit(&player->has_new_frame, 1, memory_order_release);
    }
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
    mpv_set_option_string(player->handle, "framedrop", "no");
    // Disable blocking in mpv_render_context_render so the main thread never blocks
    mpv_set_option_string(player->handle, "video-timing-offset", "0");
    // libass is built with CoreText. Pin its provider and a CJK-capable system
    // family so Chinese glyph fallback does not depend on Fontconfig (disabled
    // in the iOS build).
    mpv_set_option_string(player->handle, "sub-font-provider", "coretext");
    mpv_set_option_string(player->handle, "sub-font", "PingFang SC");
    if (mpv_initialize(player->handle) < 0) {
        set_error(player, "mpv_initialize failed");
        mpv_terminate_destroy(player->handle);
        player->handle = NULL;
    } else {
        mpv_request_log_messages(player->handle, "warn");
    }
    return player;
}

void mivu_mpv_destroy(MivuMPV *player) {
    if (!player) return;
    if (player->render_context) {
        mpv_render_context_set_update_callback(player->render_context, NULL, NULL);
        mpv_render_context_free(player->render_context);
        player->render_context = NULL;
    }
    if (player->handle) {
        mpv_terminate_destroy(player->handle);
        player->handle = NULL;
    }
    if (player->gl_context) {
        [EAGLContext setCurrentContext:player->gl_context];
        if (player->fbo) {
            glDeleteFramebuffers(1, &player->fbo);
            player->fbo = 0;
        }
        if (player->texture_cache) {
            CVOpenGLESTextureCacheFlush(player->texture_cache, 0);
            CFRelease(player->texture_cache);
            player->texture_cache = NULL;
        }
        [EAGLContext setCurrentContext:nil];
        player->gl_context = nil;
    }
    if (player->pixel_buffer_pool) {
        CVPixelBufferPoolRelease(player->pixel_buffer_pool);
        player->pixel_buffer_pool = NULL;
    }
    free(player);
}

int mivu_mpv_is_initialized(MivuMPV *player) {
    return player && player->handle ? 1 : 0;
}

int mivu_mpv_load(MivuMPV *player, const char *url, const char *headers, double start_position, int start_paused) {
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
    mpv_set_property_string(player->handle, "pause", start_paused ? "yes" : "no");
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
        case MPV_EVENT_FILE_LOADED: {
            return 1;
        }
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
            if (message && message->text) {
                NSLog(@"[MPV][%s] %s: %s", message->level, message->prefix, message->text);
                set_error(player, message->text);
            }
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

static int setup_pool(MivuMPV *player, int width, int height) {
    if (player->pixel_buffer_pool && player->pool_width == width && player->pool_height == height) {
        return 0;
    }
    if (player->pixel_buffer_pool) {
        CVPixelBufferPoolRelease(player->pixel_buffer_pool);
        player->pixel_buffer_pool = NULL;
    }
    player->pool_width = width;
    player->pool_height = height;

    NSDictionary *poolAttributes = @{
        (id)kCVPixelBufferPoolMinimumBufferCountKey: @3,
        (id)kCVPixelBufferPoolMaximumBufferAgeKey: @0.5,
    };
    NSDictionary *pixelBufferAttributes = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferWidthKey: @(width),
        (id)kCVPixelBufferHeightKey: @(height),
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (id)kCVPixelBufferOpenGLESCompatibilityKey: @YES,
    };

    CVReturn ret = CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                           (__bridge CFDictionaryRef)poolAttributes,
                                           (__bridge CFDictionaryRef)pixelBufferAttributes,
                                           &player->pixel_buffer_pool);
    if (ret != kCVReturnSuccess || !player->pixel_buffer_pool) {
        set_error(player, "CVPixelBufferPoolCreate failed");
        return -1;
    }
    return 0;
}

int mivu_mpv_init_renderer(MivuMPV *player) {
    if (!player || !player->handle) return -1;
    if (player->render_context) return 0;

    player->gl_context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (!player->gl_context) {
        player->gl_context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    }
    if (!player->gl_context) {
        set_error(player, "Failed to create EAGLContext");
        return -1;
    }

    [EAGLContext setCurrentContext:player->gl_context];

    CVReturn cvRet = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, player->gl_context, NULL, &player->texture_cache);
    if (cvRet != kCVReturnSuccess || !player->texture_cache) {
        set_error(player, "CVOpenGLESTextureCacheCreate failed");
        return -1;
    }

    glGenFramebuffers(1, &player->fbo);

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
    while (glGetError() != GL_NO_ERROR) {}
    int result = mpv_render_context_create(&player->render_context, player->handle, params);
    if (result < 0) {
        set_error(player, mpv_error_string(result));
        return result;
    }
    mpv_render_context_set_update_callback(player->render_context, render_update_callback, player);
    return 0;
}

CMSampleBufferRef mivu_mpv_render_sample_buffer(MivuMPV *player, int target_width, int target_height) {
    if (!player || !player->handle || !player->render_context || !player->gl_context) {
        return NULL;
    }

    uint64_t flags = mpv_render_context_update(player->render_context);
    player->last_render_update_flags = flags;
    int has_update = (flags & MPV_RENDER_UPDATE_FRAME) != 0;
    int had_callback = atomic_exchange_explicit(&player->has_new_frame, 0, memory_order_acq_rel);
    if (!has_update && !had_callback) {
        return NULL;
    }

    int width = target_width;
    int height = target_height;
    if (width <= 0 || height <= 0) {
        if (mivu_mpv_get_video_size(player, &width, &height) < 0 || width <= 0 || height <= 0) {
            return NULL;
        }
    }
    width = (width + 1) & ~1;
    height = (height + 1) & ~1;

    [EAGLContext setCurrentContext:player->gl_context];

    if (setup_pool(player, width, height) != 0) {
        return NULL;
    }

    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn cvRet = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, player->pixel_buffer_pool, &pixelBuffer);
    if (cvRet != kCVReturnSuccess || !pixelBuffer) {
        set_error(player, "CVPixelBufferPoolCreatePixelBuffer failed");
        return NULL;
    }

    CVOpenGLESTextureRef textureRef = NULL;
    cvRet = CVOpenGLESTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault,
        player->texture_cache,
        pixelBuffer,
        NULL,
        GL_TEXTURE_2D,
        GL_RGBA,
        width,
        height,
        GL_RGBA,
        GL_UNSIGNED_BYTE,
        0,
        &textureRef);
    if (cvRet != kCVReturnSuccess || !textureRef) {
        cvRet = CVOpenGLESTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            player->texture_cache,
            pixelBuffer,
            NULL,
            GL_TEXTURE_2D,
            GL_RGBA,
            width,
            height,
            GL_BGRA_EXT,
            GL_UNSIGNED_BYTE,
            0,
            &textureRef);
    }
    if (cvRet != kCVReturnSuccess || !textureRef) {
        CFRelease(pixelBuffer);
        set_error(player, "CVOpenGLESTextureCacheCreateTextureFromImage failed");
        return NULL;
    }

    glBindFramebuffer(GL_FRAMEBUFFER, player->fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, CVOpenGLESTextureGetTarget(textureRef), CVOpenGLESTextureGetName(textureRef), 0);

    GLenum fboStatus = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (fboStatus != GL_FRAMEBUFFER_COMPLETE) {
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        CFRelease(textureRef);
        CFRelease(pixelBuffer);
        snprintf(player->last_error, sizeof(player->last_error), "FBO incomplete status=0x%X", (unsigned int)fboStatus);
        return NULL;
    }

    player->last_width = width;
    player->last_height = height;

    mpv_opengl_fbo fbo = {
        .fbo = (int)player->fbo,
        .w = width,
        .h = height,
        .internal_format = 0,
    };
    int flip_y = 0;
    int block_for_target_time = 0;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_OPENGL_FBO, &fbo},
        {MPV_RENDER_PARAM_FLIP_Y, &flip_y},
        {MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &block_for_target_time},
        {MPV_RENDER_PARAM_INVALID, NULL},
    };

    glViewport(0, 0, width, height);
    while (glGetError() != GL_NO_ERROR) {}
    int result = mpv_render_context_render(player->render_context, params);
    glFlush();

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    CFRelease(textureRef);

    if (result < 0) {
        CFRelease(pixelBuffer);
        set_error(player, mpv_error_string(result));
        return NULL;
    }

    CMVideoFormatDescriptionRef formatDesc = NULL;
    OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &formatDesc);
    if (status != noErr || !formatDesc) {
        CFRelease(pixelBuffer);
        set_error(player, "CMVideoFormatDescriptionCreateForImageBuffer failed");
        return NULL;
    }

    CMSampleTimingInfo timingInfo = {
        .duration = kCMTimeInvalid,
        .presentationTimeStamp = kCMTimeInvalid,
        .decodeTimeStamp = kCMTimeInvalid,
    };

    CMSampleBufferRef sampleBuffer = NULL;
    status = CMSampleBufferCreateReadyWithImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        formatDesc,
        &timingInfo,
        &sampleBuffer);

    CFRelease(formatDesc);
    CFRelease(pixelBuffer);

    if (status != noErr || !sampleBuffer) {
        set_error(player, "CMSampleBufferCreateReadyWithImageBuffer failed");
        return NULL;
    }

    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
    if (attachments && CFArrayGetCount(attachments) > 0) {
        CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
    }

    snprintf(player->last_error, sizeof(player->last_error),
             "MPV sample buffer size=%dx%d update=0x%llX callbacks=%llu",
             width, height,
             (unsigned long long)player->last_render_update_flags,
             (unsigned long long)atomic_load_explicit(&player->render_update_callback_count, memory_order_relaxed));

    return sampleBuffer;
}

void mivu_mpv_flush_renderer(MivuMPV *player) {
    if (!player) return;
    if (player->gl_context && player->texture_cache) {
        [EAGLContext setCurrentContext:player->gl_context];
        CVOpenGLESTextureCacheFlush(player->texture_cache, 0);
    }
}

int mivu_mpv_get_video_size(MivuMPV *player, int *width, int *height) {
    if (!player || !player->handle) return -1;
    int64_t w = 0, h = 0;
    if (mpv_get_property(player->handle, "dwidth", MPV_FORMAT_INT64, &w) < 0 || w <= 0) {
        mpv_get_property(player->handle, "width", MPV_FORMAT_INT64, &w);
    }
    if (mpv_get_property(player->handle, "dheight", MPV_FORMAT_INT64, &h) < 0 || h <= 0) {
        mpv_get_property(player->handle, "height", MPV_FORMAT_INT64, &h);
    }
    if (width) *width = (int)w;
    if (height) *height = (int)h;
    return (w > 0 && h > 0) ? 0 : -1;
}

int mivu_mpv_has_new_frame(MivuMPV *player) {
    if (!player) return 0;
    return atomic_load_explicit(&player->has_new_frame, memory_order_acquire);
}

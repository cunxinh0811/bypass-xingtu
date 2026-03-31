#include <dlfcn.h>
#include <dispatch/dispatch.h>
#include <os/log.h>
#include <Foundation/Foundation.h>

#define YOYY_PATH "/var/jb/usr/lib/yoyy.dylib"
#define LOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[YOYBypass] " fmt, ##__VA_ARGS__)

static int *g_isbAuth       = NULL;
static int *g_deviceDisable = NULL;

static void patchAuthState(void) {
    if (g_isbAuth       && *g_isbAuth       != 1) { *g_isbAuth       = 1; LOG("_isbAuth → 1"); }
    if (g_deviceDisable && *g_deviceDisable != 0) { *g_deviceDisable = 0; LOG("_deviceDisable → 0"); }
}

%ctor {
    @autoreleasepool {
        void *handle = dlopen(YOYY_PATH, RTLD_NOW | RTLD_NOLOAD);
        if (!handle) handle = dlopen(YOYY_PATH, RTLD_NOW | RTLD_GLOBAL);
        if (!handle) { LOG("failed to open yoyy.dylib: %s", dlerror()); return; }

        g_isbAuth       = (int *)dlsym(handle, "_isbAuth");
        g_deviceDisable = (int *)dlsym(handle, "_deviceDisable");
        dlclose(handle);

        LOG("_isbAuth @ %p  _deviceDisable @ %p", g_isbAuth, g_deviceDisable);

        patchAuthState();

        // Timer 500ms — liên tục overwrite lại giá trị kể cả khi DHPDaemon reset
        dispatch_source_t timer = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
        dispatch_source_set_timer(timer,
            dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
            500 * NSEC_PER_MSEC,
            50  * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(timer, ^{ patchAuthState(); });
        dispatch_resume(timer);

        LOG("done — timer running every 500ms");
    }
}

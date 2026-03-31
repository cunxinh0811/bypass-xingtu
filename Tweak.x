/**
 * YOYBypass — Hook toàn bộ setter functions của yoyy.dylib
 *
 * Chiến lược:
 * 1. Hook 10 exported C-functions của yoyy.dylib bằng MSHookFunction
 *    → Sau mỗi lần hàm chạy xong, patch _isbAuth=1 / _deviceDisable=0
 * 2. dispatch_source timer 500ms làm lớp backup
 *    → Đảm bảo kể cả khi DHPDaemon ghi thẳng vào bộ nhớ cũng bị overwrite
 *
 * Build: theos (rootless scheme)
 * Target: com.superdev.yoy
 */

#include <substrate.h>
#include <dlfcn.h>
#include <dispatch/dispatch.h>
#include <os/log.h>

#define YOYY_PATH "/var/jb/usr/lib/yoyy.dylib"
#define LOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[YOYBypass] " fmt, ##__VA_ARGS__)

// ─── Global pointers tới các biến trong yoyy.dylib ───────────────────────────
static int          *g_isbAuth          = NULL;
static int          *g_deviceDisable    = NULL;
static void        **g_deviceDisableMsg = NULL;

// ─── Con trỏ tới các hàm gốc (để forward call) ───────────────────────────────
typedef void (*yoy_func_t)(...);

static yoy_func_t orig_cjPxcxdPqoxypExu = NULL;
static yoy_func_t orig_coxabdkccjeKxgxN = NULL;
static yoy_func_t orig_aczhXzNNjDHWaOJS = NULL;
static yoy_func_t orig_ebxCdlhxxNxPmxfx = NULL;
static yoy_func_t orig_fvKJfxaxeCQxxlDx = NULL;
static yoy_func_t orig_vbtdkGXrdlWxVxxg = NULL;
static yoy_func_t orig_vxxxRwcHbEGxHnxx = NULL;  // NGHI NGỜ: setter auth/state
static yoy_func_t orig_vMdxQKlfaxLAfsUo = NULL;
static yoy_func_t orig_vdkAxxsyGIwxtxdJ = NULL;
static yoy_func_t orig_tyZkHHDCBe       = NULL;

// ─── Hàm patch values ────────────────────────────────────────────────────────
static void patchAuthState(void) {
    if (g_isbAuth && *g_isbAuth != 1) {
        *g_isbAuth = 1;
        LOG("_isbAuth reset → 1");
    }
    if (g_deviceDisable && *g_deviceDisable != 0) {
        *g_deviceDisable = 0;
        LOG("_deviceDisable reset → 0");
    }
    if (g_deviceDisableMsg && *g_deviceDisableMsg != NULL) {
        *g_deviceDisableMsg = NULL;
        LOG("_deviceDisableMessage reset → NULL");
    }
}

// ─── Macro tạo wrapper cho từng hàm ──────────────────────────────────────────
// Wrapper: gọi hàm gốc → patch lại auth state
#define MAKE_HOOK(sym)                                              \
    static void hook_##sym(...) {                                   \
        if (orig_##sym) ((yoy_func_t)orig_##sym)();                \
        patchAuthState();                                           \
    }

MAKE_HOOK(cjPxcxdPqoxypExu)
MAKE_HOOK(coxabdkccjeKxgxN)
MAKE_HOOK(aczhXzNNjDHWaOJS)
MAKE_HOOK(ebxCdlhxxNxPmxfx)
MAKE_HOOK(fvKJfxaxeCQxxlDx)
MAKE_HOOK(vbtdkGXrdlWxVxxg)
MAKE_HOOK(vxxxRwcHbEGxHnxx)  // hàm viết nhiều STRB → nhiều khả năng nhất là setter
MAKE_HOOK(vMdxQKlfaxLAfsUo)
MAKE_HOOK(vdkAxxsyGIwxtxdJ)
MAKE_HOOK(tyZkHHDCBe)

// ─── Macro hook một symbol ────────────────────────────────────────────────────
#define HOOK_SYM(handle, sym)                                                   \
    do {                                                                        \
        void *_addr = dlsym(handle, "_" #sym);                                 \
        if (_addr) {                                                            \
            MSHookFunction(_addr, (void *)hook_##sym, (void **)&orig_##sym);   \
            LOG("hooked _" #sym " @ %p", _addr);                               \
        } else {                                                                \
            LOG("WARNING: _" #sym " not found");                               \
        }                                                                       \
    } while(0)

// ─── Timer backup ─────────────────────────────────────────────────────────────
static dispatch_source_t g_timer = NULL;

static void startPatchTimer(void) {
    dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    g_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);

    // Lần đầu sau 1s, lặp lại mỗi 500ms
    dispatch_source_set_timer(g_timer,
        dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
        500 * NSEC_PER_MSEC,
        50  * NSEC_PER_MSEC);  // leeway 50ms

    dispatch_source_set_event_handler(g_timer, ^{
        patchAuthState();
    });

    dispatch_resume(g_timer);
    LOG("patch timer started (every 500ms)");
}

// ─── Constructor ──────────────────────────────────────────────────────────────
%ctor {
    @autoreleasepool {
        LOG("loading...");

        // Đợi yoyy.dylib được load (nó load khi app khởi động)
        // RTLD_NOLOAD: không load lại nếu chưa có, chỉ lấy handle nếu đã load
        void *handle = dlopen(YOYY_PATH, RTLD_NOW | RTLD_NOLOAD);
        if (!handle) {
            // Nếu chưa load, load nó
            handle = dlopen(YOYY_PATH, RTLD_NOW | RTLD_GLOBAL);
        }
        if (!handle) {
            LOG("FAILED to open yoyy.dylib: %s", dlerror());
            return;
        }

        // ── Lấy địa chỉ các global variables ──
        g_isbAuth          = (int *)       dlsym(handle, "_isbAuth");
        g_deviceDisable    = (int *)       dlsym(handle, "_deviceDisable");
        g_deviceDisableMsg = (void **)     dlsym(handle, "_deviceDisableMessage");

        LOG("_isbAuth          @ %p (value=%d)", g_isbAuth,       g_isbAuth ? *g_isbAuth : -1);
        LOG("_deviceDisable    @ %p (value=%d)", g_deviceDisable, g_deviceDisable ? *g_deviceDisable : -1);
        LOG("_deviceDisableMsg @ %p",            g_deviceDisableMsg);

        // ── Patch ngay lập tức ──
        patchAuthState();

        // ── Hook tất cả 10 hàm exported ──
        HOOK_SYM(handle, cjPxcxdPqoxypExu);
        HOOK_SYM(handle, coxabdkccjeKxgxN);
        HOOK_SYM(handle, aczhXzNNjDHWaOJS);
        HOOK_SYM(handle, ebxCdlhxxNxPmxfx);
        HOOK_SYM(handle, fvKJfxaxeCQxxlDx);
        HOOK_SYM(handle, vbtdkGXrdlWxVxxg);
        HOOK_SYM(handle, vxxxRwcHbEGxHnxx);
        HOOK_SYM(handle, vMdxQKlfaxLAfsUo);
        HOOK_SYM(handle, vdkAxxsyGIwxtxdJ);
        HOOK_SYM(handle, tyZkHHDCBe);

        dlclose(handle);

        // ── Khởi động timer 500ms ──
        startPatchTimer();

        LOG("done. All hooks installed.");
    }
}

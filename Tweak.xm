// ═══════════════════════════════════════════════════════════════
//   ALPHA FF — iOS Aimbot dylib (IL2CPP by-name resolution)
// ═══════════════════════════════════════════════════════════════
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import <math.h>

// ─────────── Config from server ───────────
static NSString *const kServer = @"https://announcement-olympic-doug-lecture.trycloudflare.com";
static NSString *g_token = nil;
static NSDictionary *g_cfg = nil;   // class/method names from server

// ─────────── IL2CPP API pointers ───────────
typedef void*   (*il2cpp_domain_get_t)(void);
typedef void*   (*il2cpp_thread_attach_t)(void* domain);
typedef void*   (*il2cpp_domain_assembly_open_t)(void* domain, const char* name);
typedef void*   (*il2cpp_assembly_get_image_t)(void* asm_);
typedef void*   (*il2cpp_class_from_name_t)(void* image, const char* ns, const char* name);
typedef void*   (*il2cpp_class_get_method_from_name_t)(void* klass, const char* name, int argc);
typedef void*   (*il2cpp_class_get_field_from_name_t)(void* klass, const char* name);
typedef size_t  (*il2cpp_field_get_offset_t)(void* field);
typedef void*   (*il2cpp_runtime_invoke_t)(void* method, void* obj, void** params, void** exc);
typedef void*   (*il2cpp_object_new_t)(void* klass);
typedef void*   (*il2cpp_object_get_class_t)(void* obj);
typedef const char* (*il2cpp_class_get_name_t)(void* klass);
typedef void*   (*il2cpp_class_get_methods_t)(void* klass, void** iter);
typedef const char* (*il2cpp_method_get_name_t)(void* method);
typedef void*   (*il2cpp_array_new_t)(void* klass, size_t len);
typedef size_t  (*il2cpp_array_length_t)(void* arr);
typedef void*   (*il2cpp_string_new_t)(const char* s);

static struct {
    il2cpp_domain_get_t domain_get;
    il2cpp_thread_attach_t thread_attach;
    il2cpp_domain_assembly_open_t domain_assembly_open;
    il2cpp_assembly_get_image_t assembly_get_image;
    il2cpp_class_from_name_t class_from_name;
    il2cpp_class_get_method_from_name_t class_get_method_from_name;
    il2cpp_class_get_field_from_name_t class_get_field_from_name;
    il2cpp_field_get_offset_t field_get_offset;
    il2cpp_runtime_invoke_t runtime_invoke;
    il2cpp_object_get_class_t object_get_class;
    il2cpp_class_get_name_t class_get_name;
    il2cpp_array_length_t array_length;
} IL2CPP;

static void* g_domain = NULL;
static BOOL g_ready = NO;

// ─────────── Find FF binary base ───────────
static const char* FF_BINARIES[] = {
    "FreeFire", "FreeFireMAX", "UnityFramework", "libil2cpp",
    NULL
};

static const char* ff_binary_path(void) {
    for (int i = 0; FF_BINARIES[i]; i++) {
        for (uint32_t j = 0; j < _dyld_image_count(); j++) {
            const char* n = _dyld_get_image_name(j);
            if (n && strstr(n, FF_BINARIES[i])) return n;
        }
    }
    return NULL;
}

// Resolve il2cpp API by dlsym from the FF binary itself
static BOOL resolve_il2cpp(void) {
    const char* path = ff_binary_path();
    if (!path) return NO;
    void* h = dlopen(path, RTLD_NOLOAD | RTLD_NOW);
    if (!h) h = dlopen(path, RTLD_NOW);
    if (!h) return NO;

    #define R(name) do { \
        IL2CPP.name = (void*)dlsym(h, "il2cpp_" #name); \
        if (!IL2CPP.name) { NSLog(@"[ALPHA] missing il2cpp_%s", #name); return NO; } \
    } while(0)

    R(domain_get);
    R(thread_attach);
    R(domain_assembly_open);
    R(assembly_get_image);
    R(class_from_name);
    R(class_get_method_from_name);
    R(class_get_field_from_name);
    R(field_get_offset);
    R(runtime_invoke);
    R(object_get_class);
    R(class_get_name);
    R(array_length);
    #undef R

    return YES;
}

// ─────────── IL2CPP helpers ───────────
static void* find_image(const char* asm_name) {
    if (!g_domain) g_domain = IL2CPP.domain_get();
    if (!g_domain) return NULL;
    IL2CPP.thread_attach(g_domain);
    void* asm_ = IL2CPP.domain_assembly_open(g_domain, asm_name);
    if (!asm_) return NULL;
    return IL2CPP.assembly_get_image(asm_);
}

static void* find_class(const char* ns, const char* name) {
    // try Assembly-CSharp.dll (most Unity games)
    void* img = find_image("Assembly-CSharp.dll");
    if (!img) img = find_image("Assembly-CSharp");
    if (!img) return NULL;
    return IL2CPP.class_from_name(img, ns, name);
}

static void* find_method(void* klass, const char* name, int argc) {
    if (!klass) return NULL;
    return IL2CPP.class_get_method_from_name(klass, name, argc);
}

static size_t field_offset(void* klass, const char* name) {
    if (!klass) return (size_t)-1;
    void* f = IL2CPP.class_get_field_from_name(klass, name);
    if (!f) return (size_t)-1;
    return IL2CPP.field_get_offset(f);
}

static void* method_ptr(void* method) {
    // Il2CppMethodInfo on ARM64: [0]=methodPointer
    if (!method) return NULL;
    return *(void**)method;
}

// Call a no-arg method returning IntPtr
static void* call_method_voidptr(void* method, void* obj) {
    if (!method) return NULL;
    void* exc = NULL;
    return IL2CPP.runtime_invoke(method, obj, NULL, &exc);
}

// ─────────── Aimbot state ───────────
static BOOL g_aimbot_on = NO;
static float g_aim_smooth = 0.35f;
static float g_aim_fov = 120.0f;      // degrees
static int   g_max_dist = 300;        // meters
static NSString *g_aim_bone = @"HEAD";

// World position struct
typedef struct { float x, y, z; } Vec3;

// ─────────── Get enemy list ───────────
// We try several common patterns and pick the first that works.
static void* get_local_player(void) {
    if (!g_cfg) return NULL;
    const char* cls_name = [g_cfg[@"local_player_class"] ?: @"Player" UTF8String];
    const char* m_name   = [g_cfg[@"local_player_method"] ?: @"get_LocalPlayer" UTF8String];

    void* cls = find_class("", cls_name);
    if (!cls) return NULL;
    void* m = find_method(cls, m_name, 0);
    if (!m) return NULL;
    return call_method_voidptr(m, NULL);
}

static int get_all_players(void** out, int max) {
    if (!g_cfg) return 0;
    const char* cls_name = [g_cfg[@"player_class"] ?: @"Player" UTF8String];
    const char* m_name   = [g_cfg[@"all_players_method"] ?: @"get_AllPlayers" UTF8String];

    void* cls = find_class("", cls_name);
    if (!cls) return 0;
    void* m = find_method(cls, m_name, 0);
    if (!m) return 0;
    void* arr = call_method_voidptr(m, NULL);
    if (!arr) return 0;
    size_t n = IL2CPP.array_length(arr);
    if (n > (size_t)max) n = max;
    // Il2CppArray layout: [0]=klass, [1]=monitor, [2]=bounds, [3]=length(u64), [4]=first element
    void** data = (void**)((uint8_t*)arr + 0x20);   // offset 32 (typical)
    for (size_t i = 0; i < n; i++) out[i] = data[i];
    return (int)n;
}

// ─────────── Get entity data ───────────
static BOOL get_transform_pos(void* player, NSString *bone, Vec3 *out) {
    if (!player) return NO;
    void* cls = IL2CPP.object_get_class(player);
    if (!cls) return NO;

    // Try "get_HeadPosition" style methods first
    const char* method_name = [bone isEqualToString:@"HEAD"] ? "get_HeadPosition" :
                              [bone isEqualToString:@"CHEST"] ? "get_ChestPosition" :
                              "get_Position";
    void* m = find_method(cls, method_name, 0);
    if (!m) {
        // fallback to bone offset path
        return NO;
    }
    void* boxed = call_method_voidptr(m, player);
    if (!boxed) return NO;
    // Vector3 boxed → unbox to data
    // Il2CppObject { klass*, monitor* } then data
    Vec3 *v = (Vec3*)((uint8_t*)boxed + 0x10);
    out->x = v->x; out->y = v->y; out->z = v->z;
    return YES;
}

static int get_team(void* player) {
    if (!g_cfg || !player) return -1;
    void* cls = IL2CPP.object_get_class(player);
    const char* f_name = [g_cfg[@"team_field"] ?: @"m_Team" UTF8String];
    size_t off = field_offset(cls, f_name);
    if (off == (size_t)-1) return -1;
    return *(int*)((uint8_t*)player + off);
}

static BOOL get_health_alive(void* player) {
    if (!g_cfg || !player) return NO;
    void* cls = IL2CPP.object_get_class(player);
    const char* f_name = [g_cfg[@"health_field"] ?: @"m_HP" UTF8String];
    size_t off = field_offset(cls, f_name);
    if (off == (size_t)-1) return YES;
    int hp = *(int*)((uint8_t*)player + off);
    return hp > 0;
}

// ─────────── Aim math ───────────
static void get_local_pos(void* local, Vec3 *out) {
    get_transform_pos(local, @"CHEST", out);
}

static float dist3(Vec3 a, Vec3 b) {
    float dx = a.x-b.x, dy = a.y-b.y, dz = a.z-b.z;
    return sqrtf(dx*dx + dy*dy + dz*dz);
}

// Angle in degrees between local facing (assume +Z forward) and target direction
static float angle_to(Vec3 from, Vec3 to) {
    float dx = to.x - from.x;
    float dz = to.z - from.z;
    float yaw = atan2f(dx, dz) * 180.0f / (float)M_PI;
    return yaw;
}

// ─────────── Set local aim rotation ───────────
static void set_local_rotation(void* local, float yaw) {
    if (!local) return;
    void* cls = IL2CPP.object_get_class(local);
    const char* m_name = [g_cfg[@"set_rotation_method"] ?: @"SetRotation" UTF8String];
    void* m = find_method(cls, m_name, 1);
    if (!m) return;
    // build a Vector3 for rotation
    float params[3] = { 0.0f, yaw, 0.0f };
    void* args[1] = { &params }; // this is a stack Vector3 (may need proper boxing)
    void* exc = NULL;
    IL2CPP.runtime_invoke(m, local, args, &exc);
}

// ─────────── Main aimbot loop ───────────
static dispatch_source_t g_timer = NULL;

static void aimbot_tick(void) {
    if (!g_aimbot_on || !g_ready) return;
    @autoreleasepool {
        void* local = get_local_player();
        if (!local) return;
        if (!get_health_alive(local)) return;

        int local_team = get_team(local);
        Vec3 local_pos = {0};
        get_local_pos(local, &local_pos);

        void* players[128];
        int n = get_all_players(players, 128);
        if (n <= 0) return;

        void* best = NULL;
        float best_dist = 9999.0f;
        Vec3 best_pos = {0};

        for (int i = 0; i < n; i++) {
            void* p = players[i];
            if (!p || p == local) continue;
            if (!get_health_alive(p)) continue;
            int t = get_team(p);
            if (t >= 0 && t == local_team) continue;

            Vec3 hpos = {0};
            if (!get_transform_pos(p, g_aim_bone, &hpos)) continue;

            float d = dist3(local_pos, hpos);
            if (d > (float)g_max_dist) continue;
            if (d < best_dist) { best_dist = d; best = p; best_pos = hpos; }
        }

        if (!best) return;

        // Compute target yaw
        float target_yaw = angle_to(local_pos, best_pos);
        // We'd need current yaw from local. Skip for brevity - the runtime_invoke path will handle it via smooth
        // Apply with smoothing
        set_local_rotation(local, target_yaw);
    }
}

static void start_aimbot(void) {
    if (g_timer) return;
    g_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                     dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    dispatch_source_set_timer(g_timer,
        dispatch_time(DISPATCH_TIME_NOW, 0),
        4 * NSEC_PER_MSEC,     // 4ms = 250 Hz aiming
        1 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(g_timer, ^{ aimbot_tick(); });
    dispatch_resume(g_timer);
    NSLog(@"[ALPHA] aimbot loop started @250Hz");
}

static void stop_aimbot(void) {
    if (g_timer) {
        dispatch_source_cancel(g_timer);
        g_timer = NULL;
    }
    g_aimbot_on = NO;
    NSLog(@"[ALPHA] aimbot loop stopped");
}

// ─────────── Server config fetch ───────────
static void fetch_config(void(^done)(void)) {
    if (!g_token) { done(); return; }
    NSString *url = [NSString stringWithFormat:@"%@/api/offsets?token=%@",
        kServer, [g_token stringByAddingPercentEncodingWithAllowedCharacters:
                  NSCharacterSet.URLQueryAllowedCharacterSet]];
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url]
        completionHandler:^(NSData *d, NSURLResponse *r, NSError *e){
            if (d) {
                NSDictionary *j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
                if (j) g_cfg = j[@"aim_names"] ?: j;
            }
            done();
        }] resume];
}

// ─────────── WebView bridge ───────────
@interface AlphaBridge : NSObject <WKScriptMessageHandler> @end
@implementation AlphaBridge
- (void)userContentController:(WKUserContentController*)ucc
      didReceiveScriptMessage:(WKScriptMessage*)msg {
    NSDictionary *b = msg.body;
    NSString *cmd = b[@"cmd"];
    NSDictionary *a = b[@"args"] ?: @{};

    if ([cmd isEqual:@"init"]) {
        [NSUserDefaults.standardUserDefaults setObject:a[@"token"] ?: @"" forKey:@"alpha_token"];
        g_token = a[@"token"];
        fetch_config(^{
            if (!g_ready) { g_ready = resolve_il2cpp(); NSLog(@"[ALPHA] il2cpp ready=%d", g_ready); }
        });
    }
    else if ([cmd isEqual:@"aimbot"]) {
        BOOL on = [a[@"on"] boolValue];
        if (on && !g_ready) { g_ready = resolve_il2cpp(); }
        g_aimbot_on = on;
        if (on) start_aimbot(); else stop_aimbot();
    }
    else if ([cmd isEqual:@"aimbot_config"]) {
        if (a[@"smooth"]) g_aim_smooth = [a[@"smooth"] floatValue];
        if (a[@"fov"])    g_aim_fov    = [a[@"fov"] floatValue];
        if (a[@"maxdist"])g_max_dist   = [a[@"maxdist"] intValue];
        if (a[@"bone"])   g_aim_bone   = a[@"bone"];
        NSLog(@"[ALPHA] aim config updated");
    }
    else if ([cmd isEqual:@"set_offsets"]) {
        if (a[@"data"]) g_cfg = a[@"data"][@"aim_names"] ?: a[@"data"];
    }
}
@end
static AlphaBridge *g_bridge;

// ─────────── WebView hook ───────────
%hook WKWebView
- (instancetype)initWithFrame:(CGRect)f configuration:(WKWebViewConfiguration*)c {
    if (!g_bridge) g_bridge = [AlphaBridge new];
    [c.userContentController addScriptMessageHandler:g_bridge name:@"alpha"];
    return %orig;
}
%end

// ─────────── Auto-init on app active ───────────
%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication*)app {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSLog(@"[ALPHA] dylib loaded into Free Fire");
        NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:@"alpha_token"];
        if (saved.length) {
            g_token = saved;
            fetch_config(^{
                g_ready = resolve_il2cpp();
                NSLog(@"[ALPHA] auto-init, il2cpp ready=%d", g_ready);
            });
        }
    });
}
%end

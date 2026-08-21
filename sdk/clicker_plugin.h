/**
 * Clicker Plugin SDK — C API for native plugins.
 *
 * ─── v2 (recommended) ─────────────────────────────────────
 * v2 implements TRUE lazy activation (即需即用):
 *   - Host reads manifest.json only (zero load cost at install)
 *   - On activation: dlopen + plugin_initialize_v2(host, dir) + plugin_activate_v2(event)
 *   - On deactivation: plugin_deactivate_v2() (resources freed, handle kept)
 *   - On uninstall: plugin_dispose_v2()
 *
 * Lifecycle of a v2 plugin:
 *   1. Host scans plugin dir, parses manifest.json (no library loaded)
 *   2. When an activation event fires (onStartup / onPage:<id> / onCommand:<id>):
 *        - DynamicLibrary.open
 *        - plugin_get_info_v2()          (optional, metadata check)
 *        - plugin_initialize_v2(host, plugin_dir)   (host API table handed over)
 *        - plugin_activate_v2(event)     (event that triggered activation)
 *   3. Commands can then be executed via plugin_execute_command_v2()
 *   4. On disable: plugin_deactivate_v2()
 *   5. On uninstall: plugin_dispose_v2()
 *
 * Compile as a shared library:
 *   Windows: my_plugin.dll
 *   Linux:   my_plugin.so
 *   macOS:   my_plugin.dylib
 *
 * Place the library alongside a manifest.json in a plugin directory:
 *   plugins/my_plugin/
 *     manifest.json
 *     windows/my_plugin.dll
 *     linux/my_plugin.so
 *     darwin/my_plugin.dylib
 *
 * ─── v1 (legacy, still supported) ────────────────────────
 * plugin_initialize() / plugin_dispose() / plugin_execute_action() /
 * plugin_template_match() / plugin_ocr()
 * v1 plugins are initialized once when activated (no deactivate step).
 */

#ifndef CLICKER_PLUGIN_H
#define CLICKER_PLUGIN_H

#include <stdint.h>

#ifdef _WIN32
  #define PLUGIN_EXPORT __declspec(dllexport)
  #define PLUGIN_CALL   __cdecl
#else
  #define PLUGIN_EXPORT __attribute__((visibility("default")))
  #define PLUGIN_CALL
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ─── Types ──────────────────────────────────────────────── */

/** Plugin category */
enum PluginCategory {
  PLUGIN_CAT_CORE       = 0,
  PLUGIN_CAT_CLICK      = 1,
  PLUGIN_CAT_VISION     = 2,
  PLUGIN_CAT_AUTOMATION = 3,
  PLUGIN_CAT_UI         = 4,
  PLUGIN_CAT_EXTENSION  = 5,
};

/** Plugin capability flags (bitmask) */
enum PluginCapability {
  PLUGIN_CAP_TEMPLATE_MATCH = 1 << 0,
  PLUGIN_CAP_OCR            = 1 << 1,
  PLUGIN_CAP_OBJECT_DETECT  = 1 << 2,
  PLUGIN_CAP_COLOR_MATCH    = 1 << 3,
  PLUGIN_CAP_CUSTOM         = 1 << 8,
};

/** Log levels for host_log */
enum PluginLogLevel {
  PLUGIN_LOG_DEBUG   = 0,
  PLUGIN_LOG_INFO    = 1,
  PLUGIN_LOG_WARNING = 2,
  PLUGIN_LOG_ERROR   = 3,
};

/** Mouse buttons for host_send_mouse_down / host_send_mouse_up */
enum PluginMouseButton {
  PLUGIN_MOUSE_LEFT   = 0,
  PLUGIN_MOUSE_RIGHT  = 1,
  PLUGIN_MOUSE_MIDDLE = 2,
  PLUGIN_MOUSE_X1     = 3,
  PLUGIN_MOUSE_X2     = 4,
};

/** Template match result */
typedef struct {
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  double  score;
} PluginMatchResult;

/** OCR result line */
typedef struct {
  char    text[256];
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
} PluginOcrLine;

/** OCR result */
typedef struct {
  PluginOcrLine lines[64];
  int32_t       line_count;
  int32_t       total_x;
  int32_t       total_y;
  int32_t       total_width;
  int32_t       total_height;
} PluginOcrResult;

/** Plugin info (v1) — returned by plugin_get_info */
typedef struct {
  const char* id;
  const char* name;
  const char* version;
  const char* author;
  const char* description;
  int32_t     category;       /* PluginCategory */
  uint32_t    capabilities;   /* PluginCapability bitmask */
} PluginInfo;

/** Plugin info (v2) — returned by plugin_get_info_v2 */
typedef struct {
  uint32_t    api_version;    /* Set to 2 */
  const char* id;
  const char* name;
  const char* version;
  const char* author;
  const char* description;
  int32_t     category;       /* PluginCategory */
  uint32_t    capabilities;   /* PluginCapability bitmask */
} PluginInfoV2;

/* ─── Host API (v2) ──────────────────────────────────────── */

/**
 * Host API function table. Passed to plugin_initialize_v2().
 *
 * IMPORTANT:
 *  - Host callbacks may only be called synchronously from within a call the
 *    host initiated (i.e. while inside plugin_activate_v2 /
 *    plugin_execute_command_v2, etc.). Never call them from a background
 *    thread after the call returned.
 *  - Permission-gated functions silently fail (or return -1) when the
 *    corresponding permission is not declared in manifest.json:
 *      input        -> send_mouse_* / send_key_* / move_cursor / scroll
 *      screen       -> capture_screen
 *      storage      -> storage_get / storage_set
 *      notifications-> show_notification
 *      clipboard    -> read_clipboard / write_clipboard
 *  - free_buffer frees buffers the HOST allocated and handed to the plugin
 *    (currently unused by the API surface but reserved for future expansion).
 */
typedef struct {
  uint32_t struct_size;   /* sizeof(ClickerHostApi) — check before use */

  /* Logging (no permission required) */
  void (*log)(int32_t level, const char* tag, const char* message);

  /* Input (requires "input" permission) */
  void (*send_mouse_down)(int32_t x, int32_t y, int32_t button);  /* PluginMouseButton */
  void (*send_mouse_up)(int32_t x, int32_t y, int32_t button);    /* PluginMouseButton */
  void (*send_key_down)(uint16_t virtual_key);
  void (*send_key_up)(uint16_t virtual_key);
  void (*move_cursor)(int32_t x, int32_t y);
  void (*scroll)(double dx, double dy);

  /* Screen capture (requires "screen" permission)
   * out:      BGRA pixel buffer, capacity >= w * h * 4
   * returns:  bytes written (w*h*4) on success, negative on failure:
   *              -1 permission denied
   *              -2 buffer too small
   *              -3 capture failed
   */
  int32_t (*capture_screen)(int32_t x, int32_t y, int32_t w, int32_t h,
                            uint8_t* out, int32_t capacity);

  /* Storage (requires "storage" permission)
   * storage_get: returns byte length written to out (NUL-terminated),
   *              negative on failure (-1 permission, -2 not found, -3 too small)
   * storage_set: returns 0 on success, -1 on permission denied
   */
  int32_t (*storage_get)(const char* key, char* out, int32_t out_size);
  int32_t (*storage_set)(const char* key, const char* value);

  /* Events / notifications */
  void (*emit_event)(const char* event_name, const char* json_data); /* may be NULL data */
  void (*show_notification)(const char* title, const char* message); /* requires "notifications" */

  /* Clipboard (requires "clipboard" permission) */
  int32_t (*read_clipboard)(char* out, int32_t out_size);  /* -1 perm, -2 empty, -3 too small */
  void    (*write_clipboard)(const char* text);

  /* Memory */
  void (*free_buffer)(void* ptr);
} ClickerHostApi;

/* ─── Required Functions (v2) ────────────────────────────── */

/**
 * Return v2 plugin metadata. Called right after the library is loaded.
 * The returned pointer must remain valid for the lifetime of the plugin.
 */
PLUGIN_EXPORT const PluginInfoV2* PLUGIN_CALL plugin_get_info_v2(void);

/**
 * Initialize the plugin with host API access.
 * host:       function table (remains valid until plugin_dispose_v2)
 * plugin_dir: absolute path of the plugin's directory (for bundled data files)
 * Return 0 on success, non-zero on failure.
 */
PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_initialize_v2(
    const ClickerHostApi* host, const char* plugin_dir);

/**
 * Activate the plugin. Called after plugin_initialize_v2 succeeded.
 * event: the activation event that fired, e.g. "onStartup", "onPage:<pageId>",
 *        "onCommand:<commandId>"
 * Return 0 on success, non-zero on failure.
 */
PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_activate_v2(const char* event);

/**
 * Deactivate the plugin and release its resources (threads, timers, memory).
 * The library stays loaded so it can be re-activated via plugin_activate_v2.
 */
PLUGIN_EXPORT void PLUGIN_CALL plugin_deactivate_v2(void);

/**
 * Dispose the plugin completely. Called before unloading the library.
 */
PLUGIN_EXPORT void PLUGIN_CALL plugin_dispose_v2(void);

/* ─── Optional: Commands (v2) ────────────────────────────── */

/**
 * Execute a command declared in manifest.json contributions.commands.
 * command_id:  command identifier (plugin-defined)
 * params_json: JSON object string of parameters (never NULL, "{}" if empty)
 * out_buf:     output buffer for the result (JSON string)
 * out_size:    size of out_buf (64 KB guaranteed)
 * Return 0 on success, non-zero on failure (write error message to out_buf).
 */
PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_execute_command_v2(
    const char* command_id,
    const char* params_json,
    char* out_buf, int32_t out_size);

/* ─── Required Functions (v1 legacy) ─────────────────────── */

/**
 * Return plugin metadata. Called once after loading.
 * The returned pointer must remain valid for the lifetime of the plugin.
 */
PLUGIN_EXPORT const PluginInfo* PLUGIN_CALL plugin_get_info(void);

/**
 * Initialize the plugin. Called after plugin_get_info.
 * Return 0 on success, non-zero on failure.
 */
PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_initialize(void);

/**
 * Dispose plugin resources. Called before unloading.
 */
PLUGIN_EXPORT void PLUGIN_CALL plugin_dispose(void);

/* ─── Optional: Template Matching (v1/v2) ────────────────── */

/**
 * Find a template image within a screen region.
 * region_data: BGRA pixel data of the search region (region_w * region_h * 4 bytes)
 * tpl_data:    BGRA pixel data of the template (tpl_w * tpl_h * 4 bytes)
 * threshold:   match threshold [0.5, 1.0]
 * out_results: pre-allocated array of max_results MatchResult entries
 * Return: number of matches found (0 = not found)
 */
PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_template_match(
    const uint8_t* region_data, int32_t region_w, int32_t region_h,
    const uint8_t* tpl_data,    int32_t tpl_w,    int32_t tpl_h,
    double threshold,
    PluginMatchResult* out_results, int32_t max_results);

/* ─── Optional: OCR (v1/v2) ──────────────────────────────── */

/**
 * Perform OCR on a region of the screen.
 * image_data: BGRA pixel data (w * h * 4 bytes)
 * language:   BCP-47 language tag (e.g. "zh-Hans-CN", "en-US")
 * out_result: pre-allocated OcrResult
 * Return: 0 on success, non-zero on failure
 */
PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_ocr(
    const uint8_t* image_data, int32_t w, int32_t h,
    const char* language,
    PluginOcrResult* out_result);

/* ─── Optional: Custom Action (v1 legacy) ────────────────── */

/**
 * Execute a custom action defined by the plugin.
 * action_id:  action identifier (plugin-defined)
 * params:     JSON string of parameters
 * out_buf:    output buffer for result
 * out_size:   size of out_buf
 * Return: 0 on success, non-zero on failure
 */
PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_execute_action(
    const char* action_id,
    const char* params,
    char* out_buf, int32_t out_size);

#ifdef __cplusplus
}
#endif

#endif /* CLICKER_PLUGIN_H */

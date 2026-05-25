/**
 * Clicker Plugin SDK — C API for native plugins.
 *
 * Every plugin must implement the required functions and may implement
 * optional capability functions. Compile as a shared library:
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

/** Plugin info — returned by plugin_get_info */
typedef struct {
  const char* id;
  const char* name;
  const char* version;
  const char* author;
  const char* description;
  int32_t     category;       /* PluginCategory */
  uint32_t    capabilities;   /* PluginCapability bitmask */
} PluginInfo;

/* ─── Required Functions ─────────────────────────────────── */

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

/* ─── Optional: Template Matching ────────────────────────── */

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

/* ─── Optional: OCR ──────────────────────────────────────── */

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

/* ─── Optional: Custom Action ────────────────────────────── */

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

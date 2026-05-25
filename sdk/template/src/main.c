/**
 * Clicker Plugin Template — edit this file to build your plugin.
 *
 * Build commands:
 *   Windows: cl /LD /O2 main.c /I. /Fe:../windows/example_plugin.dll
 *   Linux:   gcc -shared -fPIC -O2 main.c -I. -o ../linux/example_plugin.so
 *   macOS:   clang -shared -fPIC -O2 main.c -I. -o ../darwin/example_plugin.dylib
 */

#include "clicker_plugin.h"
#include <string.h>

/* ─── Plugin Info ────────────────────────────────────────── */

static PluginInfo g_info = {
    .id          = "com.clicker.example",
    .name        = "示例插件",
    .version     = "1.0.0",
    .author      = "",
    .description = "Clicker 示例插件",
    .category    = PLUGIN_CAT_EXTENSION,
    .capabilities = 0,  /* Set capability flags here, e.g. PLUGIN_CAP_TEMPLATE_MATCH */
};

PLUGIN_EXPORT const PluginInfo* PLUGIN_CALL plugin_get_info(void) {
    return &g_info;
}

/* ─── Lifecycle ──────────────────────────────────────────── */

PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_initialize(void) {
    /* Initialize your plugin here (load models, allocate resources, etc.) */
    return 0;  /* Return 0 on success */
}

PLUGIN_EXPORT void PLUGIN_CALL plugin_dispose(void) {
    /* Cleanup resources here */
}

/* ─── Optional: Template Matching ────────────────────────── */

/*
PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_template_match(
    const uint8_t* region_data, int32_t region_w, int32_t region_h,
    const uint8_t* tpl_data,    int32_t tpl_w,    int32_t tpl_h,
    double threshold,
    PluginMatchResult* out_results, int32_t max_results) {

    if (max_results < 1) return 0;

    int32_t found = 0;

    for (int32_t y = 0; y <= region_h - tpl_h && found < max_results; y += 2) {
        for (int32_t x = 0; x <= region_w - tpl_w && found < max_results; x += 2) {

            double score = 0.0;
            int32_t count = 0;

            for (int32_t ty = 0; ty < tpl_h; ty += 2) {
                for (int32_t tx = 0; tx < tpl_w; tx += 2) {
                    int32_t ri = ((y + ty) * region_w + (x + tx)) * 4;
                    int32_t ti = (ty * tpl_w + tx) * 4;

                    double dr = (double)region_data[ri]     - (double)tpl_data[ti];
                    double dg = (double)region_data[ri + 1] - (double)tpl_data[ti + 1];
                    double db = (double)region_data[ri + 2] - (double)tpl_data[ti + 2];

                    score += 1.0 - (dr*dr + dg*dg + db*db) / (3.0 * 255.0 * 255.0);
                    count++;
                }
            }

            if (count > 0) score /= count;

            if (score >= threshold) {
                out_results[found].x      = x;
                out_results[found].y      = y;
                out_results[found].width  = tpl_w;
                out_results[found].height = tpl_h;
                out_results[found].score  = score;
                found++;
            }
        }
    }

    return found;
}
*/

/* ─── Optional: OCR ──────────────────────────────────────── */

/*
PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_ocr(
    const uint8_t* image_data, int32_t w, int32_t h,
    const char* language,
    PluginOcrResult* out_result) {

    out_result->line_count = 0;
    return 1;
}
*/

/* ─── Optional: Custom Actions ───────────────────────────── */

/*
PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_execute_action(
    const char* action_id,
    const char* params,
    char* out_buf, int32_t out_size) {

    return 1;
}
*/

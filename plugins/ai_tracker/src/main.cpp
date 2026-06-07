/**
 * AI Tracker Plugin — YOLO object detection via ONNX Runtime.
 *
 * Uses ONNX Runtime C API (accessed via OrtGetApiBase) to run
 * YOLOv8/YOLOv11 models for real-time object detection.
 *
 * Build:
 *   build_windows.bat
 */

#include "clicker_plugin.h"
#include "onnxruntime_c_api.h"
#include <cstring>
#include <cstdlib>
#include <cmath>
#include <cstdarg>
#include <vector>
#include <string>
#include <algorithm>
#include <sstream>

#ifdef _WIN32
#include <windows.h>
#include <shlobj.h>

static void dbgLog(const char* fmt, ...) {
    char buf[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    OutputDebugStringA("[ai_tracker] ");
    OutputDebugStringA(buf);
    OutputDebugStringA("\n");
}
#else
#include <dlfcn.h>
#include <limits.h>
#include <stdio.h>

static void dbgLog(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    fprintf(stderr, "[ai_tracker] ");
    vfprintf(stderr, fmt, args);
    fprintf(stderr, "\n");
    va_end(args);
}
#endif

/* ─── Plugin Info ──────────────────────────────────────── */

static PluginInfo g_info = {
    "ai_tracker",
    "AI图像跟踪",
    "1.0.0",
    "Clicker",
    "基于ONNX Runtime的YOLO目标检测与跟踪",
    PLUGIN_CAT_VISION,
    PLUGIN_CAP_OBJECT_DETECT | PLUGIN_CAP_TEMPLATE_MATCH | PLUGIN_CAP_CUSTOM,
};

/* ─── Detection Result ─────────────────────────────────── */

struct Detection {
    float x, y, w, h;
    float confidence;
    int class_id;
};

/* ─── Plugin State ─────────────────────────────────────── */

struct TrackerState {
    bool available;
    bool initialized;
    bool model_loaded;

#ifdef _WIN32
    HMODULE ort_lib;
#else
    void* ort_lib;
#endif
    const OrtApi* ort;
    OrtEnv* env;
    OrtSession* session;
    OrtMemoryInfo* mem_info;

    int input_width;
    int input_height;
    int num_classes;
    std::vector<std::string> class_names;

    float confidence_threshold;
    float nms_threshold;
    int max_detections;

    std::vector<float> input_buffer;

    TrackerState()
        : available(false), initialized(false), model_loaded(false),
          ort_lib(nullptr), ort(nullptr), env(nullptr), session(nullptr), mem_info(nullptr),
          input_width(640), input_height(640), num_classes(80),
          confidence_threshold(0.5f), nms_threshold(0.45f), max_detections(20) {}

    void cleanup() {
        if (session && ort) ort->ReleaseSession(session);
        session = nullptr;
        if (mem_info && ort) ort->ReleaseMemoryInfo(mem_info);
        mem_info = nullptr;
        if (env && ort) ort->ReleaseEnv(env);
        env = nullptr;
#ifdef _WIN32
        if (ort_lib) { FreeLibrary(ort_lib); ort_lib = nullptr; }
#else
        if (ort_lib) { dlclose(ort_lib); ort_lib = nullptr; }
#endif
        initialized = false;
        model_loaded = false;
        available = false;
        ort = nullptr;
        input_buffer.clear();
    }
};

static TrackerState g_tracker;

/* ─── COCO 80 Class Names ──────────────────────────────── */

static void initCocoClassNames(std::vector<std::string>& names) {
    names = {
        "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
        "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat",
        "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack",
        "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
        "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
        "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
        "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair",
        "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
        "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator",
        "book", "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush"
    };
}

/* ─── Simple JSON Helpers ──────────────────────────────── */

static std::string jsonGetString(const std::string& json, const std::string& key) {
    std::string search = "\"" + key + "\"";
    size_t pos = json.find(search);
    if (pos == std::string::npos) return "";
    pos = json.find(':', pos + search.length());
    if (pos == std::string::npos) return "";
    pos++;
    while (pos < json.length() && (json[pos] == ' ' || json[pos] == '\t')) pos++;
    if (pos >= json.length()) return "";
    if (json[pos] == '"') {
        std::string result;
        size_t i = pos + 1;
        while (i < json.length()) {
            if (json[i] == '\\' && i + 1 < json.length()) {
                char next = json[i + 1];
                if (next == '"' || next == '\\' || next == '/') result += next;
                else if (next == 'n') result += '\n';
                else if (next == 'r') result += '\r';
                else if (next == 't') result += '\t';
                else result += next;
                i += 2;
            } else if (json[i] == '"') {
                break;
            } else {
                result += json[i];
                i++;
            }
        }
        return result;
    }
    size_t end = pos;
    while (end < json.length() && json[end] != ',' && json[end] != '}' && json[end] != ']') end++;
    return json.substr(pos, end - pos);
}

static int jsonGetInt(const std::string& json, const std::string& key, int def = 0) {
    std::string val = jsonGetString(json, key);
    if (val.empty()) return def;
    return atoi(val.c_str());
}

static double jsonGetDouble(const std::string& json, const std::string& key, double def = 0.0) {
    std::string val = jsonGetString(json, key);
    if (val.empty()) return def;
    return atof(val.c_str());
}

static std::string jsonEscape(const std::string& s) {
    std::string out;
    for (char c : s) {
        if (c == '"') out += "\\\"";
        else if (c == '\\') out += "\\\\";
        else out += c;
    }
    return out;
}

/* ─── ONNX Runtime Dynamic Loading ─────────────────────── */

static bool loadOnnxRuntime() {
#ifdef _WIN32
    std::vector<std::string> search_paths;

    char exePath[MAX_PATH];
    GetModuleFileNameA(NULL, exePath, MAX_PATH);
    char* lastSlash = strrchr(exePath, '\\');
    std::string exe_dir;
    if (lastSlash) {
        *lastSlash = '\0';
        exe_dir = exePath;
    }

    char dllPath[MAX_PATH];
    HMODULE hSelf = NULL;
    if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS, (LPCSTR)&loadOnnxRuntime, &hSelf)) {
        GetModuleFileNameA(hSelf, dllPath, MAX_PATH);
        char* dllSlash = strrchr(dllPath, '\\');
        if (dllSlash) {
            *dllSlash = '\0';
            search_paths.push_back(std::string(dllPath) + "\\onnxruntime.dll");
            search_paths.push_back(std::string(dllPath) + "\\..\\onnxruntime.dll");
        }
        FreeLibrary(hSelf);
    }

    if (!exe_dir.empty()) {
        search_paths.push_back(exe_dir + "\\onnxruntime.dll");
        search_paths.push_back(exe_dir + "\\data\\plugins\\ai_tracker\\onnxruntime.dll");
        search_paths.push_back(exe_dir + "\\data\\plugins\\ai_tracker\\onnxruntime-win-x64-1.21.0\\onnxruntime.dll");
        search_paths.push_back(exe_dir + "\\data\\plugins\\ai_tracker\\onnxruntime-win-x64-1.21.0\\lib\\onnxruntime.dll");
    }

    char base[MAX_PATH];
    if (SUCCEEDED(SHGetFolderPathA(NULL, CSIDL_LOCAL_APPDATA, NULL, 0, base))) {
        search_paths.push_back(std::string(base) + "\\Clicker\\plugins\\ai_tracker\\onnxruntime.dll");
        search_paths.push_back(std::string(base) + "\\Clicker\\data\\plugins\\ai_tracker\\onnxruntime.dll");
    }

    // Helper lambda: try to get ORT API from a loaded DLL
    auto tryGetOrtApi = [](HMODULE lib) -> const OrtApi* {
        if (!lib) return nullptr;
        typedef const OrtApiBase* (ORT_API_CALL *OrtGetApiBaseFn)(void);
        auto get_api_base = (OrtGetApiBaseFn)GetProcAddress(lib, "OrtGetApiBase");
        if (!get_api_base) return nullptr;
        const OrtApiBase* api_base = get_api_base();
        if (!api_base) return nullptr;
        return api_base->GetApi(ORT_API_VERSION);
    };

    // Build a list of DLL paths to try (full paths first, then system search)
    std::vector<std::pair<std::string, bool>> dll_candidates; // (path, is_full_path)

    // Full paths first — these are preferred because they avoid loading wrong versions
    for (const auto& path : search_paths) {
        dll_candidates.push_back({path, true});
    }

    // System path search as last resort
    dll_candidates.push_back({"onnxruntime.dll", false});

    for (auto& [path, is_full_path] : dll_candidates) {
        if (is_full_path) {
            dbgLog("Trying: %s", path.c_str());
        } else {
            dbgLog("Trying system path search");
        }

        HMODULE lib = LoadLibraryA(path.c_str());
        if (!lib) continue;

        const OrtApi* ort_api = tryGetOrtApi(lib);
        if (ort_api) {
            dbgLog("ONNX Runtime found at: %s (API v%d OK)", path.c_str(), ORT_API_VERSION);
            g_tracker.ort_lib = lib;
            g_tracker.ort = ort_api;
            g_tracker.available = true;
            return true;
        }

        // DLL loaded but API version mismatch — free it and try next
        dbgLog("ONNX Runtime at '%s' has wrong API version (need v%d), skipping", path.c_str(), ORT_API_VERSION);
        FreeLibrary(lib);
    }

    dbgLog("ONNX Runtime NOT found with compatible API v%d (searched %d paths)", ORT_API_VERSION, (int)dll_candidates.size());
    return false;
#else
    // Linux: try dlopen
    g_tracker.ort_lib = dlopen("libonnxruntime.so", RTLD_NOW);
    if (!g_tracker.ort_lib) return false;

    typedef const OrtApiBase* (*OrtGetApiBaseFn)(void);
    auto get_api_base = (OrtGetApiBaseFn)dlsym(g_tracker.ort_lib, "OrtGetApiBase");
    if (!get_api_base) return false;

    const OrtApiBase* api_base = get_api_base();
    if (!api_base) return false;

    const OrtApi* ort_api = api_base->GetApi(ORT_API_VERSION);
    if (!ort_api) return false;

    g_tracker.ort = ort_api;
    g_tracker.available = true;
    return true;
#endif
}

/* ─── YOLO Preprocessing ───────────────────────────────── */

static void preprocessBgra(const uint8_t* bgra_data, int src_w, int src_h,
                           float* output, int dst_w, int dst_h) {
    float scale = std::min((float)dst_w / src_w, (float)dst_h / src_h);
    int new_w = (int)(src_w * scale);
    int new_h = (int)(src_h * scale);
    int pad_x = (dst_w - new_w) / 2;
    int pad_y = (dst_h - new_h) / 2;

    int total = dst_w * dst_h * 3;
    for (int i = 0; i < total; i++) {
        output[i] = 114.0f / 255.0f;
    }

    for (int dy = 0; dy < new_h; dy++) {
        float sy = (dy + 0.5f) / scale - 0.5f;
        int sy0 = (int)std::floor(sy);
        int sy1 = std::min(sy0 + 1, src_h - 1);
        sy0 = std::max(0, sy0);
        float fy = sy - sy0;

        for (int dx = 0; dx < new_w; dx++) {
            float sx = (dx + 0.5f) / scale - 0.5f;
            int sx0 = (int)std::floor(sx);
            int sx1 = std::min(sx0 + 1, src_w - 1);
            sx0 = std::max(0, sx0);
            float fx = sx - sx0;

            for (int c = 0; c < 3; c++) {
                int src_c = (c == 0) ? 2 : (c == 2) ? 0 : 1;
                float v00 = (float)bgra_data[(sy0 * src_w + sx0) * 4 + src_c];
                float v10 = (float)bgra_data[(sy0 * src_w + sx1) * 4 + src_c];
                float v01 = (float)bgra_data[(sy1 * src_w + sx0) * 4 + src_c];
                float v11 = (float)bgra_data[(sy1 * src_w + sx1) * 4 + src_c];
                float v = v00 * (1 - fx) * (1 - fy) + v10 * fx * (1 - fy) +
                          v01 * (1 - fx) * fy + v11 * fx * fy;
                int out_idx = c * dst_w * dst_h + (pad_y + dy) * dst_w + (pad_x + dx);
                output[out_idx] = v / 255.0f;
            }
        }
    }
}

/* ─── YOLO Postprocessing ──────────────────────────────── */

static float iou(const Detection& a, const Detection& b) {
    float x1 = std::max(a.x, b.x);
    float y1 = std::max(a.y, b.y);
    float x2 = std::min(a.x + a.w, b.x + b.w);
    float y2 = std::min(a.y + a.h, b.y + b.h);
    float inter = std::max(0.0f, x2 - x1) * std::max(0.0f, y2 - y1);
    float area_a = a.w * a.h;
    float area_b = b.w * b.h;
    return inter / (area_a + area_b - inter + 1e-6f);
}

static std::vector<Detection> nms(std::vector<Detection>& dets, float threshold) {
    std::sort(dets.begin(), dets.end(), [](const Detection& a, const Detection& b) {
        return a.confidence > b.confidence;
    });
    std::vector<bool> suppressed(dets.size(), false);
    std::vector<Detection> result;
    for (size_t i = 0; i < dets.size(); i++) {
        if (suppressed[i]) continue;
        result.push_back(dets[i]);
        for (size_t j = i + 1; j < dets.size(); j++) {
            if (suppressed[j]) continue;
            if (iou(dets[i], dets[j]) > threshold) {
                suppressed[j] = true;
            }
        }
    }
    return result;
}

static std::vector<Detection> postprocessYolo(const float* output, int num_outputs,
                                               int region_w, int region_h,
                                               float conf_thresh, float nms_thresh,
                                               int max_det, int num_classes) {
    int num_preds = num_outputs;
    std::vector<Detection> dets;

    float scale = std::min((float)g_tracker.input_width / region_w, (float)g_tracker.input_height / region_h);
    int new_w = (int)(region_w * scale);
    int new_h = (int)(region_h * scale);
    float pad_x = ((float)g_tracker.input_width - new_w) / 2.0f;
    float pad_y = ((float)g_tracker.input_height - new_h) / 2.0f;

    for (int i = 0; i < num_preds; i++) {
        const float* row = output + i * (4 + num_classes);
        float cx = row[0];
        float cy = row[1];
        float w = row[2];
        float h = row[3];

        int best_class = 0;
        float best_score = 0;
        for (int c = 0; c < num_classes; c++) {
            float score = row[4 + c];
            if (score > best_score) {
                best_score = score;
                best_class = c;
            }
        }

        if (best_score < conf_thresh) continue;

        float orig_cx = (cx - pad_x) / scale;
        float orig_cy = (cy - pad_y) / scale;
        float orig_w = w / scale;
        float orig_h = h / scale;

        Detection det;
        det.x = orig_cx - orig_w / 2;
        det.y = orig_cy - orig_h / 2;
        det.w = orig_w;
        det.h = orig_h;
        det.confidence = best_score;
        det.class_id = best_class;
        dets.push_back(det);

        if ((int)dets.size() >= max_det * 2) break;
    }

    return nms(dets, nms_thresh);
}

/* ─── Plugin API ───────────────────────────────────────── */

PLUGIN_EXPORT const PluginInfo* PLUGIN_CALL plugin_get_info(void) {
    return &g_info;
}

PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_initialize(void) {
    dbgLog("plugin_initialize called, initialized=%d, available=%d, ort_lib=%p",
           g_tracker.initialized, g_tracker.available, (void*)g_tracker.ort_lib);
    if (g_tracker.initialized) return 0;

    if (!loadOnnxRuntime()) {
        g_tracker.available = false;
        dbgLog("loadOnnxRuntime FAILED");
        return -1;
    }

    dbgLog("loadOnnxRuntime OK, ort_api=%p", (void*)g_tracker.ort);

    initCocoClassNames(g_tracker.class_names);
    g_tracker.num_classes = (int)g_tracker.class_names.size();

    int input_size = 3 * g_tracker.input_width * g_tracker.input_height;
    g_tracker.input_buffer.resize(input_size, 114.0f / 255.0f);

    g_tracker.initialized = true;
    g_tracker.available = true;
    dbgLog("initialized OK, input=%dx%d, classes=%d", g_tracker.input_width, g_tracker.input_height, g_tracker.num_classes);
    return 0;
}

PLUGIN_EXPORT void PLUGIN_CALL plugin_dispose(void) {
    g_tracker.cleanup();
}

/* ─── Template Matching (NCC fallback) ─────────────────── */

PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_template_match(
    const uint8_t* region_data, int32_t region_w, int32_t region_h,
    const uint8_t* tpl_data,    int32_t tpl_w,    int32_t tpl_h,
    double threshold,
    PluginMatchResult* out_results, int32_t max_results) {

    if (max_results < 1) return 0;

    int32_t found = 0;
    int step = 2;

    for (int32_t y = 0; y <= region_h - tpl_h && found < max_results; y += step) {
        for (int32_t x = 0; x <= region_w - tpl_w && found < max_results; x += step) {
            double score = 0.0;
            int count = 0;

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

/* ─── Custom Actions ───────────────────────────────────── */

PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_execute_action(
    const char* action_id,
    const char* params,
    char* out_buf, int32_t out_size) {

    auto& ort = g_tracker.ort;

    if (strcmp(action_id, "load_model") == 0) {
        std::string params_str(params ? params : "");
        std::string model_path = jsonGetString(params_str, "model_path");

        dbgLog("load_model: path=%s", model_path.c_str());

        if (model_path.empty()) {
            if (out_buf && out_size > 0) {
                strncpy(out_buf, "{\"error\":\"model_path is required\"}", out_size - 1);
                out_buf[out_size - 1] = '\0';
            }
            return 1;
        }

        if (!g_tracker.available || !ort) {
            if (out_buf && out_size > 0) {
                strncpy(out_buf, "{\"error\":\"onnxruntime_not_available\"}", out_size - 1);
                out_buf[out_size - 1] = '\0';
            }
            return 1;
        }

        if (g_tracker.session) {
            ort->ReleaseSession(g_tracker.session);
            g_tracker.session = nullptr;
            g_tracker.model_loaded = false;
        }

        if (!g_tracker.env) {
            OrtStatus* status = ort->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "ai_tracker", &g_tracker.env);
            if (status != nullptr || !g_tracker.env) {
                if (out_buf && out_size > 0) {
                    const char* msg = (status != nullptr) ? ort->GetErrorMessage(status) : "null";
                    snprintf(out_buf, out_size, "{\"error\":\"create_env_failed\",\"detail\":\"%s\"}", msg);
                    if (status) ort->ReleaseStatus(status);
                }
                return 1;
            }
        }

        if (!g_tracker.mem_info) {
            OrtStatus* status = ort->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &g_tracker.mem_info);
            if (status != nullptr || !g_tracker.mem_info) {
                if (out_buf && out_size > 0) {
                    const char* msg = (status != nullptr) ? ort->GetErrorMessage(status) : "null";
                    snprintf(out_buf, out_size, "{\"error\":\"create_mem_info_failed\",\"detail\":\"%s\"}", msg);
                    if (status) ort->ReleaseStatus(status);
                }
                return 1;
            }
        }

        OrtSessionOptions* opts = nullptr;
        OrtStatus* status = ort->CreateSessionOptions(&opts);
        if (status != nullptr || !opts) {
            if (out_buf && out_size > 0) {
                const char* msg = (status != nullptr) ? ort->GetErrorMessage(status) : "null";
                snprintf(out_buf, out_size, "{\"error\":\"create_opts_failed\",\"detail\":\"%s\"}", msg);
                if (status) ort->ReleaseStatus(status);
            }
            return 1;
        }

        ort->SetIntraOpNumThreads(opts, 1);
        ort->SetSessionGraphOptimizationLevel(opts, ORT_ENABLE_BASIC);

#ifdef _WIN32
        const wchar_t* wmodel_path = nullptr;
        int wlen = MultiByteToWideChar(CP_UTF8, 0, model_path.c_str(), -1, nullptr, 0);
        std::vector<wchar_t> wpath(wlen);
        MultiByteToWideChar(CP_UTF8, 0, model_path.c_str(), -1, wpath.data(), wlen);
        wmodel_path = wpath.data();
        status = ort->CreateSession(g_tracker.env, wmodel_path, opts, &g_tracker.session);
#else
        status = ort->CreateSession(g_tracker.env, model_path.c_str(), opts, &g_tracker.session);
#endif

        ort->ReleaseSessionOptions(opts);

        if (status != nullptr || !g_tracker.session) {
            if (out_buf && out_size > 0) {
                const char* msg = (status != nullptr) ? ort->GetErrorMessage(status) : "null";
                snprintf(out_buf, out_size, "{\"error\":\"create_session_failed\",\"detail\":\"%s\"}", msg);
                if (status) ort->ReleaseStatus(status);
            }
            return 1;
        }

        g_tracker.model_loaded = true;
        dbgLog("load_model: SUCCESS");
        if (out_buf && out_size > 0) {
            strncpy(out_buf, "{\"success\":true}", out_size - 1);
            out_buf[out_size - 1] = '\0';
        }
        return 0;
    }

    if (strcmp(action_id, "detect_objects") == 0) {
        if (!g_tracker.model_loaded || !g_tracker.session || !g_tracker.mem_info || !ort) {
            dbgLog("detect_objects: model NOT ready (loaded=%d session=%d mem=%d ort=%d)",
                g_tracker.model_loaded, !!g_tracker.session, !!g_tracker.mem_info, !!ort);
            if (out_buf && out_size > 0) {
                snprintf(out_buf, out_size,
                    "{\"error\":\"model_not_loaded\",\"model_loaded\":%s,\"session\":%s,\"mem_info\":%s,\"ort\":%s}",
                    g_tracker.model_loaded ? "true" : "false",
                    g_tracker.session ? "true" : "false",
                    g_tracker.mem_info ? "true" : "false",
                    ort ? "true" : "false");
            }
            return 1;
        }

        std::string params_str(params ? params : "");
        int region_w = jsonGetInt(params_str, "region_w", 0);
        int region_h = jsonGetInt(params_str, "region_h", 0);
        double confidence = jsonGetDouble(params_str, "confidence", 0.5);
        std::string target_class = jsonGetString(params_str, "target_class");

        if (region_w <= 0 || region_h <= 0) {
            if (out_buf && out_size > 0) {
                strncpy(out_buf, "{\"error\":\"invalid_region\"}", out_size - 1);
                out_buf[out_size - 1] = '\0';
            }
            return 1;
        }

        const uint8_t* pixel_data = nullptr;
        std::string ptr_str = jsonGetString(params_str, "pixel_data_ptr");
        if (!ptr_str.empty()) {
            pixel_data = (const uint8_t*)(uintptr_t)strtoull(ptr_str.c_str(), nullptr, 16);
        }

        if (!pixel_data) {
            dbgLog("detect_objects: no pixel data (ptr_str='%s')", ptr_str.c_str());
            if (out_buf && out_size > 0) {
                strncpy(out_buf, "{\"error\":\"no_pixel_data\"}", out_size - 1);
                out_buf[out_size - 1] = '\0';
            }
            return 1;
        }

        // Log first few pixel values for debugging
        dbgLog("detect_objects: first pixels BGRA=[%d,%d,%d,%d] region=%dx%d ptr=0x%s",
            pixel_data[0], pixel_data[1], pixel_data[2], pixel_data[3],
            region_w, region_h, ptr_str.c_str());

        preprocessBgra(pixel_data, region_w, region_h,
                       g_tracker.input_buffer.data(),
                       g_tracker.input_width, g_tracker.input_height);

        int64_t input_shape[] = {1, 3, (int64_t)g_tracker.input_height, (int64_t)g_tracker.input_width};
        OrtValue* input_tensor = nullptr;
        OrtStatus* status = ort->CreateTensorWithDataAsOrtValue(
            g_tracker.mem_info,
            g_tracker.input_buffer.data(),
            g_tracker.input_buffer.size() * sizeof(float),
            input_shape,
            4,
            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
            &input_tensor);

        if (status != nullptr || !input_tensor) {
            if (out_buf && out_size > 0) {
                const char* msg = (status != nullptr) ? ort->GetErrorMessage(status) : "null";
                snprintf(out_buf, out_size, "{\"error\":\"create_tensor_failed\",\"detail\":\"%s\"}", msg);
                if (status) ort->ReleaseStatus(status);
            }
            return 1;
        }

        const char* input_names[] = {"images"};
        const char* output_names[] = {"output0"};
        OrtValue* output_tensor = nullptr;

        status = ort->Run(
            g_tracker.session,
            nullptr,
            input_names,
            (const OrtValue* const*)&input_tensor,
            1,
            output_names,
            1,
            &output_tensor);

        ort->ReleaseValue(input_tensor);

        if (status != nullptr || !output_tensor) {
            if (out_buf && out_size > 0) {
                const char* msg = (status != nullptr) ? ort->GetErrorMessage(status) : "null";
                snprintf(out_buf, out_size, "{\"error\":\"inference_failed\",\"detail\":\"%s\"}", msg);
                if (status) ort->ReleaseStatus(status);
            }
            return 1;
        }

        float* output_data = nullptr;
        status = ort->GetTensorMutableData(output_tensor, (void**)&output_data);

        if (status != nullptr || !output_data) {
            ort->ReleaseValue(output_tensor);
            if (out_buf && out_size > 0) {
                const char* msg = (status != nullptr) ? ort->GetErrorMessage(status) : "null";
                snprintf(out_buf, out_size, "{\"error\":\"get_output_failed\",\"detail\":\"%s\"}", msg);
                if (status) ort->ReleaseStatus(status);
            }
            return 1;
        }

        OrtTensorTypeAndShapeInfo* shape_info = nullptr;
        int64_t output_dims[4] = {};
        status = ort->GetTensorTypeAndShape(output_tensor, &shape_info);
        if (status == nullptr && shape_info) {
            size_t dim_count = 0;
            ort->GetDimensionsCount(shape_info, &dim_count);
            if (dim_count <= 4) {
                ort->GetDimensions(shape_info, output_dims, dim_count);
            }
            ort->ReleaseTensorTypeAndShapeInfo(shape_info);
        }

        int num_preds = 8400;
        int num_attrs = 4 + g_tracker.num_classes;
        if (output_dims[0] == 1 && output_dims[1] > 0 && output_dims[2] > 0) {
            num_attrs = (int)output_dims[1];
            num_preds = (int)output_dims[2];
        }

        dbgLog("detect_objects: output shape=[%d,%d,%d,%d] preds=%d attrs=%d",
            (int)output_dims[0], (int)output_dims[1], (int)output_dims[2], (int)output_dims[3],
            num_preds, num_attrs);

        std::vector<float> transposed(num_preds * num_attrs);
        for (int a = 0; a < num_attrs; a++) {
            for (int p = 0; p < num_preds; p++) {
                transposed[p * num_attrs + a] = output_data[a * num_preds + p];
            }
        }

        ort->ReleaseValue(output_tensor);

        float conf = (float)confidence;
        if (conf <= 0) conf = g_tracker.confidence_threshold;

        std::vector<Detection> dets = postprocessYolo(
            transposed.data(), num_preds,
            region_w, region_h,
            conf, g_tracker.nms_threshold,
            g_tracker.max_detections, g_tracker.num_classes);

        dbgLog("detect_objects: raw_dets=%d conf=%.2f region=%dx%d",
            (int)dets.size(), conf, region_w, region_h);

        std::vector<Detection> filtered;
        for (const auto& det : dets) {
            if (!target_class.empty()) {
                if (det.class_id >= 0 && det.class_id < (int)g_tracker.class_names.size()) {
                    if (g_tracker.class_names[det.class_id] != target_class) continue;
                }
            }
            filtered.push_back(det);
        }

        std::ostringstream json;
        json << "{\"detections\":[";
        for (size_t i = 0; i < filtered.size(); i++) {
            const auto& d = filtered[i];
            if (i > 0) json << ",";
            const char* cls_name = (d.class_id >= 0 && d.class_id < (int)g_tracker.class_names.size())
                ? g_tracker.class_names[d.class_id].c_str() : "unknown";
            json << "{\"x\":" << (int)d.x
                 << ",\"y\":" << (int)d.y
                 << ",\"w\":" << (int)d.w
                 << ",\"h\":" << (int)d.h
                 << ",\"confidence\":" << (double)d.confidence
                 << ",\"class_id\":" << d.class_id
                 << ",\"class_name\":\"" << jsonEscape(cls_name) << "\"}";
        }
        json << "],\"count\":" << filtered.size()
             << ",\"debug\":{\"num_preds\":" << num_preds
             << ",\"num_attrs\":" << num_attrs
             << ",\"raw_dets\":" << dets.size()
             << ",\"conf_thresh\":" << conf
             << ",\"region_w\":" << region_w
             << ",\"region_h\":" << region_h
             << "}}";

        std::string result = json.str();
        if (out_buf && out_size > 0) {
            strncpy(out_buf, result.c_str(), out_size - 1);
            out_buf[out_size - 1] = '\0';
        }
        return 0;
    }

    if (strcmp(action_id, "get_status") == 0) {
        if (out_buf && out_size > 0) {
            std::ostringstream json;
            json << "{\"initialized\":" << (g_tracker.initialized ? "true" : "false")
                 << ",\"available\":" << (g_tracker.available ? "true" : "false")
                 << ",\"model_loaded\":" << (g_tracker.model_loaded ? "true" : "false")
                 << ",\"ort_lib\":" << (g_tracker.ort_lib ? "true" : "false")
                 << ",\"ort_api\":" << (g_tracker.ort ? "true" : "false")
                 << "}";
            std::string result = json.str();
            strncpy(out_buf, result.c_str(), out_size - 1);
            out_buf[out_size - 1] = '\0';
        }
        return 0;
    }

    return 1;
}

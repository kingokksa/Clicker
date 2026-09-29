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
#include <cstdint>
#include <vector>
#include <string>
#include <algorithm>
#include <sstream>
#include <fstream>

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
    PLUGIN_CAP_OBJECT_DETECT | PLUGIN_CAP_TEMPLATE_MATCH | PLUGIN_CAP_OCR | PLUGIN_CAP_CUSTOM,
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
    std::string det_input_name;
    std::string det_output_name;

    int input_width;
    int input_height;
    int num_classes;
    bool has_objectness;
    int detector_mode;
    std::vector<std::string> class_names;

    float confidence_threshold;
    float nms_threshold;
    int max_detections;
    float input_scale;

    std::vector<float> input_buffer;

    TrackerState()
        : available(false), initialized(false), model_loaded(false),
          ort_lib(nullptr), ort(nullptr), env(nullptr), session(nullptr), mem_info(nullptr),
          input_width(640), input_height(640), num_classes(80), has_objectness(false),
          detector_mode(0),
          confidence_threshold(0.5f), nms_threshold(0.45f), max_detections(20),
          input_scale(1.0f / 255.0f) {}

    void releaseSession() {
        if (session && ort) ort->ReleaseSession(session);
        session = nullptr;
        model_loaded = false;
        det_input_name.clear();
        det_output_name.clear();
    }

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

/* ─── OCR State (PP-OCRv4 det + rec) ───────────────────── */

struct OcrState {
    OrtSession* det_session;
    OrtSession* rec_session;
    bool loaded;
    std::vector<std::string> keys;
    std::string det_input, det_output;
    std::string rec_input, rec_output;
    float box_thresh;
    float unclip_ratio;
    int max_side;
    int min_size;

    OcrState()
        : det_session(nullptr), rec_session(nullptr), loaded(false),
          box_thresh(0.6f), unclip_ratio(1.8f), max_side(960), min_size(3) {}

    void release() {
        if (g_tracker.ort) {
            if (det_session) g_tracker.ort->ReleaseSession(det_session);
            if (rec_session) g_tracker.ort->ReleaseSession(rec_session);
        }
        det_session = nullptr;
        rec_session = nullptr;
        loaded = false;
    }
};

static OcrState g_ocr;

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
    for (unsigned char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out += (char)c;
                }
        }
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

/* ─── Shared Helpers: session / resize ─────────────────── */

static std::string ortSessionInputName(OrtSession* s, size_t index) {
    if (!g_tracker.ort || !s) return "";
    OrtAllocator* alloc = nullptr;
    if (g_tracker.ort->GetAllocatorWithDefaultOptions(&alloc) != nullptr || !alloc) return "";
    char* name = nullptr;
    OrtStatus* st = g_tracker.ort->SessionGetInputName(s, index, alloc, &name);
    if (st != nullptr) { g_tracker.ort->ReleaseStatus(st); return ""; }
    std::string out = name ? name : "";
    if (name) alloc->Free(alloc, name);
    return out;
}

static std::string ortSessionOutputName(OrtSession* s, size_t index) {
    if (!g_tracker.ort || !s) return "";
    OrtAllocator* alloc = nullptr;
    if (g_tracker.ort->GetAllocatorWithDefaultOptions(&alloc) != nullptr || !alloc) return "";
    char* name = nullptr;
    OrtStatus* st = g_tracker.ort->SessionGetOutputName(s, index, alloc, &name);
    if (st != nullptr) { g_tracker.ort->ReleaseStatus(st); return ""; }
    std::string out = name ? name : "";
    if (name) alloc->Free(alloc, name);
    return out;
}

static OrtSession* createSessionFromFile(const std::string& path, int threads, std::string& err) {
    auto& ort = g_tracker.ort;
    if (!ort) { err = "ort_not_available"; return nullptr; }
    if (path.empty()) { err = "empty_path"; return nullptr; }

    if (!g_tracker.env) {
        OrtStatus* st = ort->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "ai_tracker", &g_tracker.env);
        if (st != nullptr || !g_tracker.env) {
            err = (st != nullptr) ? ort->GetErrorMessage(st) : "create_env_failed";
            if (st) ort->ReleaseStatus(st);
            return nullptr;
        }
    }

    OrtSessionOptions* opts = nullptr;
    OrtStatus* st = ort->CreateSessionOptions(&opts);
    if (st != nullptr || !opts) {
        err = (st != nullptr) ? ort->GetErrorMessage(st) : "create_opts_failed";
        if (st) ort->ReleaseStatus(st);
        return nullptr;
    }
    ort->SetIntraOpNumThreads(opts, threads > 0 ? threads : 1);
    ort->SetSessionGraphOptimizationLevel(opts, ORT_ENABLE_BASIC);

    OrtSession* session = nullptr;
#ifdef _WIN32
    int wlen = MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, nullptr, 0);
    std::vector<wchar_t> wpath(wlen > 0 ? (size_t)wlen : 1);
    MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, wpath.data(), (int)wpath.size());
    st = ort->CreateSession(g_tracker.env, wpath.data(), opts, &session);
#else
    st = ort->CreateSession(g_tracker.env, path.c_str(), opts, &session);
#endif
    ort->ReleaseSessionOptions(opts);

    if (st != nullptr || !session) {
        err = (st != nullptr) ? ort->GetErrorMessage(st) : "create_session_failed";
        if (st) ort->ReleaseStatus(st);
        return nullptr;
    }
    return session;
}

static void resizeBgraToRgbFloat(const uint8_t* src, int sw, int sh,
                                 float* dst, int dw, int dh,
                                 float mean_r, float mean_g, float mean_b,
                                 float std_r, float std_g, float std_b) {
    const size_t plane = (size_t)dw * dh;
    for (int dy = 0; dy < dh; dy++) {
        float sy = ((dy + 0.5f) * sh / dh) - 0.5f;
        int sy0 = (int)std::floor(sy);
        float fy = sy - sy0;
        int sy1 = sy0 + 1;
        sy0 = std::max(0, std::min(sh - 1, sy0));
        sy1 = std::max(0, std::min(sh - 1, sy1));
        for (int dx = 0; dx < dw; dx++) {
            float sx = ((dx + 0.5f) * sw / dw) - 0.5f;
            int sx0 = (int)std::floor(sx);
            float fx = sx - sx0;
            int sx1 = sx0 + 1;
            sx0 = std::max(0, std::min(sw - 1, sx0));
            sx1 = std::max(0, std::min(sw - 1, sx1));

            const uint8_t* p00 = src + ((size_t)sy0 * sw + sx0) * 4;
            const uint8_t* p10 = src + ((size_t)sy0 * sw + sx1) * 4;
            const uint8_t* p01 = src + ((size_t)sy1 * sw + sx0) * 4;
            const uint8_t* p11 = src + ((size_t)sy1 * sw + sx1) * 4;

            float w00 = (1 - fx) * (1 - fy), w10 = fx * (1 - fy);
            float w01 = (1 - fx) * fy,       w11 = fx * fy;

            float b = p00[0] * w00 + p10[0] * w10 + p01[0] * w01 + p11[0] * w11;
            float g = p00[1] * w00 + p10[1] * w10 + p01[1] * w01 + p11[1] * w11;
            float r = p00[2] * w00 + p10[2] * w10 + p01[2] * w01 + p11[2] * w11;

            size_t idx = (size_t)dy * dw + dx;
            dst[idx]           = (r / 255.0f - mean_r) / std_r;
            dst[plane + idx]   = (g / 255.0f - mean_g) / std_g;
            dst[plane * 2 + idx] = (b / 255.0f - mean_b) / std_b;
        }
    }
}

/* ─── YOLO Preprocessing ───────────────────────────────── */

static void preprocessBgra(const uint8_t* bgra_data, int src_w, int src_h,
                           float* output, int dst_w, int dst_h, float scale_val) {
    float scale = std::min((float)dst_w / src_w, (float)dst_h / src_h);
    int new_w = (int)(src_w * scale);
    int new_h = (int)(src_h * scale);
    int pad_x = (dst_w - new_w) / 2;
    int pad_y = (dst_h - new_h) / 2;

    int total = dst_w * dst_h * 3;
    for (int i = 0; i < total; i++) {
        output[i] = 114.0f * scale_val;
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
                output[out_idx] = v * scale_val;
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

static std::vector<Detection> postprocessDetections(const float* rows, int num_preds, int num_attrs,
                                                    bool has_objectness, int num_classes,
                                                    int region_w, int region_h,
                                                    float conf_thresh, float nms_thresh,
                                                    int max_det,
                                                    int input_w, int input_h) {
    std::vector<Detection> dets;

    float scale = std::min((float)input_w / region_w, (float)input_h / region_h);
    int new_w = (int)(region_w * scale);
    int new_h = (int)(region_h * scale);
    float pad_x = ((float)input_w - new_w) / 2.0f;
    float pad_y = ((float)input_h - new_h) / 2.0f;

    const int cls_off = has_objectness ? 5 : 4;

    for (int i = 0; i < num_preds; i++) {
        const float* row = rows + (size_t)i * num_attrs;
        float cx = row[0];
        float cy = row[1];
        float w = row[2];
        float h = row[3];

        float obj = has_objectness ? row[4] : 1.0f;
        if (obj <= 0.0f) continue;

        int best_class = 0;
        float best_score = 0;
        for (int c = 0; c < num_classes && cls_off + c < num_attrs; c++) {
            float score = row[cls_off + c];
            if (score > best_score) {
                best_score = score;
                best_class = c;
            }
        }

        float score = obj * best_score;
        if (score < conf_thresh) continue;

        float orig_cx = (cx - pad_x) / scale;
        float orig_cy = (cy - pad_y) / scale;
        float orig_w = w / scale;
        float orig_h = h / scale;

        Detection det;
        det.x = orig_cx - orig_w / 2;
        det.y = orig_cy - orig_h / 2;
        det.w = orig_w;
        det.h = orig_h;
        det.confidence = score;
        det.class_id = best_class;
        dets.push_back(det);

        if ((int)dets.size() >= max_det * 2) break;
    }

    return nms(dets, nms_thresh);
}

/* ─── OCR Pipeline (PP-OCRv4 DB det + CTC rec) ─────────── */

static bool runOcrRegion(const uint8_t* pixels, int region_w, int region_h,
                         float det_threshold, float box_threshold,
                         std::string& out_json, std::string& err) {
    auto& ort = g_tracker.ort;
    if (!ort || !g_ocr.loaded || !g_ocr.det_session || !g_ocr.rec_session) {
        err = "ocr_not_loaded";
        return false;
    }
    if (!g_tracker.mem_info) {
        err = "mem_info_missing";
        return false;
    }

    // ---- detection preprocessing ----
    float ratio = std::min(1.0f, (float)g_ocr.max_side / (float)std::max(region_w, region_h));
    int det_w = std::lround(region_w * ratio);
    int det_h = std::lround(region_h * ratio);
    det_w = std::max(32, (det_w + 31) / 32 * 32);
    det_h = std::max(32, (det_h + 31) / 32 * 32);

    std::vector<float> det_in((size_t)3 * det_w * det_h);
    resizeBgraToRgbFloat(pixels, region_w, region_h, det_in.data(), det_w, det_h,
                         0.485f, 0.456f, 0.406f, 0.229f, 0.224f, 0.225f);

    int64_t det_shape[] = {1, 3, (int64_t)det_h, (int64_t)det_w};
    OrtValue* det_tensor = nullptr;
    OrtStatus* st = ort->CreateTensorWithDataAsOrtValue(
        g_tracker.mem_info, det_in.data(), det_in.size() * sizeof(float),
        det_shape, 4, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &det_tensor);
    if (st != nullptr || !det_tensor) {
        err = (st != nullptr) ? ort->GetErrorMessage(st) : "det_tensor_failed";
        if (st) ort->ReleaseStatus(st);
        return false;
    }

    const char* det_in_names[] = { g_ocr.det_input.c_str() };
    const char* det_out_names[] = { g_ocr.det_output.c_str() };
    OrtValue* det_out = nullptr;
    st = ort->Run(g_ocr.det_session, nullptr, det_in_names,
                  (const OrtValue* const*)&det_tensor, 1, det_out_names, 1, &det_out);
    ort->ReleaseValue(det_tensor);
    if (st != nullptr || !det_out) {
        err = (st != nullptr) ? ort->GetErrorMessage(st) : "det_run_failed";
        if (st) ort->ReleaseStatus(st);
        return false;
    }

    float* prob = nullptr;
    st = ort->GetTensorMutableData(det_out, (void**)&prob);
    if (st != nullptr || !prob) {
        ort->ReleaseValue(det_out);
        err = (st != nullptr) ? ort->GetErrorMessage(st) : "det_output_failed";
        if (st) ort->ReleaseStatus(st);
        return false;
    }

    // ---- connected components + unclip ----
    struct OcrBox { float x0, y0, x1, y1; };
    std::vector<OcrBox> boxes;
    {
        const size_t n = (size_t)det_w * det_h;
        std::vector<uint8_t> visited(n, 0);
        std::vector<int32_t> stack;
        const float thr = det_threshold > 0.0f ? det_threshold : 0.3f;
        const float box_thr = box_threshold > 0.0f ? box_threshold : g_ocr.box_thresh;

        for (int sy = 0; sy < det_h; sy++) {
            for (int sx = 0; sx < det_w; sx++) {
                size_t start = (size_t)sy * det_w + sx;
                if (visited[start] || prob[start] <= thr) continue;

                stack.clear();
                stack.push_back((int32_t)start);
                visited[start] = 1;

                int minx = sx, maxx = sx, miny = sy, maxy = sy, count = 0;
                double sum = 0.0;

                while (!stack.empty()) {
                    int32_t cur = stack.back();
                    stack.pop_back();
                    int cy = (int)(cur / det_w);
                    int cx = (int)(cur % det_w);
                    sum += prob[cur];
                    count++;
                    if (cx < minx) minx = cx;
                    if (cx > maxx) maxx = cx;
                    if (cy < miny) miny = cy;
                    if (cy > maxy) maxy = cy;

                    size_t ni;
                    if (cx > 0)         { ni = (size_t)cy * det_w + (cx - 1); if (!visited[ni] && prob[ni] > thr) { visited[ni] = 1; stack.push_back((int32_t)ni); } }
                    if (cx + 1 < det_w) { ni = (size_t)cy * det_w + (cx + 1); if (!visited[ni] && prob[ni] > thr) { visited[ni] = 1; stack.push_back((int32_t)ni); } }
                    if (cy > 0)         { ni = (size_t)(cy - 1) * det_w + cx; if (!visited[ni] && prob[ni] > thr) { visited[ni] = 1; stack.push_back((int32_t)ni); } }
                    if (cy + 1 < det_h) { ni = (size_t)(cy + 1) * det_w + cx; if (!visited[ni] && prob[ni] > thr) { visited[ni] = 1; stack.push_back((int32_t)ni); } }
                }

                int bw = maxx - minx + 1;
                int bh = maxy - miny + 1;
                if (bw < g_ocr.min_size || bh < g_ocr.min_size) continue;

                float score = (float)(sum / (count > 0 ? count : 1));
                if (score < box_thr) continue;

                double area = (double)count;
                double peri = 2.0 * (bw + bh);
                float d = (float)(area * g_ocr.unclip_ratio / (peri > 0.0 ? peri : 1.0));

                OcrBox b;
                b.x0 = (float)minx - d;
                b.y0 = (float)miny - d;
                b.x1 = (float)maxx + d;
                b.y1 = (float)maxy + d;
                boxes.push_back(b);
            }
        }
    }

    ort->ReleaseValue(det_out);

    // ---- det coords -> region coords, sort top-to-bottom ----
    float mx = (float)region_w / (float)det_w;
    float my = (float)region_h / (float)det_h;
    for (auto& b : boxes) {
        b.x0 *= mx; b.y0 *= my; b.x1 *= mx; b.y1 *= my;
    }
    std::sort(boxes.begin(), boxes.end(), [](const OcrBox& a, const OcrBox& b) {
        if (std::fabs(a.y0 - b.y0) > 8.0f) return a.y0 < b.y0;
        return a.x0 < b.x0;
    });

    // ---- recognition per box ----
    const int rec_h = 48;
    std::ostringstream json;
    json << "{\"lines\":[";
    std::string full;
    int emitted = 0;

    for (const auto& b : boxes) {
        int cx0 = std::max(0, (int)std::floor(b.x0) - 3);
        int cy0 = std::max(0, (int)std::floor(b.y0) - 3);
        int cx1 = std::min(region_w, (int)std::ceil(b.x1) + 3);
        int cy1 = std::min(region_h, (int)std::ceil(b.y1) + 3);
        int cw = cx1 - cx0;
        int ch = cy1 - cy0;
        if (cw < 3 || ch < 3) continue;

        int rec_w = std::max(8, (int)std::lround((double)cw * rec_h / ch));
        if (rec_w > 1280) rec_w = 1280;

        std::vector<uint8_t> crop((size_t)cw * ch * 4);
        for (int y = 0; y < ch; y++) {
            std::memcpy(crop.data() + (size_t)y * cw * 4,
                        pixels + ((size_t)(cy0 + y) * region_w + cx0) * 4,
                        (size_t)cw * 4);
        }

        std::vector<float> rec_in((size_t)3 * rec_w * rec_h);
        resizeBgraToRgbFloat(crop.data(), cw, ch, rec_in.data(), rec_w, rec_h,
                             0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f);

        int64_t rec_shape[] = {1, 3, (int64_t)rec_h, (int64_t)rec_w};
        OrtValue* rec_tensor = nullptr;
        st = ort->CreateTensorWithDataAsOrtValue(
            g_tracker.mem_info, rec_in.data(), rec_in.size() * sizeof(float),
            rec_shape, 4, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &rec_tensor);
        if (st != nullptr || !rec_tensor) {
            if (st) ort->ReleaseStatus(st);
            continue;
        }

        const char* rec_in_names[] = { g_ocr.rec_input.c_str() };
        const char* rec_out_names[] = { g_ocr.rec_output.c_str() };
        OrtValue* rec_out = nullptr;
        st = ort->Run(g_ocr.rec_session, nullptr, rec_in_names,
                      (const OrtValue* const*)&rec_tensor, 1, rec_out_names, 1, &rec_out);
        ort->ReleaseValue(rec_tensor);
        if (st != nullptr || !rec_out) {
            if (st) ort->ReleaseStatus(st);
            continue;
        }

        float* logits = nullptr;
        st = ort->GetTensorMutableData(rec_out, (void**)&logits);
        if (st != nullptr || !logits) {
            ort->ReleaseValue(rec_out);
            if (st) ort->ReleaseStatus(st);
            continue;
        }

        int seq = 0, classes = 0;
        OrtTensorTypeAndShapeInfo* si = nullptr;
        if (ort->GetTensorTypeAndShape(rec_out, &si) == nullptr && si) {
            size_t nd = 0;
            ort->GetDimensionsCount(si, &nd);
            int64_t dims[3] = {};
            if (nd >= 3) {
                ort->GetDimensions(si, dims, nd);
                seq = (int)dims[1];
                classes = (int)dims[2];
            }
            ort->ReleaseTensorTypeAndShapeInfo(si);
        }
        if (seq <= 0 || classes <= 0) {
            ort->ReleaseValue(rec_out);
            continue;
        }

        const int key_count = (int)g_ocr.keys.size();
        std::string text;
        double conf_sum = 0.0;
        int conf_cnt = 0;
        int prev = -1;

        for (int t = 0; t < seq; t++) {
            const float* row = logits + (size_t)t * classes;
            int best = 0;
            float bestv = row[0];
            for (int k = 1; k < classes; k++) {
                if (row[k] > bestv) { bestv = row[k]; best = k; }
            }
            if (best != 0 && best != prev) {
                if (best >= 1 && best <= key_count) text += g_ocr.keys[best - 1];
                else if (best == key_count + 1) text += " ";
                conf_sum += bestv;
                conf_cnt++;
            }
            prev = best;
        }

        ort->ReleaseValue(rec_out);

        if (text.empty()) continue;

        float conf = conf_cnt > 0 ? (float)(conf_sum / conf_cnt) : 0.0f;
        if (emitted > 0) json << ",";
        json << "{\"text\":\"" << jsonEscape(text) << "\""
             << ",\"x\":" << cx0 << ",\"y\":" << cy0
             << ",\"width\":" << cw << ",\"height\":" << ch
             << ",\"confidence\":" << conf << "}";
        if (!full.empty()) full += "\n";
        full += text;
        emitted++;
    }

    json << "],\"text\":\"" << jsonEscape(full) << "\""
         << ",\"count\":" << emitted
         << ",\"det_size\":[" << det_w << "," << det_h << "]}";

    out_json = json.str();
    return true;
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
    g_ocr.release();
    g_ocr.keys.clear();
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
        g_tracker.det_input_name = ortSessionInputName(g_tracker.session, 0);
        g_tracker.det_output_name = ortSessionOutputName(g_tracker.session, 0);

        int input_size = jsonGetInt(params_str, "input_size", 0);
        std::string detector = jsonGetString(params_str, "detector");
        double input_scale = jsonGetDouble(params_str, "input_scale", 0.0);
        g_tracker.input_scale = (input_scale > 0.0 && input_scale <= 255.0)
                                    ? (float)input_scale
                                    : (1.0f / 255.0f);
        if (input_size >= 32 && input_size <= 4096) {
            g_tracker.input_width = input_size;
            g_tracker.input_height = input_size;
        }
        if (detector == "yolox") {
            g_tracker.detector_mode = 2;
        } else if (detector == "yolov8" || detector == "yolo" || detector == "yolo11") {
            g_tracker.detector_mode = 1;
        } else {
            g_tracker.detector_mode = 0;
        }
        {
            int total = 3 * g_tracker.input_width * g_tracker.input_height;
            g_tracker.input_buffer.assign((size_t)total, 114.0f * g_tracker.input_scale);
        }

        dbgLog("load_model: SUCCESS input=%dx%d detector_mode=%d",
               g_tracker.input_width, g_tracker.input_height, g_tracker.detector_mode);
        if (out_buf && out_size > 0) {
            std::ostringstream json;
            json << "{\"success\":true,\"input_size\":" << g_tracker.input_width
                 << ",\"detector_mode\":" << g_tracker.detector_mode
                 << ",\"input_scale\":" << g_tracker.input_scale << "}";
            std::string r = json.str();
            strncpy(out_buf, r.c_str(), out_size - 1);
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
                       g_tracker.input_width, g_tracker.input_height,
                       g_tracker.input_scale);

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

        const char* input_names[] = {g_tracker.det_input_name.empty()
                                         ? "images"
                                         : g_tracker.det_input_name.c_str()};
        const char* output_names[] = {g_tracker.det_output_name.empty()
                                          ? "output0"
                                          : g_tracker.det_output_name.c_str()};
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

        int num_classes = g_tracker.num_classes;
        int attrs_yolo = 4 + num_classes;
        int attrs_obj  = 5 + num_classes;
        int d0 = (int)output_dims[0];
        int d1 = (int)output_dims[1];
        int d2 = (int)output_dims[2];

        bool attrs_first = true;
        int num_preds = d2 > 0 ? d2 : 8400;
        int num_attrs = d1 > 0 ? d1 : attrs_yolo;
        if (d1 == attrs_yolo || d1 == attrs_obj) {
            attrs_first = true;
            num_attrs = d1;
            num_preds = d2;
        } else if (d2 == attrs_yolo || d2 == attrs_obj) {
            attrs_first = false;
            num_attrs = d2;
            num_preds = d1;
        }
        if (num_preds <= 0) num_preds = 8400;
        if (num_attrs <= 0) num_attrs = attrs_yolo;

        bool has_obj;
        if (g_tracker.detector_mode == 1) has_obj = false;
        else if (g_tracker.detector_mode == 2) has_obj = true;
        else has_obj = (num_attrs == attrs_obj);

        dbgLog("detect_objects: output=[%d,%d,%d,%d] preds=%d attrs=%d attrs_first=%d has_obj=%d input=%dx%d",
            d0, d1, d2, (int)output_dims[3], num_preds, num_attrs,
            attrs_first ? 1 : 0, has_obj ? 1 : 0, g_tracker.input_width, g_tracker.input_height);

        std::vector<float> rows((size_t)num_preds * num_attrs);
        if (attrs_first) {
            for (int a = 0; a < num_attrs; a++) {
                for (int p = 0; p < num_preds; p++) {
                    rows[(size_t)p * num_attrs + a] = output_data[(size_t)a * num_preds + p];
                }
            }
        } else {
            std::memcpy(rows.data(), output_data, rows.size() * sizeof(float));
        }

        ort->ReleaseValue(output_tensor);

        float conf = (float)confidence;
        if (conf <= 0) conf = g_tracker.confidence_threshold;

        std::vector<Detection> dets = postprocessDetections(
            rows.data(), num_preds, num_attrs,
            has_obj, num_classes,
            region_w, region_h,
            conf, g_tracker.nms_threshold,
            g_tracker.max_detections,
            g_tracker.input_width, g_tracker.input_height);

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
             << ",\"attrs_first\":" << (attrs_first ? "true" : "false")
             << ",\"has_objectness\":" << (has_obj ? "true" : "false")
             << ",\"input_size\":" << g_tracker.input_width
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

    if (strcmp(action_id, "load_ocr_models") == 0) {
        std::string params_str(params ? params : "");
        std::string det_path = jsonGetString(params_str, "det_path");
        std::string rec_path = jsonGetString(params_str, "rec_path");
        std::string keys_path = jsonGetString(params_str, "keys_path");

        if (!g_tracker.available || !ort) {
            if (out_buf && out_size > 0) {
                strncpy(out_buf, "{\"error\":\"onnxruntime_not_available\"}", out_size - 1);
                out_buf[out_size - 1] = '\0';
            }
            return 1;
        }
        if (det_path.empty() || rec_path.empty()) {
            if (out_buf && out_size > 0) {
                strncpy(out_buf, "{\"error\":\"det_path and rec_path are required\"}", out_size - 1);
                out_buf[out_size - 1] = '\0';
            }
            return 1;
        }

        if (!g_tracker.env) {
            OrtStatus* status = ort->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "ai_tracker", &g_tracker.env);
            if (status != nullptr || !g_tracker.env) {
                const char* msg = (status != nullptr) ? ort->GetErrorMessage(status) : "null";
                if (out_buf && out_size > 0) {
                    snprintf(out_buf, out_size, "{\"error\":\"create_env_failed\",\"detail\":\"%s\"}", msg);
                }
                if (status) ort->ReleaseStatus(status);
                return 1;
            }
        }

        if (!g_tracker.mem_info) {
            OrtStatus* status = ort->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &g_tracker.mem_info);
            if (status != nullptr || !g_tracker.mem_info) {
                const char* msg = (status != nullptr) ? ort->GetErrorMessage(status) : "null";
                if (out_buf && out_size > 0) {
                    snprintf(out_buf, out_size, "{\"error\":\"create_mem_info_failed\",\"detail\":\"%s\"}", msg);
                }
                if (status) ort->ReleaseStatus(status);
                return 1;
            }
        }

        g_ocr.release();
        g_ocr.keys.clear();

        std::string err;
        g_ocr.det_session = createSessionFromFile(det_path, 2, err);
        if (!g_ocr.det_session) {
            if (out_buf && out_size > 0) {
                snprintf(out_buf, out_size, "{\"error\":\"det_session_failed\",\"detail\":\"%s\"}", jsonEscape(err).c_str());
            }
            return 1;
        }

        g_ocr.rec_session = createSessionFromFile(rec_path, 2, err);
        if (!g_ocr.rec_session) {
            g_ocr.release();
            if (out_buf && out_size > 0) {
                snprintf(out_buf, out_size, "{\"error\":\"rec_session_failed\",\"detail\":\"%s\"}", jsonEscape(err).c_str());
            }
            return 1;
        }

        g_ocr.det_input = ortSessionInputName(g_ocr.det_session, 0);
        g_ocr.det_output = ortSessionOutputName(g_ocr.det_session, 0);
        g_ocr.rec_input = ortSessionInputName(g_ocr.rec_session, 0);
        g_ocr.rec_output = ortSessionOutputName(g_ocr.rec_session, 0);
        if (g_ocr.det_input.empty()) g_ocr.det_input = "x";
        if (g_ocr.det_output.empty()) g_ocr.det_output = "sigmoid_0.tmp_0";
        if (g_ocr.rec_input.empty()) g_ocr.rec_input = "x";
        if (g_ocr.rec_output.empty()) g_ocr.rec_output = "softmax_11.tmp_0";

        if (!keys_path.empty()) {
            std::ifstream ifs(keys_path, std::ios::binary);
            if (!ifs) {
                g_ocr.release();
                if (out_buf && out_size > 0) {
                    strncpy(out_buf, "{\"error\":\"keys_file_not_found\"}", out_size - 1);
                    out_buf[out_size - 1] = '\0';
                }
                return 1;
            }
            std::string content((std::istreambuf_iterator<char>(ifs)), std::istreambuf_iterator<char>());
            if (content.size() >= 3 &&
                (unsigned char)content[0] == 0xEF &&
                (unsigned char)content[1] == 0xBB &&
                (unsigned char)content[2] == 0xBF) {
                content.erase(0, 3);
            }
            std::istringstream ss(content);
            std::string line;
            while (std::getline(ss, line)) {
                if (!line.empty() && line.back() == '\r') line.pop_back();
                g_ocr.keys.push_back(line);
            }
        }

        if (g_ocr.keys.empty()) {
            g_ocr.release();
            if (out_buf && out_size > 0) {
                strncpy(out_buf, "{\"error\":\"keys_empty\"}", out_size - 1);
                out_buf[out_size - 1] = '\0';
            }
            return 1;
        }

        g_ocr.box_thresh = (float)jsonGetDouble(params_str, "box_threshold", 0.6);
        g_ocr.unclip_ratio = (float)jsonGetDouble(params_str, "unclip_ratio", 1.8);
        g_ocr.max_side = jsonGetInt(params_str, "max_side", 960);
        if (g_ocr.max_side < 64) g_ocr.max_side = 64;
        if (g_ocr.max_side > 2560) g_ocr.max_side = 2560;
        g_ocr.loaded = true;

        dbgLog("load_ocr_models: OK keys=%d det=%s->%s rec=%s->%s",
               (int)g_ocr.keys.size(), g_ocr.det_input.c_str(), g_ocr.det_output.c_str(),
               g_ocr.rec_input.c_str(), g_ocr.rec_output.c_str());

        if (out_buf && out_size > 0) {
            std::ostringstream json;
            json << "{\"success\":true,\"keys\":" << g_ocr.keys.size()
                 << ",\"det_input\":\"" << jsonEscape(g_ocr.det_input) << "\""
                 << ",\"det_output\":\"" << jsonEscape(g_ocr.det_output) << "\""
                 << ",\"rec_input\":\"" << jsonEscape(g_ocr.rec_input) << "\""
                 << ",\"rec_output\":\"" << jsonEscape(g_ocr.rec_output) << "\"}";
            std::string r = json.str();
            strncpy(out_buf, r.c_str(), out_size - 1);
            out_buf[out_size - 1] = '\0';
        }
        return 0;
    }

    if (strcmp(action_id, "ocr_region") == 0) {
        std::string params_str(params ? params : "");
        int region_w = jsonGetInt(params_str, "region_w", 0);
        int region_h = jsonGetInt(params_str, "region_h", 0);
        double threshold = jsonGetDouble(params_str, "threshold", 0.3);
        double box_threshold = jsonGetDouble(params_str, "box_threshold", 0.0);

        std::string ptr_str = jsonGetString(params_str, "pixel_data_ptr");
        const uint8_t* pixel_data = nullptr;
        if (!ptr_str.empty()) {
            pixel_data = (const uint8_t*)(uintptr_t)strtoull(ptr_str.c_str(), nullptr, 16);
        }

        if (!g_ocr.loaded) {
            if (out_buf && out_size > 0) {
                strncpy(out_buf, "{\"error\":\"ocr_not_loaded\"}", out_size - 1);
                out_buf[out_size - 1] = '\0';
            }
            return 1;
        }
        if (!pixel_data || region_w <= 0 || region_h <= 0) {
            if (out_buf && out_size > 0) {
                strncpy(out_buf, "{\"error\":\"invalid_region\"}", out_size - 1);
                out_buf[out_size - 1] = '\0';
            }
            return 1;
        }

        std::string json_out, err;
        if (!runOcrRegion(pixel_data, region_w, region_h,
                          (float)threshold, (float)box_threshold, json_out, err)) {
            if (out_buf && out_size > 0) {
                snprintf(out_buf, out_size, "{\"error\":\"%s\"}", jsonEscape(err).c_str());
            }
            return 1;
        }

        if ((int)json_out.size() >= out_size) {
            if (out_buf && out_size > 0) {
                snprintf(out_buf, out_size,
                    "{\"error\":\"result_too_large\",\"bytes\":%d,\"buffer\":%d}",
                    (int)json_out.size(), out_size);
            }
            return 1;
        }

        if (out_buf && out_size > 0) {
            strncpy(out_buf, json_out.c_str(), out_size - 1);
            out_buf[out_size - 1] = '\0';
        }
        return 0;
    }

    if (strcmp(action_id, "ocr_status") == 0) {
        if (out_buf && out_size > 0) {
            std::ostringstream json;
            json << "{\"ocr_loaded\":" << (g_ocr.loaded ? "true" : "false")
                 << ",\"det_session\":" << (g_ocr.det_session ? "true" : "false")
                 << ",\"rec_session\":" << (g_ocr.rec_session ? "true" : "false")
                 << ",\"keys\":" << g_ocr.keys.size()
                 << ",\"ort_available\":" << (g_tracker.available ? "true" : "false")
                 << "}";
            std::string r = json.str();
            strncpy(out_buf, r.c_str(), out_size - 1);
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
                 << ",\"input_size\":" << g_tracker.input_width
                 << ",\"detector_mode\":" << g_tracker.detector_mode
                 << ",\"ocr_loaded\":" << (g_ocr.loaded ? "true" : "false")
                 << ",\"ocr_keys\":" << g_ocr.keys.size()
                 << "}";
            std::string result = json.str();
            strncpy(out_buf, result.c_str(), out_size - 1);
            out_buf[out_size - 1] = '\0';
        }
        return 0;
    }

    return 1;
}

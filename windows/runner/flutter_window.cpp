#pragma warning(disable: 4819)
#include "flutter_window.h"

#include <dwmapi.h>
#include <mmsystem.h>
#include <sstream>
#include <optional>
#include <algorithm>
#include <vector>
#include <thread>
#include <set>
#include <mutex>
#include <atomic>
#include <map>
#include <cmath>
#include <UIAutomation.h>

// C++/WinRT for Windows OCR
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Storage.Streams.h>

#pragma comment(lib, "winmm.lib")
#pragma comment(lib, "dwmapi.lib")

// Debug logging macro — outputs to Visual Studio Output window and debug log
#define CLICKER_DEBUG 0
#if CLICKER_DEBUG
#define DBG_LOG(msg) do { \
  std::ostringstream _dbg_ss; \
  _dbg_ss << "[CLICKER] " << msg << std::endl; \
  OutputDebugStringA(_dbg_ss.str().c_str()); \
} while(0)
#else
#define DBG_LOG(msg) ((void)0)
#endif

#include "flutter/generated_plugin_registrant.h"
#include "flutter/standard_method_codec.h"

// Safe integer extraction from EncodableValue.
// Flutter StandardMethodCodec may encode Dart int as int32_t or int64_t.
static int GetInt(const flutter::EncodableValue& val) {
  if (const auto* p = std::get_if<int32_t>(&val)) return *p;
  if (const auto* p = std::get_if<int64_t>(&val)) return static_cast<int>(*p);
  return 0;
}

static int64_t GetInt64(const flutter::EncodableValue& val) {
  if (const auto* p = std::get_if<int64_t>(&val)) return *p;
  if (const auto* p = std::get_if<int32_t>(&val)) return static_cast<int64_t>(*p);
  return 0;
}

static void _prepareBackgroundTarget(HWND hwnd, int x, int y, int fromScreen,
                                     LPARAM* lp, bool hoverFirst) {
  if (fromScreen) {
    POINT pt = {x, y};
    ScreenToClient(hwnd, &pt);
    x = pt.x;
    y = pt.y;
  }
  *lp = MAKELPARAM(static_cast<WORD>(x), static_cast<WORD>(y));
  if (GetForegroundWindow() != hwnd) {
    PostMessage(hwnd, WM_ACTIVATE, MAKEWPARAM(WA_ACTIVE, 0), 0);
  }
  if (hoverFirst) {
    PostMessage(hwnd, WM_MOUSEMOVE, 0, *lp);
  }
}

// ─── Hidden Command Execution ──────────────────────────────
// Run a command without showing a console window.
// Uses CreateProcess with CREATE_NO_WINDOW instead of _popen,
// which would flash a visible terminal on screen.
// Returns the command's exit code, and captures stdout into 'output'.
static int _runCommandHidden(const std::string& cmd, std::string& output) {
  output.clear();

  // Create pipes for stdout
  SECURITY_ATTRIBUTES sa = {};
  sa.nLength = sizeof(SECURITY_ATTRIBUTES);
  sa.bInheritHandle = TRUE;
  sa.lpSecurityDescriptor = nullptr;

  HANDLE hReadPipe = nullptr, hWritePipe = nullptr;
  if (!CreatePipe(&hReadPipe, &hWritePipe, &sa, 0)) return -1;
  SetHandleInformation(hReadPipe, HANDLE_FLAG_INHERIT, 0);

  // Build command line: cmd /C <command>
  std::string fullCmd = "cmd /C " + cmd;
  // CreateProcessW needs a mutable wchar_t*
  int wLen = MultiByteToWideChar(CP_UTF8, 0, fullCmd.c_str(), -1, nullptr, 0);
  std::vector<wchar_t> cmdLine(wLen);
  MultiByteToWideChar(CP_UTF8, 0, fullCmd.c_str(), -1, cmdLine.data(), wLen);

  STARTUPINFOW si = {};
  si.cb = sizeof(STARTUPINFOW);
  si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
  si.hStdOutput = hWritePipe;
  si.hStdError = hWritePipe;
  si.wShowWindow = SW_HIDE;

  PROCESS_INFORMATION pi = {};
  DWORD creationFlags = CREATE_NO_WINDOW;

  BOOL ok = CreateProcessW(
    nullptr, cmdLine.data(), nullptr, nullptr, TRUE,
    creationFlags, nullptr, nullptr, &si, &pi);

  if (!ok) {
    CloseHandle(hReadPipe);
    CloseHandle(hWritePipe);
    return -1;
  }

  CloseHandle(hWritePipe); // Close write end so ReadFile can detect EOF

  // Read output
  char buf[256];
  DWORD bytesRead = 0;
  while (ReadFile(hReadPipe, buf, sizeof(buf) - 1, &bytesRead, nullptr) && bytesRead > 0) {
    buf[bytesRead] = '\0';
    output += buf;
  }

  CloseHandle(hReadPipe);

  // Wait with timeout (60 seconds max for OCR operations)
  DWORD waitResult = WaitForSingleObject(pi.hProcess, 60000);
  DWORD exitCode = 1;
  if (waitResult == WAIT_TIMEOUT) {
    TerminateProcess(pi.hProcess, 1);
  }
  GetExitCodeProcess(pi.hProcess, &exitCode);
  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);

  return static_cast<int>(exitCode);
}

// Simplified version that ignores output
static int _runCommandHidden(const std::string& cmd) {
  std::string unused;
  return _runCommandHidden(cmd, unused);
}

// ─── Fast Clicker State ────────────────────────────────────
// Defined early so MessageHandler can check g_clicker.running.
// Function implementations are further down in the file.

static struct {
  volatile bool running = false;
  volatile bool stop_requested = false;
  volatile uint64_t generation = 0;
  int interval_us = 10000;   // 点击间隔（微秒）— 高精度调度
  int x = -1;
  int y = -1;
  int button = 0;
  volatile int click_count = 0;
  int target_count = -1;
  flutter::MethodChannel<flutter::EncodableValue>* channel = nullptr;
  bool background_mode = false;
  HWND target_hwnd = nullptr;
  int client_x = 0;
  int client_y = 0;
  bool is_keyboard = false;
  int key_vk = 0;
  int key_action_mode = 0;
  int combo_keys[8] = {};
  int combo_key_count = 0;
  HWND self_hwnd = nullptr;
  int dart_generation = 0;
} g_clicker;

// 停止事件 — 唤醒睡眠中的点击线程，让 stop 立即生效（毫秒级以内）
static HANDLE g_clicker_stop_event = nullptr;
static volatile UINT g_clicker_stopped_msg = 0;
static volatile UINT g_perform_click_msg = 0;
static volatile UINT g_findimage_result_msg = 0;

// ─── 模板匹配内核：灰度 + 积分图 + 按行并行 ────────────────
// NCC 只关心亮度，灰度化把内存带宽降到 1/4；积分图让窗口均值/方差变成 O(1)，
// 每个位置只剩互相关那一项需要逐像素算。
static inline uint8_t _lumaOf(uint8_t b, uint8_t g, uint8_t r) {
  return static_cast<uint8_t>((r * 77 + g * 150 + b * 29) >> 8);
}

static std::vector<uint8_t> _bgraToGray(const uint8_t* bgra, int w, int h) {
  const int n = w * h;
  std::vector<uint8_t> gray(static_cast<size_t>(n));
  for (int i = 0; i < n; i++) {
    gray[i] = _lumaOf(bgra[i * 4], bgra[i * 4 + 1], bgra[i * 4 + 2]);
  }
  return gray;
}

static std::vector<uint8_t> _resampleGray(const std::vector<uint8_t>& src, int sw, int sh, int dw, int dh) {
  std::vector<uint8_t> out(static_cast<size_t>(dw) * dh);
  for (int y = 0; y < dh; y++) {
    int y0 = static_cast<int>(static_cast<int64_t>(y) * sh / dh);
    int y1 = static_cast<int>(static_cast<int64_t>(y + 1) * sh / dh);
    if (y0 >= sh) y0 = sh - 1;
    if (y1 <= y0) y1 = y0 + 1;
    if (y1 > sh) y1 = sh;
    uint8_t* drow = out.data() + static_cast<size_t>(y) * dw;
    for (int x = 0; x < dw; x++) {
      int x0 = static_cast<int>(static_cast<int64_t>(x) * sw / dw);
      int x1 = static_cast<int>(static_cast<int64_t>(x + 1) * sw / dw);
      if (x0 >= sw) x0 = sw - 1;
      if (x1 <= x0) x1 = x0 + 1;
      if (x1 > sw) x1 = sw;
      int sum = 0;
      int cnt = 0;
      for (int sy = y0; sy < y1; sy++) {
        const uint8_t* srow = src.data() + static_cast<size_t>(sy) * sw;
        for (int sx = x0; sx < x1; sx++) {
          sum += srow[sx];
          cnt++;
        }
      }
      drow[x] = cnt > 0 ? static_cast<uint8_t>((sum + cnt / 2) / cnt) : 0;
    }
  }
  return out;
}

struct GrayRegion {
  int w = 0;
  int h = 0;
  std::vector<uint8_t> px;
  std::vector<int64_t> sat;
  std::vector<int64_t> sat2;

  inline int64_t rectSum(const std::vector<int64_t>& t, int x, int y, int rw, int rh) const {
    const int stride = w + 1;
    return t[static_cast<size_t>(y + rh) * stride + (x + rw)] - t[static_cast<size_t>(y) * stride + (x + rw)]
         - t[static_cast<size_t>(y + rh) * stride + x] + t[static_cast<size_t>(y) * stride + x];
  }
};

static GrayRegion _makeGrayRegion(std::vector<uint8_t> gray, int w, int h) {
  GrayRegion r;
  r.w = w;
  r.h = h;
  r.px = std::move(gray);
  const int stride = w + 1;
  r.sat.assign(static_cast<size_t>(stride) * (h + 1), 0);
  r.sat2.assign(static_cast<size_t>(stride) * (h + 1), 0);
  for (int y = 0; y < h; y++) {
    int64_t rowSum = 0;
    int64_t rowSum2 = 0;
    const uint8_t* src = r.px.data() + static_cast<size_t>(y) * w;
    int64_t* cur = r.sat.data() + static_cast<size_t>(y + 1) * stride;
    int64_t* cur2 = r.sat2.data() + static_cast<size_t>(y + 1) * stride;
    const int64_t* prev = r.sat.data() + static_cast<size_t>(y) * stride;
    const int64_t* prev2 = r.sat2.data() + static_cast<size_t>(y) * stride;
    for (int x = 0; x < w; x++) {
      const int v = src[x];
      rowSum += v;
      rowSum2 += static_cast<int64_t>(v) * v;
      cur[x + 1] = prev[x + 1] + rowSum;
      cur2[x + 1] = prev2[x + 1] + rowSum2;
    }
  }
  return r;
}

struct GrayTemplate {
  int w = 0;
  int h = 0;
  std::vector<uint8_t> px;
  double mean = 0;
  double norm = 1;
};

static GrayTemplate _makeGrayTemplate(std::vector<uint8_t> gray, int w, int h) {
  GrayTemplate t;
  t.w = w;
  t.h = h;
  t.px = std::move(gray);
  const int n = w * h;
  if (n <= 0) return t;
  double sum = 0;
  for (int i = 0; i < n; i++) sum += t.px[i];
  t.mean = sum / n;
  double var = 0;
  for (int i = 0; i < n; i++) {
    const double d = t.px[i] - t.mean;
    var += d * d;
  }
  t.norm = std::sqrt(var);
  if (t.norm < 1.0) t.norm = 1.0;
  return t;
}

static inline double _nccAt(const GrayRegion& reg, const GrayTemplate& tpl, int sx, int sy) {
  const int n = tpl.w * tpl.h;
  const int64_t sum = reg.rectSum(reg.sat, sx, sy, tpl.w, tpl.h);
  const int64_t sum2 = reg.rectSum(reg.sat2, sx, sy, tpl.w, tpl.h);
  const double regMean = static_cast<double>(sum) / n;
  double regVar = static_cast<double>(sum2) - static_cast<double>(sum) * regMean;
  if (regVar < 1.0) regVar = 1.0;

  double dot = 0;
  for (int ty = 0; ty < tpl.h; ty++) {
    const uint8_t* rp = reg.px.data() + static_cast<size_t>(sy + ty) * reg.w + sx;
    const uint8_t* tp = tpl.px.data() + static_cast<size_t>(ty) * tpl.w;
    for (int tx = 0; tx < tpl.w; tx++) dot += static_cast<double>(rp[tx]) * tp[tx];
  }
  const double num = dot - static_cast<double>(n) * regMean * tpl.mean;
  double ncc = num / (tpl.norm * std::sqrt(regVar));
  if (ncc > 1.0) return 1.0;
  if (ncc < -1.0) return -1.0;
  return ncc;
}

// 按行切分到多线程；行数太少时退回单线程，避免线程启动开销反超
template <typename Fn>
static void _parallelRows(int count, Fn&& body) {
  int nThreads = static_cast<int>(std::thread::hardware_concurrency());
  if (nThreads <= 0) nThreads = 1;
  if (nThreads > 8) nThreads = 8;
  if (count < 64 || nThreads == 1) {
    body(0, 1);
    return;
  }
  if (count < nThreads) nThreads = count;
  std::vector<std::thread> pool;
  pool.reserve(static_cast<size_t>(nThreads - 1));
  for (int ti = 1; ti < nThreads; ti++) {
    pool.emplace_back([&body, ti, nThreads]() { body(ti, nThreads); });
  }
  body(0, nThreads);
  for (auto& t : pool) t.join();
}

struct MatchBox {
  double score;
  int x;
  int y;
  int w;
  int h;
};

// Structure to pass findImage result from background thread to main thread
struct FindImageResultData {
  flutter::MethodResult<>* result_ptr;
  double bestScore;
  int bestX;
  int bestY;
  int tplW;
  int tplH;
  std::vector<MatchBox> matches;
};
static std::mutex g_findimage_mutex;
static std::map<int, FindImageResultData> g_findimage_results;
static std::atomic<int> g_findimage_next_id{0};

// 模板指纹缓存：同一模板反复查找时只传指纹，像素不必再过一次 channel
struct CachedTemplate {
  int w = 0;
  int h = 0;
  std::vector<uint8_t> gray;
};
static std::mutex g_tpl_cache_mutex;
static std::map<std::string, CachedTemplate> g_tpl_cache;

// 帧指纹缓存：画面与全部参数都没变时直接复用上次结果
struct FrameCache {
  bool valid = false;
  uint64_t regionHash = 0;
  uint64_t tplHash = 0;
  int regionX = 0;
  int regionY = 0;
  int regionW = 0;
  int regionH = 0;
  double threshold = 0;
  int maxResults = 0;
  std::vector<double> scales;
  std::vector<MatchBox> matches;
  double bestScore = -1.0;
};
static std::mutex g_frame_cache_mutex;
static FrameCache g_frame_cache;

static inline uint64_t _fnv1a(const uint8_t* data, size_t len) {
  uint64_t h = 1469598103934665603ULL;
  for (size_t i = 0; i < len; i++) {
    h ^= data[i];
    h *= 1099511628211ULL;
  }
  return h;
}

static flutter::EncodableList _matchesToEncodable(const std::vector<MatchBox>& matches, double bestScore = -1.0) {
  flutter::EncodableList out;
  for (const auto& b : matches) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("x")] = flutter::EncodableValue(b.x);
    m[flutter::EncodableValue("y")] = flutter::EncodableValue(b.y);
    m[flutter::EncodableValue("width")] = flutter::EncodableValue(b.w);
    m[flutter::EncodableValue("height")] = flutter::EncodableValue(b.h);
    m[flutter::EncodableValue("score")] = flutter::EncodableValue(b.score);
    m[flutter::EncodableValue("matched")] = flutter::EncodableValue(true);
    out.push_back(flutter::EncodableValue(m));
  }
  flutter::EncodableMap meta;
  meta[flutter::EncodableValue("best_score")] = flutter::EncodableValue(bestScore);
  out.push_back(flutter::EncodableValue(meta));
  return out;
}

// ─── UIA 元素枚举 ─────────────────────────────────────────
// 走 COM 的 UI Automation 直接读控件树（名称/类型/包围盒），比截图匹配稳；
// 跨进程调用可能卡住，所以放独立线程里跑，结果经窗口消息回主线程。

static volatile UINT g_elem_result_msg = 0;

struct ElementDumpResult {
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result_ptr;
  flutter::EncodableList elements;
  bool truncated = false;
  std::string error;
};

static std::mutex g_elem_mutex;
static std::map<int, ElementDumpResult> g_elem_results;
static std::atomic<int> g_elem_next_id{0};

static std::string _bstrToUtf8(BSTR b) {
  if (!b) return std::string();
  const int need = WideCharToMultiByte(CP_UTF8, 0, b, -1, nullptr, 0, nullptr, nullptr);
  if (need <= 1) return std::string();
  std::string out(static_cast<size_t>(need - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, b, -1, out.data(), need, nullptr, nullptr);
  return out;
}

static std::string _wideToUtf8(const std::wstring& w) {
  if (w.empty()) return std::string();
  const int need = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), static_cast<int>(w.size()), nullptr, 0, nullptr, nullptr);
  if (need <= 0) return std::string();
  std::string out(static_cast<size_t>(need), '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.c_str(), static_cast<int>(w.size()), out.data(), need, nullptr, nullptr);
  return out;
}

static const char* _uiaControlTypeName(CONTROLTYPEID id) {
  switch (id) {
    case UIA_ButtonControlTypeId: return "Button";
    case UIA_CalendarControlTypeId: return "Calendar";
    case UIA_CheckBoxControlTypeId: return "CheckBox";
    case UIA_ComboBoxControlTypeId: return "ComboBox";
    case UIA_EditControlTypeId: return "Edit";
    case UIA_HyperlinkControlTypeId: return "Hyperlink";
    case UIA_ImageControlTypeId: return "Image";
    case UIA_ListItemControlTypeId: return "ListItem";
    case UIA_ListControlTypeId: return "List";
    case UIA_MenuControlTypeId: return "Menu";
    case UIA_MenuBarControlTypeId: return "MenuBar";
    case UIA_MenuItemControlTypeId: return "MenuItem";
    case UIA_ProgressBarControlTypeId: return "ProgressBar";
    case UIA_RadioButtonControlTypeId: return "RadioButton";
    case UIA_ScrollBarControlTypeId: return "ScrollBar";
    case UIA_SliderControlTypeId: return "Slider";
    case UIA_SpinnerControlTypeId: return "Spinner";
    case UIA_StatusBarControlTypeId: return "StatusBar";
    case UIA_TabControlTypeId: return "Tab";
    case UIA_TabItemControlTypeId: return "TabItem";
    case UIA_TextControlTypeId: return "Text";
    case UIA_ToolBarControlTypeId: return "ToolBar";
    case UIA_ToolTipControlTypeId: return "ToolTip";
    case UIA_TreeControlTypeId: return "Tree";
    case UIA_TreeItemControlTypeId: return "TreeItem";
    case UIA_DataGridControlTypeId: return "DataGrid";
    case UIA_DataItemControlTypeId: return "DataItem";
    case UIA_DocumentControlTypeId: return "Document";
    case UIA_SplitButtonControlTypeId: return "SplitButton";
    case UIA_WindowControlTypeId: return "Window";
    case UIA_PaneControlTypeId: return "Pane";
    case UIA_HeaderControlTypeId: return "Header";
    case UIA_HeaderItemControlTypeId: return "HeaderItem";
    case UIA_TableControlTypeId: return "Table";
    case UIA_TitleBarControlTypeId: return "TitleBar";
    case UIA_SeparatorControlTypeId: return "Separator";
    case UIA_GroupControlTypeId: return "Group";
    case UIA_ThumbControlTypeId: return "Thumb";
    case UIA_CustomControlTypeId: return "Custom";
    default: return "Unknown";
  }
}

struct ElementCollector {
  IUIAutomationTreeWalker* walker = nullptr;
  int maxDepth = 6;
  int maxElements = 400;
  int count = 0;
  bool truncated = false;
  double dpiScale = 1.0;
  flutter::EncodableList out;

  void walk(IUIAutomationElement* el, int depth) {
    if (!el) return;
    if (count >= maxElements) {
      truncated = true;
      return;
    }

    BSTR name = nullptr;
    BSTR automationId = nullptr;
    BSTR className = nullptr;
    el->get_CurrentName(&name);
    el->get_CurrentAutomationId(&automationId);
    el->get_CurrentClassName(&className);

    CONTROLTYPEID controlType = 0;
    el->get_CurrentControlType(&controlType);

    RECT rect{0, 0, 0, 0};
    const bool hasRect = SUCCEEDED(el->get_CurrentBoundingRectangle(&rect));

    BOOL enabled = FALSE;
    BOOL focused = FALSE;
    el->get_CurrentIsEnabled(&enabled);
    el->get_CurrentHasKeyboardFocus(&focused);

    UIA_HWND nativeHwnd = nullptr;
    el->get_CurrentNativeWindowHandle(&nativeHwnd);

    flutter::EncodableMap m;
    m[flutter::EncodableValue("name")] = flutter::EncodableValue(_bstrToUtf8(name));
    m[flutter::EncodableValue("automationId")] = flutter::EncodableValue(_bstrToUtf8(automationId));
    m[flutter::EncodableValue("className")] = flutter::EncodableValue(_bstrToUtf8(className));
    m[flutter::EncodableValue("controlType")] = flutter::EncodableValue(std::string(_uiaControlTypeName(controlType)));
    m[flutter::EncodableValue("controlTypeId")] = flutter::EncodableValue(static_cast<int>(controlType));
    m[flutter::EncodableValue("enabled")] = flutter::EncodableValue(enabled != FALSE);
    m[flutter::EncodableValue("focused")] = flutter::EncodableValue(focused != FALSE);
    m[flutter::EncodableValue("hwnd")] = flutter::EncodableValue(static_cast<int64_t>(reinterpret_cast<INT_PTR>(nativeHwnd)));
    m[flutter::EncodableValue("depth")] = flutter::EncodableValue(depth);
    if (hasRect) {
      const int x = static_cast<int>(std::lround(rect.left / dpiScale));
      const int y = static_cast<int>(std::lround(rect.top / dpiScale));
      const int w = static_cast<int>(std::lround((rect.right - rect.left) / dpiScale));
      const int h = static_cast<int>(std::lround((rect.bottom - rect.top) / dpiScale));
      m[flutter::EncodableValue("x")] = flutter::EncodableValue(x);
      m[flutter::EncodableValue("y")] = flutter::EncodableValue(y);
      m[flutter::EncodableValue("width")] = flutter::EncodableValue(w);
      m[flutter::EncodableValue("height")] = flutter::EncodableValue(h);
      m[flutter::EncodableValue("centerX")] = flutter::EncodableValue(x + w / 2);
      m[flutter::EncodableValue("centerY")] = flutter::EncodableValue(y + h / 2);
    }
    out.push_back(flutter::EncodableValue(m));
    count++;

    if (name) SysFreeString(name);
    if (automationId) SysFreeString(automationId);
    if (className) SysFreeString(className);

    if (depth >= maxDepth) {
      IUIAutomationElement* probe = nullptr;
      if (SUCCEEDED(walker->GetFirstChildElement(el, &probe)) && probe) {
        truncated = true;
        probe->Release();
      }
      return;
    }

    IUIAutomationElement* child = nullptr;
    walker->GetFirstChildElement(el, &child);
    while (child) {
      if (count >= maxElements) {
        truncated = true;
        child->Release();
        break;
      }
      walk(child, depth + 1);
      IUIAutomationElement* next = nullptr;
      walker->GetNextSiblingElement(child, &next);
      child->Release();
      child = next;
    }
  }
};

// ─── 截图直供：PNG 编码 + Set-of-Mark 编号 ────────────────
// 多模态模型直接吃 PNG；需要指向具体控件时，把 UIA 元素的框和编号画上去。

static std::wstring _utf8ToWide(const std::string& s) {
  if (s.empty()) return std::wstring();
  const int need = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0);
  if (need <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(need), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), out.data(), need);
  return out;
}

struct MarkRect {
  int x = 0;
  int y = 0;
  int w = 0;
  int h = 0;
  std::wstring label;
};

static std::vector<uint8_t> _captureAnnotatedBgra(int x, int y, int w, int h, int outW, int outH,
                                                  const std::vector<MarkRect>& marks, double scale) {
  std::vector<uint8_t> out;
  HDC screen = GetDC(nullptr);
  if (!screen) return out;
  HDC mem = CreateCompatibleDC(screen);

  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = outW;
  bmi.bmiHeader.biHeight = -outH;
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;
  HBITMAP dib = CreateDIBSection(mem, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (!dib || !bits) {
    DeleteDC(mem);
    ReleaseDC(nullptr, screen);
    return out;
  }
  HBITMAP oldBmp = (HBITMAP)SelectObject(mem, dib);
  SetStretchBltMode(mem, HALFTONE);
  StretchBlt(mem, 0, 0, outW, outH, screen, x, y, w, h, SRCCOPY);

  if (!marks.empty()) {
    SetBkMode(mem, TRANSPARENT);
    HFONT font = CreateFontW(-16, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                             OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                             DEFAULT_PITCH, L"Microsoft YaHei");
    HGDIOBJ oldFont = font ? SelectObject(mem, font) : nullptr;
    for (const auto& mk : marks) {
      const int mx = static_cast<int>(std::lround((mk.x - x) * scale));
      const int my = static_cast<int>(std::lround((mk.y - y) * scale));
      const int mw = static_cast<int>(std::lround(mk.w * scale));
      const int mh = static_cast<int>(std::lround(mk.h * scale));
      if (mw <= 0 || mh <= 0) continue;
      if (mx + mw < 0 || my + mh < 0 || mx > outW || my > outH) continue;

      HPEN pen = CreatePen(PS_SOLID, 2, RGB(255, 64, 64));
      HGDIOBJ oldPen = SelectObject(mem, pen);
      HGDIOBJ oldBrush = SelectObject(mem, GetStockObject(NULL_BRUSH));
      Rectangle(mem, mx, my, mx + mw, my + mh);
      SelectObject(mem, oldBrush);
      SelectObject(mem, oldPen);
      DeleteObject(pen);

      if (mk.label.empty()) continue;
      SIZE sz{0, 0};
      GetTextExtentPoint32W(mem, mk.label.c_str(), (int)mk.label.size(), &sz);
      RECT bgRect{mx, my, mx + sz.cx + 10, my + sz.cy + 6};
      if (bgRect.bottom > outH) {
        bgRect.top = my - sz.cy - 6;
        bgRect.bottom = my;
      }
      HBRUSH bg = CreateSolidBrush(RGB(255, 64, 64));
      FillRect(mem, &bgRect, bg);
      DeleteObject(bg);
      SetTextColor(mem, RGB(255, 255, 255));
      RECT txtRect{bgRect.left + 5, bgRect.top + 3, bgRect.right, bgRect.bottom};
      DrawTextW(mem, mk.label.c_str(), (int)mk.label.size(), &txtRect, DT_LEFT | DT_TOP | DT_SINGLELINE | DT_NOPREFIX);
    }
    if (oldFont) SelectObject(mem, oldFont);
    if (font) DeleteObject(font);
  }

  out.resize(static_cast<size_t>(outW) * outH * 4);
  memcpy(out.data(), bits, out.size());

  SelectObject(mem, oldBmp);
  DeleteObject(dib);
  DeleteDC(mem);
  ReleaseDC(nullptr, screen);
  return out;
}

static std::vector<uint8_t> _encodePngFromBgra(std::vector<uint8_t> bgra, int w, int h) {
  std::vector<uint8_t> png;
  for (size_t i = 3; i < bgra.size(); i += 4) bgra[i] = 255;
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    using namespace winrt::Windows::Graphics::Imaging;
    using namespace winrt::Windows::Storage::Streams;

    SoftwareBitmap bitmap(BitmapPixelFormat::Bgra8, w, h, BitmapAlphaMode::Premultiplied);
    {
      DataWriter writer;
      writer.WriteBytes(winrt::array_view<uint8_t const>(bgra));
      bitmap.CopyFromBuffer(writer.DetachBuffer());
    }
    InMemoryRandomAccessStream stream;
    BitmapEncoder encoder = BitmapEncoder::CreateAsync(BitmapEncoder::PngEncoderId(), stream).get();
    encoder.SetSoftwareBitmap(bitmap);
    encoder.FlushAsync().get();

    const uint32_t size = static_cast<uint32_t>(stream.Size());
    if (size == 0) return png;
    DataReader reader = DataReader(stream.GetInputStreamAt(0));
    reader.LoadAsync(size).get();
    png.resize(size);
    reader.ReadBytes(winrt::array_view<uint8_t>(png));
  } catch (...) {
    png.clear();
  }
  return png;
}

// ─── OCR Fallback Methods ──────────────────────────────────
// Save BGRA pixels to a temp BMP file (shared by fallback methods)
// Get a temp directory that avoids non-ASCII path issues (e.g. Chinese usernames)
static std::string _getSafeTempDir() {
  // Try exe directory first — usually ASCII-safe
  char exePath[MAX_PATH];
  GetModuleFileNameA(nullptr, exePath, MAX_PATH);
  std::string exeDir(exePath);
  auto lastSlash = exeDir.find_last_of("\\/");
  if (lastSlash != std::string::npos) exeDir = exeDir.substr(0, lastSlash);

  std::string safeDir = exeDir + "\\clicker_temp";
  CreateDirectoryA(safeDir.c_str(), nullptr);
  // Verify we can actually write here
  std::string testPath = safeDir + "\\_test_" + std::to_string(GetTickCount64()) + ".tmp";
  FILE* f = nullptr;
  fopen_s(&f, testPath.c_str(), "w");
  if (f) {
    fclose(f);
    remove(testPath.c_str());
    // Clean up old temp files from previous sessions
    WIN32_FIND_DATAA findData;
    std::string searchPattern = safeDir + "\\clicker_*";
    HANDLE hFind = FindFirstFileA(searchPattern.c_str(), &findData);
    if (hFind != INVALID_HANDLE_VALUE) {
      do {
        std::string oldFile = safeDir + "\\" + findData.cFileName;
        DeleteFileA(oldFile.c_str());
      } while (FindNextFileA(hFind, &findData));
      FindClose(hFind);
    }
    return safeDir + "\\";
  }
  // Fallback to Windows TEMP with short path (8.3 format avoids non-ASCII)
  char tempDir[MAX_PATH];
  GetTempPathA(MAX_PATH, tempDir);
  char shortPath[MAX_PATH];
  if (GetShortPathNameA(tempDir, shortPath, MAX_PATH)) {
    return std::string(shortPath);
  }
  return std::string(tempDir);
}

static std::string _ocrSaveTempBmp(const std::vector<uint8_t>& pixels, int w, int h) {
  std::string tempDir = _getSafeTempDir();
  std::string tempPath = tempDir + "clicker_ocr_" +
    std::to_string(GetCurrentProcessId()) + "_" + std::to_string(GetTickCount64()) + ".bmp";

  FILE* f = nullptr;
  fopen_s(&f, tempPath.c_str(), "wb");
  if (!f) return "";

  // Flip rows for BMP (bottom-up)
  std::vector<uint8_t> flipped(pixels.size());
  int rowSize = w * 4;
  for (int y = 0; y < h; y++) {
    memcpy(&flipped[(h - 1 - y) * rowSize], &pixels[y * rowSize], rowSize);
  }

  BITMAPFILEHEADER bfh = {};
  bfh.bfType = 0x4D42;
  bfh.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
  bfh.bfSize = bfh.bfOffBits + (DWORD)flipped.size();

  BITMAPINFOHEADER bmi = {};
  bmi.biSize = sizeof(BITMAPINFOHEADER);
  bmi.biWidth = w;
  bmi.biHeight = h;
  bmi.biPlanes = 1;
  bmi.biBitCount = 32;
  bmi.biCompression = BI_RGB;
  bmi.biSizeImage = (DWORD)flipped.size();

  fwrite(&bfh, sizeof(bfh), 1, f);
  fwrite(&bmi, sizeof(bmi), 1, f);
  fwrite(flipped.data(), 1, flipped.size(), f);
  fclose(f);
  return tempPath;
}

// Fallback: Python with pytesseract
static bool _ocrFallbackPython(const std::vector<uint8_t>& pixels, int w, int h,
                                const std::string& lang, std::string& outText) {
  std::string bmpPath = _ocrSaveTempBmp(pixels, w, h);
  if (bmpPath.empty()) return false;

  // Map language code to tesseract format
  std::string tessLang = "eng";
  if (lang.find("zh") != std::string::npos) tessLang = "chi_sim";
  else if (lang == "ja") tessLang = "jpn";
  else if (lang == "ko") tessLang = "kor";

  // Write a temp Python script
  std::string tempDir = _getSafeTempDir();
  std::string pyPath = tempDir + "clicker_ocr_" +
    std::to_string(GetCurrentProcessId()) + "_" + std::to_string(GetTickCount64()) + ".py";

  FILE* pyf = nullptr;
  fopen_s(&pyf, pyPath.c_str(), "w");
  if (!pyf) { remove(bmpPath.c_str()); return false; }

  fprintf(pyf,
    "import sys\n"
    "try:\n"
    "  from PIL import Image\n"
    "  import pytesseract\n"
    "  img = Image.open(r'%s')\n"
    "  text = pytesseract.image_to_string(img, lang='%s')\n"
    "  print(text)\n"
    "except Exception as e:\n"
    "  print('PYTHON_OCR_ERROR:' + str(e))\n",
    bmpPath.c_str(), tessLang.c_str());
  fclose(pyf);

  // Try python3 first, then python
  std::string ocrText;
  for (const char* pyCmd : {"python", "python3", "py"}) {
    std::string cmd = std::string(pyCmd) + " \"" + pyPath + "\"";
    std::string output;
    int ret = _runCommandHidden(cmd, output);
    if (ret == 0) {
      ocrText = output;
      if (ocrText.find("PYTHON_OCR_ERROR:") == std::string::npos && !ocrText.empty()) {
        while (!ocrText.empty() && (ocrText.back() == '\n' || ocrText.back() == '\r' || ocrText.back() == ' '))
          ocrText.pop_back();
        remove(bmpPath.c_str());
        remove(pyPath.c_str());
        outText = ocrText;
        return true;
      }
    }
  }

  remove(bmpPath.c_str());
  remove(pyPath.c_str());
  return false;
}

// Fallback: PowerShell with Windows.Media.Ocr
static bool _ocrFallbackPowerShell(const std::vector<uint8_t>& pixels, int w, int h,
                                    const std::string& lang, std::string& outText) {
  std::string bmpPath = _ocrSaveTempBmp(pixels, w, h);
  if (bmpPath.empty()) return false;

  std::string tempDir = _getSafeTempDir();
  std::string ps1Path = tempDir + "clicker_ocr_" +
    std::to_string(GetCurrentProcessId()) + "_" + std::to_string(GetTickCount64()) + ".ps1";

  FILE* ps1f = nullptr;
  fopen_s(&ps1f, ps1Path.c_str(), "w");
  if (!ps1f) { remove(bmpPath.c_str()); return false; }

  fprintf(ps1f,
    "Add-Type -AssemblyName System.Runtime.WindowsRuntime\n"
    "[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime] | Out-Null\n"
    "[Windows.Media.Ocr.OcrEngine,Windows.Media.Ocr,ContentType=WindowsRuntime] | Out-Null\n"
    "[Windows.Graphics.Imaging.SoftwareBitmap,Windows.Graphics.Imaging,ContentType=WindowsRuntime] | Out-Null\n"
    "[Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime] | Out-Null\n"
    "$file = [Windows.Storage.StorageFile]::GetFileFromPathAsync('%s').AsTask().GetAwaiter().GetResult()\n"
    "$stream = $file.OpenAsync([Windows.Storage.FileAccessMode]::Read).AsTask().GetAwaiter().GetResult()\n"
    "$decoder = [Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream).AsTask().GetAwaiter().GetResult()\n"
    "$bmp = $decoder.GetSoftwareBitmapAsync().AsTask().GetAwaiter().GetResult()\n"
    "$ocrEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()\n"
    "if ($ocrEngine -eq $null) { Write-Output 'OCR_NOT_AVAILABLE' } else {\n"
    "$result = $ocrEngine.RecognizeAsync($bmp).AsTask().GetAwaiter().GetResult()\n"
    "Write-Output $result.Text\n"
    "}\n",
    bmpPath.c_str());
  fclose(ps1f);

  std::string cmd = "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + ps1Path + "\"";
  std::string ocrText;
  _runCommandHidden(cmd, ocrText);

  remove(bmpPath.c_str());
  remove(ps1Path.c_str());

  while (!ocrText.empty() && (ocrText.back() == '\n' || ocrText.back() == '\r' || ocrText.back() == ' '))
    ocrText.pop_back();

  if (ocrText.empty() || ocrText == "OCR_NOT_AVAILABLE") return false;

  outText = ocrText;
  return true;
}

// Ensure DWMWA_TRANSITIONS_FORCEDISABLED is defined (older SDKs may not have it)
#ifndef DWMWA_TRANSITIONS_FORCEDISABLED
#define DWMWA_TRANSITIONS_FORCEDISABLED 3
#endif

// Global pointer for low-level hooks (must be global for SetWindowsHookEx).
static FlutterWindow* g_flutter_window_for_hooks = nullptr;

// ─── VK ↔ Key Name Conversion ─────────────────────────────────────────────

static std::string VkToKeyName(int vk) {
  static const struct { int vk; const char* name; } map[] = {
    {0x0D, "enter"}, {0x09, "tab"}, {0x1B, "escape"}, {0x08, "backspace"},
    {0x20, "space"}, {0x25, "left"}, {0x27, "right"}, {0x26, "up"}, {0x28, "down"},
    {0x10, "shift"}, {0x11, "ctrl"}, {0x12, "alt"}, {0x2E, "delete"}, {0x2D, "insert"},
    {0x24, "home"}, {0x23, "end"}, {0x21, "pageup"}, {0x22, "pagedown"},
    {0x2C, "printscreen"}, {0x91, "scrolllock"}, {0x13, "pause"},
    {0x14, "capslock"}, {0x90, "numlock"}, {0x5B, "win"}, {0x5D, "apps"},
    {0x70, "f1"}, {0x71, "f2"}, {0x72, "f3"}, {0x73, "f4"}, {0x74, "f5"},
    {0x75, "f6"}, {0x76, "f7"}, {0x77, "f8"}, {0x78, "f9"}, {0x79, "f10"},
    {0x7A, "f11"}, {0x7B, "f12"},
  };
  for (const auto& m : map) {
    if (m.vk == vk) return m.name;
  }
  if (vk >= 0x30 && vk <= 0x39) return std::string(1, static_cast<char>(vk));
  if (vk >= 0x41 && vk <= 0x5A) return std::string(1, static_cast<char>(vk + 32));
  return "unknown";
}

static int KeyNameToVk(const std::string& name) {
  std::string lower = name;
  for (auto& c : lower) c = static_cast<char>(tolower(c));
  static const struct { const char* name; int vk; } map[] = {
    {"enter", 0x0D}, {"tab", 0x09}, {"escape", 0x1B}, {"backspace", 0x08},
    {"space", 0x20}, {"left", 0x25}, {"right", 0x27}, {"up", 0x26}, {"down", 0x28},
    {"shift", 0x10}, {"ctrl", 0x11}, {"alt", 0x12}, {"delete", 0x2E}, {"insert", 0x2D},
    {"home", 0x24}, {"end", 0x23}, {"pageup", 0x21}, {"pagedown", 0x22},
    {"printscreen", 0x2C}, {"scrolllock", 0x91}, {"pause", 0x13},
    {"capslock", 0x14}, {"numlock", 0x90}, {"win", 0x5B}, {"apps", 0x5D},
    {"f1", 0x70}, {"f2", 0x71}, {"f3", 0x72}, {"f4", 0x73}, {"f5", 0x74},
    {"f6", 0x75}, {"f7", 0x76}, {"f8", 0x77}, {"f9", 0x78}, {"f10", 0x79},
    {"f11", 0x7A}, {"f12", 0x7B},
  };
  for (const auto& m : map) {
    if (lower == m.name) return m.vk;
  }
  if (lower.length() == 1) {
    char c = lower[0];
    if (c >= '0' && c <= '9') return static_cast<int>(c);
    if (c >= 'a' && c <= 'z') return static_cast<int>(c - 32);
  }
  return 0;
}

// ─── Hold Trigger (Per-Key Auto-Repeat) ──────────────────────────────────

struct HoldTriggerEntry {
  int trigger_vk = 0;
  bool is_mouse_trigger = false;  // true = triggered by mouse button hold
  int mouse_trigger_button = 0;   // 0=left, 1=right, 2=middle
  bool is_keyboard = false;
  int key_vk = 0;
  int key_action_mode = 0;
  int combo_keys[8] = {};
  int combo_key_count = 0;
  int mouse_button = 0;
  int interval_ms = 50;
  bool background_mode = false;
  HWND target_hwnd = nullptr;
  int client_x = 0;
  int client_y = 0;
  HANDLE thread = nullptr;
  volatile bool stop_requested = false;
  volatile uint64_t generation = 0;
  bool active = false;
};

static const int kMaxHoldTriggers = 32;
static HoldTriggerEntry g_hold_triggers[kMaxHoldTriggers];
static int g_hold_trigger_count = 0;
static CRITICAL_SECTION g_hold_trigger_cs;
static bool g_hold_trigger_cs_initialized = false;

static DWORD WINAPI HoldTriggerThreadFunc(LPVOID param);

static void SendHoldTriggerAction(HoldTriggerEntry* entry) {
  if (entry->is_keyboard) {
    if (entry->key_action_mode == 0) {
      keybd_event(static_cast<BYTE>(entry->key_vk), 0, 0, 0);
      keybd_event(static_cast<BYTE>(entry->key_vk), 0, KEYEVENTF_KEYUP, 0);
    } else if (entry->key_action_mode == 2) {
      int n = entry->combo_key_count;
      if (n > 8) n = 8;
      for (int i = 0; i < n; i++) keybd_event(static_cast<BYTE>(entry->combo_keys[i]), 0, 0, 0);
      for (int i = 0; i < n; i++) keybd_event(static_cast<BYTE>(entry->combo_keys[i]), 0, KEYEVENTF_KEYUP, 0);
    }
  } else {
    if (entry->background_mode && entry->target_hwnd) {
      // Scroll not supported in background mode
      if (entry->mouse_button >= 5) return;
      LPARAM lp = MAKELPARAM(static_cast<WORD>(entry->client_x),
                              static_cast<WORD>(entry->client_y));
      UINT msg_down = WM_LBUTTONDOWN, msg_up = WM_LBUTTONUP;
      WPARAM wp = MK_LBUTTON;
      if (entry->mouse_button == 1) { msg_down = WM_RBUTTONDOWN; msg_up = WM_RBUTTONUP; }
      else if (entry->mouse_button == 2) { msg_down = WM_MBUTTONDOWN; msg_up = WM_MBUTTONUP; }
      else if (entry->mouse_button == 3 || entry->mouse_button == 4) {
        msg_down = WM_XBUTTONDOWN; msg_up = WM_XBUTTONUP;
        wp = MAKELPARAM((entry->mouse_button == 4) ? XBUTTON2 : XBUTTON1, 0);
      }
      PostMessage(entry->target_hwnd, msg_down, wp, lp);
      PostMessage(entry->target_hwnd, msg_up, 0, lp);
      return;
    }

    // Handle scroll
    if (entry->mouse_button == 5 || entry->mouse_button == 6) {
      int delta = (entry->mouse_button == 5) ? 120 : -120;
      mouse_event(MOUSEEVENTF_WHEEL, 0, 0, (DWORD)delta, 0);
      return;
    }

    DWORD flags_down = MOUSEEVENTF_LEFTDOWN, flags_up = MOUSEEVENTF_LEFTUP;
    DWORD mouse_data = 0;
    if (entry->mouse_button == 1) { flags_down = MOUSEEVENTF_RIGHTDOWN; flags_up = MOUSEEVENTF_RIGHTUP; }
    else if (entry->mouse_button == 2) { flags_down = MOUSEEVENTF_MIDDLEDOWN; flags_up = MOUSEEVENTF_MIDDLEUP; }
    else if (entry->mouse_button == 3) { flags_down = MOUSEEVENTF_XDOWN; flags_up = MOUSEEVENTF_XUP; mouse_data = XBUTTON1; }
    else if (entry->mouse_button == 4) { flags_down = MOUSEEVENTF_XDOWN; flags_up = MOUSEEVENTF_XUP; mouse_data = XBUTTON2; }

    // Game-friendly injection: raw-input games ignore bare mouse_event, so
    // attach an absolute move at the current cursor (same as the macro player).
    POINT pt;
    if (GetCursorPos(&pt)) {
      LONG dx = (LONG)(pt.x * 65535.0 / (GetSystemMetrics(SM_CXSCREEN) - 1));
      LONG dy = (LONG)(pt.y * 65535.0 / (GetSystemMetrics(SM_CYSCREEN) - 1));
      INPUT inputs[2] = {};
      inputs[0].type = INPUT_MOUSE;
      inputs[0].mi.dx = dx;
      inputs[0].mi.dy = dy;
      inputs[0].mi.mouseData = mouse_data;
      inputs[0].mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_MOVE | flags_down;
      inputs[1].type = INPUT_MOUSE;
      inputs[1].mi.dx = dx;
      inputs[1].mi.dy = dy;
      inputs[1].mi.mouseData = mouse_data;
      inputs[1].mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_MOVE | flags_up;
      SendInput(2, inputs, sizeof(INPUT));
    } else {
      mouse_event(flags_down, 0, 0, mouse_data, 0);
      mouse_event(flags_up, 0, 0, mouse_data, 0);
    }
  }
}

static void StartHoldTrigger(HoldTriggerEntry* entry) {
  if (entry->active) return;
  // Clean up previous thread handle if any
  if (entry->thread) {
    WaitForSingleObject(entry->thread, 100);
    CloseHandle(entry->thread);
    entry->thread = nullptr;
  }
  entry->active = true;
  entry->stop_requested = false;
  entry->generation++;
  entry->thread = CreateThread(nullptr, 0, HoldTriggerThreadFunc, entry, 0, nullptr);
}

static void StopHoldTrigger(HoldTriggerEntry* entry) {
  if (!entry->active) return;
  entry->stop_requested = true;
  entry->active = false;
  // Don't wait for thread in hook proc — it exits within one sleep cycle.
  // Handle is closed on next start or unregister.
}

static DWORD WINAPI HoldTriggerThreadFunc(LPVOID param) {
  auto* entry = reinterpret_cast<HoldTriggerEntry*>(param);
  uint64_t my_gen = entry->generation;
  SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST);
  timeBeginPeriod(1);
  int sleep_ms = entry->interval_ms;
  if (sleep_ms < 10) sleep_ms = 10;
  while (entry->generation == my_gen && !entry->stop_requested) {
    SendHoldTriggerAction(entry);
    Sleep(sleep_ms);
  }
  timeEndPeriod(1);
  return 0;
}

// Key capture mode for UI key selection
static bool g_capturing_key = false;
static flutter::MethodChannel<flutter::EncodableValue>* g_capture_channel = nullptr;

// Hook-based hotkeys (fallback when RegisterHotKey fails, e.g. F-keys without modifiers)
struct HookHotkey {
  int id;
  int modifiers;  // MOD_ALT=0x1, MOD_CONTROL=0x2, MOD_SHIFT=0x4, MOD_WIN=0x8
  int vk;
};
static HookHotkey g_hook_hotkeys[64];
static int g_hook_hotkey_count = 0;
static int g_hook_modifiers = 0;  // Current modifier key state (tracked in hook)
static flutter::MethodChannel<flutter::EncodableValue>* g_hotkey_channel = nullptr;

// -- Raw input / user input monitoring --------------------------------------

static bool g_raw_input_enabled = false;
static bool g_user_input_monitor = false;
static flutter::MethodChannel<flutter::EncodableValue>* g_raw_input_channel = nullptr;
static POINT g_user_move_last = {0, 0};
static POINT g_self_set_pos = {-1, -1};

static bool RegisterRawInputDevicesFor(HWND hwnd, bool enable) {
  RAWINPUTDEVICE devices[2] = {};
  devices[0].usUsagePage = 0x01;
  devices[0].usUsage = 0x02;
  devices[1].usUsagePage = 0x01;
  devices[1].usUsage = 0x06;
  for (auto& device : devices) {
    device.dwFlags = enable ? RIDEV_INPUTSINK : RIDEV_REMOVE;
    device.hwndTarget = enable ? hwnd : nullptr;
  }
  return RegisterRawInputDevices(devices, 2, sizeof(RAWINPUTDEVICE)) == TRUE;
}

// -- Overlay Window Implementation -------------------------------------------

OverlayState g_overlay;
static const COLORREF CROSSHAIR_COLOR = RGB(255, 60, 60);
static const COLORREF RECT_COLOR = RGB(0, 180, 255);
static const wchar_t kOverlayClassName[] = L"ClickerOverlayWnd";
static const int OVERLAY_TIMER_ID = 1;
static const int OVERLAY_FPS = 60;

// Double-buffer: offscreen DC + bitmap, created once and reused
static HDC g_overlayMemDC = nullptr;
static HBITMAP g_overlayMemBmp = nullptr;
static HBITMAP g_overlayOldBmp = nullptr;
static int g_overlayBmpW = 0;
static int g_overlayBmpH = 0;

static void EnsureOverlayBuffer(int w, int h) {
  if (g_overlayMemDC && g_overlayBmpW >= w && g_overlayBmpH >= h) return;
  if (g_overlayMemDC) {
    SelectObject(g_overlayMemDC, g_overlayOldBmp);
    DeleteObject(g_overlayMemBmp);
    DeleteDC(g_overlayMemDC);
  }
  HDC screenDC = GetDC(nullptr);
  g_overlayMemDC = CreateCompatibleDC(screenDC);
  g_overlayBmpW = w;
  g_overlayBmpH = h;
  g_overlayMemBmp = CreateCompatibleBitmap(screenDC, w, h);
  g_overlayOldBmp = (HBITMAP)SelectObject(g_overlayMemDC, g_overlayMemBmp);
  ReleaseDC(nullptr, screenDC);
}

static void CleanupOverlayBuffer() {
  if (g_overlayMemDC) {
    SelectObject(g_overlayMemDC, g_overlayOldBmp);
    DeleteObject(g_overlayMemBmp);
    DeleteDC(g_overlayMemDC);
    g_overlayMemDC = nullptr;
    g_overlayMemBmp = nullptr;
    g_overlayOldBmp = nullptr;
    g_overlayBmpW = 0;
    g_overlayBmpH = 0;
  }
}

static void DrawOverlayContent(HDC hdc, int w, int h) {
  // Fill background with dark semi-transparent color (whole window captures clicks)
  HBRUSH bgBrush = CreateSolidBrush(RGB(1, 1, 1));
  RECT rcFull = {0, 0, w, h};
  FillRect(hdc, &rcFull, bgBrush);
  DeleteObject(bgBrush);

  POINT pt;
  GetCursorPos(&pt);

  // For WindowPick mode, convert screen coordinates to overlay-local coordinates
  if (g_overlay.mode == OverlayMode::WindowPick && g_overlay.hwnd) {
    POINT origin = {0, 0};
    ClientToScreen(g_overlay.hwnd, &origin);
    pt.x -= origin.x;
    pt.y -= origin.y;
  }

  if (g_overlay.mode == OverlayMode::Crosshair || g_overlay.mode == OverlayMode::WindowPick) {
    // Draw crosshair lines (thick for easy clicking)
    HPEN hPen = CreatePen(PS_SOLID, 3, CROSSHAIR_COLOR);
    HPEN hOldPen = (HPEN)SelectObject(hdc, hPen);
    MoveToEx(hdc, 0, pt.y, nullptr);
    LineTo(hdc, w, pt.y);
    MoveToEx(hdc, pt.x, 0, nullptr);
    LineTo(hdc, pt.x, h);
    SelectObject(hdc, hOldPen);
    DeleteObject(hPen);

    // Draw center circle (large for easy clicking)
    HBRUSH circleBrush = CreateSolidBrush(CROSSHAIR_COLOR);
    HBRUSH oldBrush = (HBRUSH)SelectObject(hdc, circleBrush);
    HPEN oldPen2 = (HPEN)SelectObject(hdc, GetStockObject(NULL_PEN));
    Ellipse(hdc, pt.x - 12, pt.y - 12, pt.x + 12, pt.y + 12);
    SelectObject(hdc, oldPen2);
    SelectObject(hdc, oldBrush);
    DeleteObject(circleBrush);

    // Draw coordinate text near cursor with background
    SetBkColor(hdc, RGB(1, 1, 1));
    SetTextColor(hdc, CROSSHAIR_COLOR);
    wchar_t coordText[64];
    swprintf_s(coordText, L"(%d, %d)", pt.x, pt.y);
    TextOutW(hdc, pt.x + 16, pt.y + 16, coordText, (int)wcslen(coordText));

    if (g_overlay.mode == OverlayMode::WindowPick) {
      // Draw hint text
      SetTextColor(hdc, RGB(255, 255, 255));
      TextOutW(hdc, 8, 8, L"Click to pick coordinates (ESC to cancel)", 41);
    }

  } else if (g_overlay.mode == OverlayMode::AreaSelect) {
    if (g_overlay.dragging) {
      // Draw selection rectangle with thick border
      HPEN hPen = CreatePen(PS_SOLID, 3, RECT_COLOR);
      HBRUSH hOldBrush = (HBRUSH)SelectObject(hdc, GetStockObject(NULL_BRUSH));
      HPEN hOldPen = (HPEN)SelectObject(hdc, hPen);

      int x1 = g_overlay.dragStart.x < g_overlay.dragCurrent.x ? g_overlay.dragStart.x : g_overlay.dragCurrent.x;
      int y1 = g_overlay.dragStart.y < g_overlay.dragCurrent.y ? g_overlay.dragStart.y : g_overlay.dragCurrent.y;
      int x2 = g_overlay.dragStart.x < g_overlay.dragCurrent.x ? g_overlay.dragCurrent.x : g_overlay.dragStart.x;
      int y2 = g_overlay.dragStart.y < g_overlay.dragCurrent.y ? g_overlay.dragCurrent.y : g_overlay.dragStart.y;
      Rectangle(hdc, x1, y1, x2, y2);

      // Draw size text with background
      SetBkColor(hdc, RGB(1, 1, 1));
      SetTextColor(hdc, RECT_COLOR);
      wchar_t sizeText[64];
      swprintf_s(sizeText, L"%dx%d", x2 - x1, y2 - y1);
      TextOutW(hdc, x1, y1 - 18, sizeText, (int)wcslen(sizeText));

      SelectObject(hdc, hOldPen);
      SelectObject(hdc, hOldBrush);
      DeleteObject(hPen);
    } else {
      // Draw crosshair and hint text when not dragging
      HPEN hPen = CreatePen(PS_SOLID, 1, RECT_COLOR);
      HPEN hOldPen = (HPEN)SelectObject(hdc, hPen);
      MoveToEx(hdc, 0, pt.y, nullptr);
      LineTo(hdc, w, pt.y);
      MoveToEx(hdc, pt.x, 0, nullptr);
      LineTo(hdc, pt.x, h);
      SelectObject(hdc, hOldPen);
      DeleteObject(hPen);

      // Draw hint text
      SetBkColor(hdc, RGB(1, 1, 1));
      SetTextColor(hdc, RGB(255, 255, 255));
      TextOutW(hdc, 8, 8, L"Drag to select area (ESC to cancel)", 36);
    }

  } else if (g_overlay.mode == OverlayMode::DetectionBox) {
    COLORREF boxColors[] = {
      RGB(0, 255, 128), RGB(255, 128, 0), RGB(0, 180, 255),
      RGB(255, 60, 60), RGB(200, 0, 255), RGB(255, 255, 0),
    };
    int numColors = sizeof(boxColors) / sizeof(boxColors[0]);

    for (size_t i = 0; i < g_overlay.detection_boxes.size(); i++) {
      const auto& box = g_overlay.detection_boxes[i];
      COLORREF color = boxColors[box.class_id % numColors];

      HPEN hPen = CreatePen(PS_SOLID, 2, color);
      HBRUSH hOldBrush = (HBRUSH)SelectObject(hdc, GetStockObject(NULL_BRUSH));
      HPEN hOldPen = (HPEN)SelectObject(hdc, hPen);
      Rectangle(hdc, box.x, box.y, box.x + box.w, box.y + box.h);
      SelectObject(hdc, hOldPen);
      SelectObject(hdc, hOldBrush);
      DeleteObject(hPen);

      int labelW = 0;
      int labelH = 18;
      wchar_t label[128];
      wchar_t classNameW[64] = {};
      MultiByteToWideChar(CP_UTF8, 0, box.class_name, -1, classNameW, 64);
      swprintf_s(label, L"%s %.0f%%", classNameW, box.confidence * 100.0f);
      labelW = (int)wcslen(label) * 8 + 12;
      if (labelW < 40) labelW = 40;

      HBRUSH labelBrush = CreateSolidBrush(color);
      RECT labelRc = { box.x, box.y - labelH, box.x + labelW, box.y };
      FillRect(hdc, &labelRc, labelBrush);
      DeleteObject(labelBrush);

      SetBkColor(hdc, color);
      SetTextColor(hdc, RGB(0, 0, 0));
      TextOutW(hdc, box.x + 4, box.y - labelH + 1, label, (int)wcslen(label));
    }
  }
}

static LRESULT CALLBACK OverlayWndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  switch (msg) {
    case WM_ERASEBKGND:
      return 1; // Prevent flicker

    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC hdc = BeginPaint(hwnd, &ps);

      RECT rc;
      GetClientRect(hwnd, &rc);
      int w = rc.right;
      int h = rc.bottom;

      // Double-buffer: draw to offscreen DC, then BitBlt to screen
      EnsureOverlayBuffer(w, h);
      DrawOverlayContent(g_overlayMemDC, w, h);
      BitBlt(hdc, 0, 0, w, h, g_overlayMemDC, 0, 0, SRCCOPY);

      EndPaint(hwnd, &ps);
      return 0;
    }

    case WM_TIMER: {
      if (wp == OVERLAY_TIMER_ID && g_overlay.hwnd) {
        InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    }

    case WM_NCHITTEST: {
      if (g_overlay.mode == OverlayMode::DetectionBox) {
        return HTTRANSPARENT;
      }
      // For other modes, capture all clicks (including transparent areas)
      return HTCLIENT;
    }

    case WM_LBUTTONDOWN: {
      POINT pt;
      GetCursorPos(&pt);

      if (g_overlay.mode == OverlayMode::Crosshair) {
        if (g_overlay.channel) {
          g_overlay.channel->InvokeMethod("onOverlayClick",
            std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
              {flutter::EncodableValue("x"), flutter::EncodableValue(static_cast<int>(pt.x))},
              {flutter::EncodableValue("y"), flutter::EncodableValue(static_cast<int>(pt.y))},
            }));
        }
        DestroyOverlayWindow();
      } else if (g_overlay.mode == OverlayMode::WindowPick) {
        // Convert screen coordinates to client-area coordinates of the target window
        POINT clientPt = pt;
        if (g_overlay.target_window) {
          ScreenToClient(g_overlay.target_window, &clientPt);
        }
        if (g_overlay.channel) {
          g_overlay.channel->InvokeMethod("onOverlayWindowPick",
            std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
              {flutter::EncodableValue("x"), flutter::EncodableValue(static_cast<int>(clientPt.x))},
              {flutter::EncodableValue("y"), flutter::EncodableValue(static_cast<int>(clientPt.y))},
            }));
        }
        DestroyOverlayWindow();
      } else if (g_overlay.mode == OverlayMode::AreaSelect) {
        g_overlay.dragging = true;
        g_overlay.dragStart = pt;
        g_overlay.dragCurrent = pt;
        SetCapture(hwnd);
      }
      return 0;
    }

    case WM_MOUSEMOVE: {
      if (g_overlay.mode == OverlayMode::AreaSelect && g_overlay.dragging) {
        GetCursorPos(&g_overlay.dragCurrent);
      }
      // Don't invalidate here - the timer handles repaints
      return 0;
    }

    case WM_LBUTTONUP: {
      if (g_overlay.mode == OverlayMode::AreaSelect && g_overlay.dragging) {
        POINT pt;
        GetCursorPos(&pt);
        g_overlay.dragging = false;
        ReleaseCapture();

        int x1 = g_overlay.dragStart.x < pt.x ? g_overlay.dragStart.x : pt.x;
        int y1 = g_overlay.dragStart.y < pt.y ? g_overlay.dragStart.y : pt.y;
        int x2 = g_overlay.dragStart.x < pt.x ? pt.x : g_overlay.dragStart.x;
        int y2 = g_overlay.dragStart.y < pt.y ? pt.y : g_overlay.dragStart.y;

        if (g_overlay.channel) {
          g_overlay.channel->InvokeMethod("onOverlayAreaSelected",
            std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
              {flutter::EncodableValue("x1"), flutter::EncodableValue(x1)},
              {flutter::EncodableValue("y1"), flutter::EncodableValue(y1)},
              {flutter::EncodableValue("x2"), flutter::EncodableValue(x2)},
              {flutter::EncodableValue("y2"), flutter::EncodableValue(y2)},
            }));
        }
        DestroyOverlayWindow();
      }
      return 0;
    }

    case WM_KEYDOWN: {
      if (wp == VK_ESCAPE) {
        if (g_overlay.channel) {
          g_overlay.channel->InvokeMethod("onOverlayCancelled",
            std::make_unique<flutter::EncodableValue>(nullptr));
        }
        DestroyOverlayWindow();
      }
      return 0;
    }

    default:
      return DefWindowProc(hwnd, msg, wp, lp);
  }
}

void CreateOverlayWindow(flutter::MethodChannel<flutter::EncodableValue>* channel) {
  if (g_overlay.hwnd) {
    DestroyOverlayWindow();
  }

  static bool registered = false;
  if (!registered) {
    WNDCLASSW wc = {};
    wc.lpfnWndProc = OverlayWndProc;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.hCursor = LoadCursor(nullptr, IDC_CROSS);
    wc.hbrBackground = CreateSolidBrush(RGB(1, 1, 1));
    wc.lpszClassName = kOverlayClassName;
    RegisterClassW(&wc);
    registered = true;
  }

  g_overlay.channel = channel;
  g_overlay.dragging = false;
  g_overlay.dragStart = {};
  g_overlay.dragCurrent = {};

  int x = 0, y = 0, w = 0, h = 0;

  if (g_overlay.mode == OverlayMode::WindowPick && g_overlay.target_window) {
    // For WindowPick mode: overlay only covers the target window's client area
    RECT clientRect;
    if (GetClientRect(g_overlay.target_window, &clientRect)) {
      POINT pt = {clientRect.left, clientRect.top};
      ClientToScreen(g_overlay.target_window, &pt);
      x = pt.x;
      y = pt.y;
      w = clientRect.right - clientRect.left;
      h = clientRect.bottom - clientRect.top;
    }
    // Bring target window to foreground first
    SetForegroundWindow(g_overlay.target_window);
  }

  if (w == 0 || h == 0) {
    // Fullscreen fallback (Crosshair, AreaSelect, or failed WindowPick)
    x = 0;
    y = 0;
    w = GetSystemMetrics(SM_CXSCREEN);
    h = GetSystemMetrics(SM_CYSCREEN);
  }

  g_overlay.hwnd = CreateWindowExW(
    WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TOOLWINDOW,
    kOverlayClassName, L"",
    WS_POPUP | WS_VISIBLE,
    x, y, w, h,
    nullptr, nullptr, GetModuleHandle(nullptr), nullptr);

  // Make the whole window semi-transparent so it captures all clicks
  // LWA_ALPHA: entire window is semi-transparent, clicks are NOT passed through
  // Different alpha per mode:
  //   Crosshair/WindowPick: alpha=30 (slight tint, crosshair visible)
  //   AreaSelect: alpha=50 (moderate tint, selection rectangle visible)
  BYTE alpha = 30;
  if (g_overlay.mode == OverlayMode::AreaSelect) {
    alpha = 50;
  }
  SetLayeredWindowAttributes(g_overlay.hwnd, 0, alpha, LWA_ALPHA);

  // Start repaint timer at 30fps
  SetTimer(g_overlay.hwnd, OVERLAY_TIMER_ID, 1000 / OVERLAY_FPS, nullptr);

  // Show and focus - ensure overlay gets focus even when main window is minimized
  ShowWindow(g_overlay.hwnd, SW_SHOWNORMAL);

  // Force overlay to the foreground using multiple techniques
  DWORD overlayTid = GetWindowThreadProcessId(g_overlay.hwnd, nullptr);
  HWND fgWnd = GetForegroundWindow();
  DWORD foregroundTid = GetWindowThreadProcessId(fgWnd, nullptr);
  if (overlayTid != foregroundTid) {
    AttachThreadInput(foregroundTid, overlayTid, TRUE);
  }
  SetForegroundWindow(g_overlay.hwnd);
  SetWindowPos(g_overlay.hwnd, HWND_TOPMOST, 0, 0, 0, 0,
    SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  SetFocus(g_overlay.hwnd);
  if (overlayTid != foregroundTid) {
    AttachThreadInput(foregroundTid, overlayTid, FALSE);
  }
}

void DestroyOverlayWindow() {
  if (g_overlay.hwnd) {
    KillTimer(g_overlay.hwnd, OVERLAY_TIMER_ID);
    DestroyWindow(g_overlay.hwnd);
    g_overlay.hwnd = nullptr;
  }
  g_overlay.mode = OverlayMode::None;
  g_overlay.dragging = false;
  g_overlay.channel = nullptr;
  g_overlay.target_window = nullptr;
  g_overlay.detection_boxes.clear();
  CleanupOverlayBuffer();
}

void UpdateOverlayCrosshair() {
  if (g_overlay.hwnd) {
    InvalidateRect(g_overlay.hwnd, nullptr, FALSE);
  }
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // Initialize hold trigger critical section
  InitializeCriticalSection(&g_hold_trigger_cs);
  g_hold_trigger_cs_initialized = true;

  clicker_stopped_msg_ = RegisterWindowMessageW(L"ClickerStoppedCallback");
  g_clicker_stopped_msg = clicker_stopped_msg_;

  g_perform_click_msg = RegisterWindowMessageW(L"ClickerPerformClick");
  g_findimage_result_msg = RegisterWindowMessageW(L"ClickerFindImageResult");
  g_elem_result_msg = RegisterWindowMessageW(L"ClickerElementDumpResult");

  HWND hwnd = GetHandle();
  DragAcceptFiles(hwnd, TRUE);

  // Extend DWM frame slightly to keep window shadow and rounded corners.
  // Do NOT use {-1,-1,-1,-1} — it breaks rendering with acrylic.
  MARGINS margins = { 0, 0, 0, 1 };
  DwmExtendFrameIntoClientArea(hwnd, &margins);

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // -- Hotkey channel -------------------------------------------------------
  hotkey_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "clicker/hotkeys",
          &flutter::StandardMethodCodec::GetInstance());
  g_hotkey_channel = hotkey_channel_.get();

  hotkey_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto* args = std::get_if<flutter::EncodableList>(call.arguments());

        if (call.method_name() == "registerHotkey") {
          if (!args || args->size() < 3) {
            result->Error("INVALID_ARGS", "Expected [id, modifiers, vk]");
            return;
          }
          int id = GetInt(args->at(0));
          int modifiers = GetInt(args->at(1));
          int vk = GetInt(args->at(2));

          // Always use hook-based detection for reliable hotkey handling.
          // RegisterHotKey can fail for F-keys without modifiers and may
          // conflict with the low-level keyboard hook.
          // Unregister any previous RegisterHotKey for this id
          UnregisterHotKey(GetHandle(), id);
          registered_hotkey_ids_.erase(
              std::remove(registered_hotkey_ids_.begin(),
                          registered_hotkey_ids_.end(), id),
              registered_hotkey_ids_.end());

          // Remove any previous hook-based entry for this id
          for (int i = 0; i < g_hook_hotkey_count; i++) {
            if (g_hook_hotkeys[i].id == id) {
              g_hook_hotkeys[i] = g_hook_hotkeys[g_hook_hotkey_count - 1];
              g_hook_hotkey_count--;
              break;
            }
          }

          if (g_hook_hotkey_count < 64) {
            // Ensure keyboard hook is installed
            if (!keyboard_hook_) {
              g_flutter_window_for_hooks = this;
              keyboard_hook_ = SetWindowsHookExW(WH_KEYBOARD_LL, KeyboardHookProc, nullptr, 0);
              mouse_hook_ = SetWindowsHookExW(WH_MOUSE_LL, MouseHookProc, nullptr, 0);
            }
            g_hook_hotkeys[g_hook_hotkey_count].id = id;
            g_hook_hotkeys[g_hook_hotkey_count].modifiers = modifiers;
            g_hook_hotkeys[g_hook_hotkey_count].vk = vk;
            g_hook_hotkey_count++;
            result->Success(flutter::EncodableValue(true));
          } else {
            result->Success(flutter::EncodableValue(false));
          }
        } else if (call.method_name() == "unregisterHotkey") {
          if (!args || args->size() < 1) {
            result->Error("INVALID_ARGS", "Expected [id]");
            return;
          }
          int id = GetInt(args->at(0));
          BOOL success = UnregisterHotKey(GetHandle(), id);
          registered_hotkey_ids_.erase(
              std::remove(registered_hotkey_ids_.begin(),
                          registered_hotkey_ids_.end(), id),
              registered_hotkey_ids_.end());
          // Also remove from hook-based hotkeys
          for (int i = 0; i < g_hook_hotkey_count; i++) {
            if (g_hook_hotkeys[i].id == id) {
              g_hook_hotkeys[i] = g_hook_hotkeys[g_hook_hotkey_count - 1];
              g_hook_hotkey_count--;
              break;
            }
          }
          result->Success(flutter::EncodableValue(success != 0));
        } else if (call.method_name() == "unregisterAll") {
          for (int id : registered_hotkey_ids_) {
            UnregisterHotKey(GetHandle(), id);
          }
          registered_hotkey_ids_.clear();
          g_hook_hotkey_count = 0;
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  // -- Platform utilities channel -------------------------------------------
  platform_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "com.clicker.pro/platform",
          &flutter::StandardMethodCodec::GetInstance());

  platform_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "getCursorPosition") {
          POINT pt;
          if (GetCursorPos(&pt)) {
            flutter::EncodableMap pos;
            pos[flutter::EncodableValue("x")] = flutter::EncodableValue(static_cast<int>(pt.x));
            pos[flutter::EncodableValue("y")] = flutter::EncodableValue(static_cast<int>(pt.y));
            result->Success(flutter::EncodableValue(pos));
          } else {
            result->Error("FAILED", "GetCursorPos failed");
          }
        } else if (call.method_name() == "getClipboardImage") {
          if (!OpenClipboard(nullptr)) {
            result->Error("CLIPBOARD_BUSY", "OpenClipboard failed");
            return;
          }

          HANDLE hDrop = GetClipboardData(CF_HDROP);
          if (hDrop) {
            HDROP drop = static_cast<HDROP>(hDrop);
            const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
            flutter::EncodableList paths;
            for (UINT i = 0; i < count; ++i) {
              const UINT len = DragQueryFileW(drop, i, nullptr, 0);
              if (len == 0) continue;
              std::wstring buf(len + 1, L'\0');
              DragQueryFileW(drop, i, buf.data(), len + 1);
              buf.resize(len);
              paths.push_back(flutter::EncodableValue(_wideToUtf8(buf)));
            }
            CloseClipboard();
            if (!paths.empty()) {
              flutter::EncodableMap out;
              out[flutter::EncodableValue("paths")] = flutter::EncodableValue(paths);
              result->Success(flutter::EncodableValue(out));
              return;
            }
          }

          HANDLE hDib = GetClipboardData(CF_DIBV5);
          if (!hDib) hDib = GetClipboardData(CF_DIB);
          if (!hDib) {
            CloseClipboard();
            result->Error("NO_IMAGE", "clipboard has no image");
            return;
          }

          const size_t totalBytes = GlobalSize(hDib);
          const auto* src = static_cast<const uint8_t*>(GlobalLock(hDib));
          if (!src || totalBytes < sizeof(BITMAPINFOHEADER)) {
            if (src) GlobalUnlock(hDib);
            CloseClipboard();
            result->Error("LOCK_FAILED", "GlobalLock failed");
            return;
          }

          const auto* bih = reinterpret_cast<const BITMAPINFOHEADER*>(src);
          const int width = bih->biWidth;
          const int height = bih->biHeight < 0 ? -bih->biHeight : bih->biHeight;
          if (width <= 0 || height <= 0 || width > 16384 || height > 16384) {
            GlobalUnlock(hDib);
            CloseClipboard();
            result->Error("INVALID_SIZE", "clipboard image size out of range");
            return;
          }

          size_t headerBytes = static_cast<size_t>(bih->biSize);
          if (bih->biBitCount <= 8) {
            const size_t entries = bih->biClrUsed ? bih->biClrUsed : (static_cast<size_t>(1) << bih->biBitCount);
            headerBytes += entries * 4;
          } else if (bih->biCompression == BI_BITFIELDS && bih->biSize == sizeof(BITMAPINFOHEADER)) {
            headerBytes += 12;
          }
          if (headerBytes >= totalBytes) {
            GlobalUnlock(hDib);
            CloseClipboard();
            result->Error("INVALID_DIB", "clipboard DIB header out of range");
            return;
          }
          const uint8_t* srcBits = src + headerBytes;

          HDC hdc = GetDC(nullptr);
          BITMAPINFO target = {};
          target.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
          target.bmiHeader.biWidth = width;
          target.bmiHeader.biHeight = height;
          target.bmiHeader.biPlanes = 1;
          target.bmiHeader.biBitCount = 32;
          target.bmiHeader.biCompression = BI_RGB;

          void* bits = nullptr;
          HBITMAP hbm = CreateDIBSection(hdc, &target, DIB_RGB_COLORS, &bits, nullptr, 0);
          int copied = 0;
          if (hbm && bits) {
            copied = SetDIBits(hdc, hbm, 0, height, srcBits, reinterpret_cast<const BITMAPINFO*>(src), DIB_RGB_COLORS);
          }

          std::vector<uint8_t> pixels;
          if (copied != 0 && bits) {
            const size_t stride = static_cast<size_t>(width) * 4;
            const auto* p = static_cast<const uint8_t*>(bits);
            pixels.resize(stride * height);
            for (int y = 0; y < height; ++y) {
              memcpy(pixels.data() + static_cast<size_t>(y) * stride, p + static_cast<size_t>(height - 1 - y) * stride, stride);
            }
          }

          if (hbm) DeleteObject(hbm);
          ReleaseDC(nullptr, hdc);
          GlobalUnlock(hDib);
          CloseClipboard();

          if (pixels.empty()) {
            result->Error("CONVERT_FAILED", "SetDIBits failed");
            return;
          }

          flutter::EncodableMap out;
          out[flutter::EncodableValue("width")] = flutter::EncodableValue(width);
          out[flutter::EncodableValue("height")] = flutter::EncodableValue(height);
          out[flutter::EncodableValue("pixels")] = flutter::EncodableValue(pixels);
          result->Success(flutter::EncodableValue(out));
        } else if (call.method_name() == "getPixelColor") {
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 2) {
            result->Error("INVALID_ARGS", "Expected [x, y]");
            return;
          }
          int x = GetInt(args->at(0));
          int y = GetInt(args->at(1));
          // Convert logical pixels to physical pixels for GetPixel
          UINT dpi = GetDpiForWindow(nullptr);
          if (dpi == 0) dpi = 96;
          double dpiScale = dpi / 96.0;
          int physX = static_cast<int>(x * dpiScale);
          int physY = static_cast<int>(y * dpiScale);
          HDC hdc = GetDC(nullptr);
          COLORREF color = GetPixel(hdc, physX, physY);
          ReleaseDC(nullptr, hdc);
          int r = GetRValue(color);
          int g = GetGValue(color);
          int b = GetBValue(color);
          flutter::EncodableMap colorMap;
          colorMap[flutter::EncodableValue("r")] = flutter::EncodableValue(r);
          colorMap[flutter::EncodableValue("g")] = flutter::EncodableValue(g);
          colorMap[flutter::EncodableValue("b")] = flutter::EncodableValue(b);
          colorMap[flutter::EncodableValue("value")] = flutter::EncodableValue(static_cast<int>(color));
          result->Success(flutter::EncodableValue(colorMap));
        } else if (call.method_name() == "captureScreenRect") {
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 4) {
            result->Error("INVALID_ARGS", "Expected [x, y, w, h]");
            return;
          }
          int x = GetInt(args->at(0));
          int y = GetInt(args->at(1));
          int w = GetInt(args->at(2));
          int h = GetInt(args->at(3));
          if (w <= 0 || h <= 0 || w > 3840 || h > 2160) {
            result->Error("INVALID_SIZE", "Capture size out of range");
            return;
          }
          // Convert logical pixels to physical pixels for screen capture
          UINT dpi = GetDpiForWindow(nullptr);
          if (dpi == 0) dpi = 96;
          double dpiScale = dpi / 96.0;
          int physX = static_cast<int>(x * dpiScale);
          int physY = static_cast<int>(y * dpiScale);
          int physW = static_cast<int>(std::ceil(w * dpiScale));
          int physH = static_cast<int>(std::ceil(h * dpiScale));

          HDC hdcScreen = GetDC(nullptr);
          HDC hdcMem = CreateCompatibleDC(hdcScreen);
          HBITMAP hBitmap = CreateCompatibleBitmap(hdcScreen, physW, physH);
          HBITMAP hOld = (HBITMAP)SelectObject(hdcMem, hBitmap);
          BitBlt(hdcMem, 0, 0, physW, physH, hdcScreen, physX, physY, SRCCOPY);

          BITMAPINFOHEADER bi = {};
          bi.biSize = sizeof(BITMAPINFOHEADER);
          bi.biWidth = physW;
          bi.biHeight = -physH;
          bi.biPlanes = 1;
          bi.biBitCount = 32;
          bi.biCompression = BI_RGB;

          std::vector<uint8_t> physPixels(physW * physH * 4);
          GetDIBits(hdcMem, hBitmap, 0, physH, physPixels.data(), (BITMAPINFO*)&bi, DIB_RGB_COLORS);

          SelectObject(hdcMem, hOld);
          DeleteObject(hBitmap);
          DeleteDC(hdcMem);
          ReleaseDC(nullptr, hdcScreen);

          // Check if captured data is all zeros
          int nonZeroCount = 0;
          for (size_t i = 0; i < physPixels.size() && nonZeroCount < 10; i++) {
            if (physPixels[i] != 0) nonZeroCount++;
          }
          OutputDebugStringA(("[captureScreenRect] physPixels nonZero(first10)=" + std::to_string(nonZeroCount) + "/" + std::to_string(physPixels.size()) + "\n").c_str());

          // Downscale physical pixels back to logical pixel size for Dart
          std::vector<uint8_t> pixels(w * h * 4);
          OutputDebugStringA(("[captureScreenRect] x=" + std::to_string(x) + " y=" + std::to_string(y) + " w=" + std::to_string(w) + " h=" + std::to_string(h) + " physW=" + std::to_string(physW) + " physH=" + std::to_string(physH) + " dpiScale=" + std::to_string(dpiScale) + " physPixels=" + std::to_string(physPixels.size()) + "\n").c_str());
          if (dpiScale == 1.0) {
            pixels = std::move(physPixels);
          } else {
            for (int ly = 0; ly < h; ly++) {
              int sy = static_cast<int>(ly * dpiScale);
              if (sy >= physH) sy = physH - 1;
              for (int lx = 0; lx < w; lx++) {
                int sx = static_cast<int>(lx * dpiScale);
                if (sx >= physW) sx = physW - 1;
                int srcIdx = (sy * physW + sx) * 4;
                int dstIdx = (ly * w + lx) * 4;
                pixels[dstIdx]     = physPixels[srcIdx];
                pixels[dstIdx + 1] = physPixels[srcIdx + 1];
                pixels[dstIdx + 2] = physPixels[srcIdx + 2];
                pixels[dstIdx + 3] = physPixels[srcIdx + 3];
              }
            }
          }

          result->Success(flutter::EncodableValue(std::move(pixels)));
        } else if (call.method_name() == "getScreenSize") {
          int w = GetSystemMetrics(SM_CXSCREEN);
          int h = GetSystemMetrics(SM_CYSCREEN);
          flutter::EncodableMap sizeMap;
          sizeMap[flutter::EncodableValue("width")] = flutter::EncodableValue(w);
          sizeMap[flutter::EncodableValue("height")] = flutter::EncodableValue(h);
          result->Success(flutter::EncodableValue(sizeMap));
        } else if (call.method_name() == "getForegroundWindowTitle") {
          HWND hwnd = GetForegroundWindow();
          if (hwnd) {
            wchar_t title[256] = {};
            GetWindowTextW(hwnd, title, 256);
            // Convert wide string to UTF-8
            std::string narrow;
            int len = WideCharToMultiByte(CP_UTF8, 0, title, -1, nullptr, 0, nullptr, nullptr);
            if (len > 0) {
              narrow.resize(len - 1);
              WideCharToMultiByte(CP_UTF8, 0, title, -1, &narrow[0], len, nullptr, nullptr);
            }
            result->Success(flutter::EncodableValue(narrow));
          } else {
            result->Success(flutter::EncodableValue(""));
          }
        } else if (call.method_name() == "startPickOverlay") {
          // Start crosshair overlay for color picking
          g_overlay.mode = OverlayMode::Crosshair;
          CreateOverlayWindow(platform_channel_.get());
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "startWindowPickOverlay") {
          // Start window coordinate picking overlay over the target window
          g_overlay.mode = OverlayMode::WindowPick;
          // Get target hwnd from arguments
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (args && args->size() >= 1) {
            g_overlay.target_window = reinterpret_cast<HWND>(static_cast<intptr_t>(
              GetInt64(args->operator[](0))));
          }
          CreateOverlayWindow(platform_channel_.get());
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "startAreaSelectOverlay") {
          // Start area selection overlay
          g_overlay.mode = OverlayMode::AreaSelect;
          CreateOverlayWindow(platform_channel_.get());
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "stopOverlay") {
          DestroyOverlayWindow();
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "showDetectionBoxes") {
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 1) {
            result->Error("INVALID_ARGS", "Expected [boxes]");
            return;
          }
          g_overlay.detection_boxes.clear();
          const auto* boxes = std::get_if<flutter::EncodableList>(&args->at(0));
          if (boxes) {
            for (const auto& item : *boxes) {
              const auto* box_map = std::get_if<flutter::EncodableMap>(&item);
              if (!box_map) continue;
              DetectionBox db = {};
              auto it = box_map->find(flutter::EncodableValue("x"));
              if (it != box_map->end()) { if (auto* v = std::get_if<int32_t>(&it->second)) db.x = *v; }
              it = box_map->find(flutter::EncodableValue("y"));
              if (it != box_map->end()) { if (auto* v = std::get_if<int32_t>(&it->second)) db.y = *v; }
              it = box_map->find(flutter::EncodableValue("w"));
              if (it != box_map->end()) { if (auto* v = std::get_if<int32_t>(&it->second)) db.w = *v; }
              it = box_map->find(flutter::EncodableValue("h"));
              if (it != box_map->end()) { if (auto* v = std::get_if<int32_t>(&it->second)) db.h = *v; }
              it = box_map->find(flutter::EncodableValue("confidence"));
              if (it != box_map->end()) { if (auto* v = std::get_if<double>(&it->second)) db.confidence = (float)*v; }
              it = box_map->find(flutter::EncodableValue("class_id"));
              if (it != box_map->end()) { if (auto* v = std::get_if<int32_t>(&it->second)) db.class_id = *v; }
              it = box_map->find(flutter::EncodableValue("class_name"));
              if (it != box_map->end()) { if (auto* v = std::get_if<std::string>(&it->second)) {
                strncpy_s(db.class_name, v->c_str(), 63);
              }}
              g_overlay.detection_boxes.push_back(db);
            }
          }
          if (!g_overlay.hwnd || g_overlay.mode != OverlayMode::DetectionBox) {
            g_overlay.mode = OverlayMode::DetectionBox;
            CreateOverlayWindow(platform_channel_.get());
          } else {
            InvalidateRect(g_overlay.hwnd, nullptr, FALSE);
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "updateDetectionBoxes") {
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 1) {
            result->Error("INVALID_ARGS", "Expected [boxes]");
            return;
          }
          g_overlay.detection_boxes.clear();
          const auto* boxes = std::get_if<flutter::EncodableList>(&args->at(0));
          if (boxes) {
            for (const auto& item : *boxes) {
              const auto* box_map = std::get_if<flutter::EncodableMap>(&item);
              if (!box_map) continue;
              DetectionBox db = {};
              auto it = box_map->find(flutter::EncodableValue("x"));
              if (it != box_map->end()) { if (auto* v = std::get_if<int32_t>(&it->second)) db.x = *v; }
              it = box_map->find(flutter::EncodableValue("y"));
              if (it != box_map->end()) { if (auto* v = std::get_if<int32_t>(&it->second)) db.y = *v; }
              it = box_map->find(flutter::EncodableValue("w"));
              if (it != box_map->end()) { if (auto* v = std::get_if<int32_t>(&it->second)) db.w = *v; }
              it = box_map->find(flutter::EncodableValue("h"));
              if (it != box_map->end()) { if (auto* v = std::get_if<int32_t>(&it->second)) db.h = *v; }
              it = box_map->find(flutter::EncodableValue("confidence"));
              if (it != box_map->end()) { if (auto* v = std::get_if<double>(&it->second)) db.confidence = (float)*v; }
              it = box_map->find(flutter::EncodableValue("class_id"));
              if (it != box_map->end()) { if (auto* v = std::get_if<int32_t>(&it->second)) db.class_id = *v; }
              it = box_map->find(flutter::EncodableValue("class_name"));
              if (it != box_map->end()) { if (auto* v = std::get_if<std::string>(&it->second)) {
                strncpy_s(db.class_name, v->c_str(), 63);
              }}
              g_overlay.detection_boxes.push_back(db);
            }
          }
          if (g_overlay.hwnd && g_overlay.mode == OverlayMode::DetectionBox) {
            InvalidateRect(g_overlay.hwnd, nullptr, FALSE);
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "findImage") {
          // Template matching: find a template image within a screen region
          // Args: [regionX, regionY, regionW, regionH, templateBgraBytes, templateW, templateH, threshold]
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 8) {
            result->Error("INVALID_ARGS", "Expected [regionX, regionY, regionW, regionH, templateBgraBytes, templateW, templateH, threshold]");
            return;
          }
          int regionX = GetInt(args->at(0));
          int regionY = GetInt(args->at(1));
          int regionW = GetInt(args->at(2));
          int regionH = GetInt(args->at(3));
          const auto* tplBytes = std::get_if<flutter::EncodableList>(&args->at(4));
          const auto* tplBytesUint8 = std::get_if<std::vector<uint8_t>>(&args->at(4));
          int tplW = GetInt(args->at(5));
          int tplH = GetInt(args->at(6));
          double threshold = 0.8;
          if (const auto* d = std::get_if<double>(&args->at(7))) threshold = *d;
          else if (const auto* i32 = std::get_if<int32_t>(&args->at(7))) threshold = static_cast<double>(*i32);
          else if (const auto* i64 = std::get_if<int64_t>(&args->at(7))) threshold = static_cast<double>(*i64);

          std::string tplKey;
          if (args->size() >= 11) {
            if (const auto* s = std::get_if<std::string>(&args->at(10))) tplKey = *s;
          }

          if ((!tplBytes && !tplBytesUint8 && tplKey.empty()) || tplW <= 0 || tplH <= 0 || regionW <= 0 || regionH <= 0) {
            result->Error("INVALID_ARGS", "Invalid template or region dimensions");
            return;
          }

          // Optional args: [8] maxResults (default 1), [9] scales (default [1.0])
          int maxResults = 1;
          if (args->size() >= 9) {
            if (const auto* v = std::get_if<int32_t>(&args->at(8))) maxResults = *v;
            else if (const auto* v64 = std::get_if<int64_t>(&args->at(8))) maxResults = static_cast<int>(*v64);
            else if (const auto* vd = std::get_if<double>(&args->at(8))) maxResults = static_cast<int>(*vd);
          }
          if (maxResults < 1) maxResults = 1;
          if (maxResults > 200) maxResults = 200;

          std::vector<double> scales;
          if (args->size() >= 10) {
            if (const auto* list = std::get_if<flutter::EncodableList>(&args->at(9))) {
              for (const auto& v : *list) {
                if (const auto* d = std::get_if<double>(&v)) scales.push_back(*d);
                else if (const auto* i32 = std::get_if<int32_t>(&v)) scales.push_back(static_cast<double>(*i32));
                else if (const auto* i64 = std::get_if<int64_t>(&v)) scales.push_back(static_cast<double>(*i64));
              }
            }
          }
          {
            std::vector<double> clean;
            for (double s : scales) {
              if (s >= 0.2 && s <= 5.0) clean.push_back(s);
            }
            if (clean.empty()) clean.push_back(1.0);
            scales = clean;
          }

          // 模板同样只保留亮度；给了指纹且本地已缓存时，像素不必重传
          std::vector<uint8_t> tplGray;
          if (!tplBytes && !tplBytesUint8) {
            std::lock_guard<std::mutex> lock(g_tpl_cache_mutex);
            auto it = g_tpl_cache.find(tplKey);
            if (it == g_tpl_cache.end() || it->second.w != tplW || it->second.h != tplH) {
              result->Error("TEMPLATE_NOT_CACHED", "模板缓存未命中，请随请求重发模板像素");
              return;
            }
            tplGray = it->second.gray;
          } else {
            std::vector<uint8_t> tplData;
            if (tplBytesUint8) {
              tplData = std::move(*const_cast<std::vector<uint8_t>*>(tplBytesUint8));
            } else {
              tplData.resize(tplBytes->size());
              for (size_t idx = 0; idx < tplBytes->size(); idx++) {
                if (const auto* b32 = std::get_if<int32_t>(&tplBytes->at(idx))) tplData[idx] = static_cast<uint8_t>(*b32);
                else if (const auto* b64 = std::get_if<int64_t>(&tplBytes->at(idx))) tplData[idx] = static_cast<uint8_t>(*b64);
              }
            }
            const size_t expectedTplSize = static_cast<size_t>(tplW) * tplH * 4;
            if (tplData.size() < expectedTplSize) {
              result->Error("INVALID_ARGS", "Template data size mismatch: expected " + std::to_string(expectedTplSize) + " got " + std::to_string(tplData.size()));
              return;
            }
            tplGray = _bgraToGray(tplData.data(), tplW, tplH);
            if (!tplKey.empty()) {
              std::lock_guard<std::mutex> lock(g_tpl_cache_mutex);
              if (g_tpl_cache.size() >= 64) g_tpl_cache.clear();
              g_tpl_cache[tplKey] = CachedTemplate{tplW, tplH, tplGray};
            }
          }

          // Get DPI scale factor: capture at physical pixels, then downscale to logical for matching
          UINT dpi = GetDpiForWindow(nullptr);
          if (dpi == 0) dpi = 96;
          double dpiScale = dpi / 96.0;
          int physRegionX = static_cast<int>(regionX * dpiScale);
          int physRegionY = static_cast<int>(regionY * dpiScale);
          int physRegionW = static_cast<int>(std::ceil(regionW * dpiScale));
          int physRegionH = static_cast<int>(std::ceil(regionH * dpiScale));

          // Capture the screen region (physical pixel coordinates)
          HDC hdcScreen = GetDC(nullptr);
          HDC hdcMem = CreateCompatibleDC(hdcScreen);
          HBITMAP hBitmap = CreateCompatibleBitmap(hdcScreen, physRegionW, physRegionH);
          HBITMAP hOld = (HBITMAP)SelectObject(hdcMem, hBitmap);
          BitBlt(hdcMem, 0, 0, physRegionW, physRegionH, hdcScreen, physRegionX, physRegionY, SRCCOPY);

          BITMAPINFOHEADER bi = {};
          bi.biSize = sizeof(BITMAPINFOHEADER);
          bi.biWidth = physRegionW;
          bi.biHeight = -physRegionH;
          bi.biPlanes = 1;
          bi.biBitCount = 32;
          bi.biCompression = BI_RGB;

          std::vector<uint8_t> physRegionPixels(physRegionW * physRegionH * 4);
          GetDIBits(hdcMem, hBitmap, 0, physRegionH, physRegionPixels.data(), (BITMAPINFO*)&bi, DIB_RGB_COLORS);
          SelectObject(hdcMem, hOld);
          DeleteObject(hBitmap);
          DeleteDC(hdcMem);
          ReleaseDC(nullptr, hdcScreen);

          // 降采样时直接转成灰度：后续 NCC 只在这一张上算
          std::vector<uint8_t> regionGray(static_cast<size_t>(regionW) * regionH);
          if (dpiScale == 1.0) {
            for (int i = 0, n = regionW * regionH; i < n; i++) {
              regionGray[i] = _lumaOf(physRegionPixels[i * 4], physRegionPixels[i * 4 + 1], physRegionPixels[i * 4 + 2]);
            }
          } else {
            for (int ly = 0; ly < regionH; ly++) {
              int sy = static_cast<int>(ly * dpiScale);
              if (sy >= physRegionH) sy = physRegionH - 1;
              uint8_t* drow = regionGray.data() + static_cast<size_t>(ly) * regionW;
              for (int lx = 0; lx < regionW; lx++) {
                int sx = static_cast<int>(lx * dpiScale);
                if (sx >= physRegionW) sx = physRegionW - 1;
                const int srcIdx = (sy * physRegionW + sx) * 4;
                drow[lx] = _lumaOf(physRegionPixels[srcIdx], physRegionPixels[srcIdx + 1], physRegionPixels[srcIdx + 2]);
              }
            }
          }

          // Check if captured data is all zeros
          {
            int nonZeroCount = 0;
            for (size_t i = 0; i < physRegionPixels.size() && nonZeroCount < 10; i++) {
              if (physRegionPixels[i] != 0) nonZeroCount++;
            }
            OutputDebugStringA(("[findImage] physRegionPixels nonZero(first10)=" + std::to_string(nonZeroCount) + "/" + std::to_string(physRegionPixels.size()) + "\n").c_str());
          }

          // Template matching using normalized cross-correlation (in logical pixel space)
          int searchW = regionW - tplW + 1;
          int searchH = regionH - tplH + 1;
          if (searchW <= 0 || searchH <= 0) {
            result->Success(flutter::EncodableValue(flutter::EncodableList()));
            return;
          }

          // 帧指纹：画面与全部参数都没变时直接复用上次结果，省掉整轮匹配
          const uint64_t regionHash = _fnv1a(regionGray.data(), regionGray.size());
          const uint64_t tplHash = _fnv1a(tplGray.data(), tplGray.size());
          {
            std::lock_guard<std::mutex> lock(g_frame_cache_mutex);
            if (g_frame_cache.valid &&
                g_frame_cache.regionHash == regionHash &&
                g_frame_cache.tplHash == tplHash &&
                g_frame_cache.regionX == regionX && g_frame_cache.regionY == regionY &&
                g_frame_cache.regionW == regionW && g_frame_cache.regionH == regionH &&
                g_frame_cache.threshold == threshold &&
                g_frame_cache.maxResults == maxResults &&
                g_frame_cache.scales == scales) {
              result->Success(flutter::EncodableValue(_matchesToEncodable(g_frame_cache.matches, g_frame_cache.bestScore)));
              return;
            }
          }

          auto result_ptr = result.release();
          int resultId = g_findimage_next_id.fetch_add(1);
          HWND hwnd = GetHandle();

          std::thread([result_ptr, regionGray=std::move(regionGray), tplGray0=std::move(tplGray),
                       regionX, regionY, regionW, regionH, tplW0=tplW, tplH0=tplH,
                       threshold, maxResults, scales, regionHash, tplHash, resultId, hwnd]() {
            std::vector<MatchBox> found;

            std::map<int, GrayRegion> levelCache;
            levelCache.emplace(1, _makeGrayRegion(regionGray, regionW, regionH));
            const GrayRegion& base = levelCache.at(1);

            // 区域金字塔按需构建：模板够大时先在缩小的层级上粗搜，省掉大量无谓位置
            auto regionAt = [&](int level) -> const GrayRegion& {
              auto it = levelCache.find(level);
              if (it != levelCache.end()) return it->second;
              const int dw = std::max(1, base.w / level);
              const int dh = std::max(1, base.h / level);
              auto px = _resampleGray(base.px, base.w, base.h, dw, dh);
              return levelCache.emplace(level, _makeGrayRegion(std::move(px), dw, dh)).first->second;
            };

            const double minTplDim = static_cast<double>(std::min(tplW0, tplH0));
            auto levelFor = [minTplDim](double s) -> int {
              const double d = minTplDim * s;
              if (d >= 72.0) return 4;
              if (d >= 36.0) return 2;
              return 1;
            };

            double globalBest = -1.0;

            std::vector<double> orderedScales;
            orderedScales.reserve(scales.size());
            for (double s : scales) { if (std::abs(s - 1.0) < 1e-9) orderedScales.push_back(s); }
            for (double s : scales) { if (std::abs(s - 1.0) >= 1e-9) orderedScales.push_back(s); }

            auto hasHitAtThreshold = [&]() {
              for (const auto& f : found) { if (f.score >= threshold) return true; }
              return false;
            };

            for (double scale : orderedScales) {
              const int level = levelFor(scale);
              const GrayRegion& reg = regionAt(level);

              const int coarseW = static_cast<int>(std::lround(tplW0 * scale / level));
              const int coarseH = static_cast<int>(std::lround(tplH0 * scale / level));
              if (coarseW < 2 || coarseH < 2 || coarseW > reg.w || coarseH > reg.h) continue;

              const GrayTemplate coarseTpl = (coarseW == tplW0 && coarseH == tplH0)
                  ? _makeGrayTemplate(tplGray0, tplW0, tplH0)
                  : _makeGrayTemplate(_resampleGray(tplGray0, tplW0, tplH0, coarseW, coarseH), coarseW, coarseH);

              const int searchW = reg.w - coarseW + 1;
              const int searchH = reg.h - coarseH + 1;
              if (searchW <= 0 || searchH <= 0) continue;

              struct CoarseHit { int sx; int sy; double score; };

              const long long tplArea = static_cast<long long>(coarseW) * coarseH;
              const long long gridPositions = static_cast<long long>(searchW) * searchH;
              const int coarseStep = (tplArea <= 4096 && tplArea * gridPositions <= 1500000000LL) ? 1 : 2;

              const int coarseRows = (searchH + coarseStep - 1) / coarseStep;
              const int coarseCols = (searchW + coarseStep - 1) / coarseStep;
              std::vector<double> coarseMap(static_cast<size_t>(coarseRows) * coarseCols, -2.0);
              std::vector<double> coarseMax(8, -1.0);

              _parallelRows(coarseRows, [&](int ti, int nThreads) {
                double localMax = -1.0;
                for (int r = ti; r < coarseRows; r += nThreads) {
                  const int sy = r * coarseStep;
                  if (sy >= searchH) continue;
                  double* row = coarseMap.data() + static_cast<size_t>(r) * coarseCols;
                  int col = 0;
                  for (int sx = 0; sx < searchW; sx += coarseStep, col++) {
                    const double ncc = _nccAt(reg, coarseTpl, sx, sy);
                    row[col] = ncc;
                    if (ncc > localMax) localMax = ncc;
                  }
                }
                coarseMax[static_cast<size_t>(ti)] = localMax;
              });

              for (double v : coarseMax) { if (v > globalBest) globalBest = v; }

              std::vector<CoarseHit> maxima;
              for (int r = 0; r < coarseRows; r++) {
                const double* row = coarseMap.data() + static_cast<size_t>(r) * coarseCols;
                const double* up = r > 0 ? row - coarseCols : nullptr;
                const double* down = r + 1 < coarseRows ? row + coarseCols : nullptr;
                for (int c = 0; c < coarseCols; c++) {
                  const double v = row[c];
                  if (v < -1.5) continue;
                  bool isMax = true;
                  for (int dr = -1; dr <= 1 && isMax; dr++) {
                    const double* nb = dr < 0 ? up : (dr > 0 ? down : row);
                    if (nb == nullptr) continue;
                    for (int dc = -1; dc <= 1; dc++) {
                      if (dr == 0 && dc == 0) continue;
                      const int nc = c + dc;
                      if (nc < 0 || nc >= coarseCols) continue;
                      if (nb[nc] > v) { isMax = false; break; }
                    }
                  }
                  if (isMax) maxima.push_back({c * coarseStep, r * coarseStep, v});
                }
              }

              std::sort(maxima.begin(), maxima.end(),
                        [](const CoarseHit& a, const CoarseHit& b) { return a.score > b.score; });

              std::vector<CoarseHit> candidates;
              const int candidateLimit = 256;
              for (const auto& m : maxima) {
                bool overlaps = false;
                for (const auto& k : candidates) {
                  const int ix1 = std::max(m.sx, k.sx);
                  const int iy1 = std::max(m.sy, k.sy);
                  const int ix2 = std::min(m.sx + coarseW, k.sx + coarseW);
                  const int iy2 = std::min(m.sy + coarseH, k.sy + coarseH);
                  if (ix2 <= ix1 || iy2 <= iy1) continue;
                  const double inter = static_cast<double>(ix2 - ix1) * (iy2 - iy1);
                  const double uni = 2.0 * coarseW * coarseH - inter;
                  if (uni > 0.0 && inter / uni >= 0.5) { overlaps = true; break; }
                }
                if (overlaps) continue;
                candidates.push_back(m);
                if (static_cast<int>(candidates.size()) >= candidateLimit) break;
              }

              if (level == 1 && coarseStep == 1) {
                for (const auto& m : maxima) {
                  if (m.score >= threshold) {
                    found.push_back({m.score, regionX + m.sx, regionY + m.sy, coarseW, coarseH});
                  }
                }
                if (hasHitAtThreshold()) break;
                continue;
              }

              const int fineW = static_cast<int>(std::lround(tplW0 * scale));
              const int fineH = static_cast<int>(std::lround(tplH0 * scale));
              if (fineW < 1 || fineH < 1 || fineW > regionW || fineH > regionH) continue;

              const GrayTemplate fineTpl = (fineW == tplW0 && fineH == tplH0)
                  ? _makeGrayTemplate(tplGray0, tplW0, tplH0)
                  : _makeGrayTemplate(_resampleGray(tplGray0, tplW0, tplH0, fineW, fineH), fineW, fineH);

              const int fineSearchW = base.w - fineW + 1;
              const int fineSearchH = base.h - fineH + 1;
              if (fineSearchW <= 0 || fineSearchH <= 0) continue;

              const int radius = std::min(2 * level, 8);
              std::set<std::pair<int, int>> fineSet;
              for (const auto& c : candidates) {
                const int cx = c.sx * level;
                const int cy = c.sy * level;
                for (int dy = -radius; dy <= radius; dy++) {
                  const int ny = cy + dy;
                  if (ny < 0 || ny >= fineSearchH) continue;
                  for (int dx = -radius; dx <= radius; dx++) {
                    const int nx = cx + dx;
                    if (nx < 0 || nx >= fineSearchW) continue;
                    fineSet.insert({nx, ny});
                  }
                }
              }

              std::vector<std::pair<int, int>> fineList(fineSet.begin(), fineSet.end());
              std::vector<std::vector<MatchBox>> fineHits(8);
              std::vector<double> fineMax(8, -1.0);
              _parallelRows(static_cast<int>(fineList.size()), [&](int ti, int nThreads) {
                auto& out = fineHits[static_cast<size_t>(ti)];
                double localMax = -1.0;
                for (size_t i = static_cast<size_t>(ti); i < fineList.size(); i += static_cast<size_t>(nThreads)) {
                  const auto& p = fineList[i];
                  const double ncc = _nccAt(base, fineTpl, p.first, p.second);
                  if (ncc > localMax) localMax = ncc;
                  if (ncc >= threshold) {
                    out.push_back({ncc, regionX + p.first, regionY + p.second, fineW, fineH});
                  }
                }
                fineMax[static_cast<size_t>(ti)] = localMax;
              });
              for (double v : fineMax) { if (v > globalBest) globalBest = v; }
              for (const auto& v : fineHits) found.insert(found.end(), v.begin(), v.end());

              if (hasHitAtThreshold()) break;
            }

            // 跨尺度去重：按分数降序贪心保留，IoU 超阈值的丢弃
            std::sort(found.begin(), found.end(),
              [](const MatchBox& a, const MatchBox& b) { return a.score > b.score; });

            std::vector<MatchBox> kept;
            for (const auto& m : found) {
              bool overlaps = false;
              for (const auto& k : kept) {
                int ix1 = std::max(m.x, k.x);
                int iy1 = std::max(m.y, k.y);
                int ix2 = std::min(m.x + m.w, k.x + k.w);
                int iy2 = std::min(m.y + m.h, k.y + k.h);
                int iw = ix2 - ix1;
                int ih = iy2 - iy1;
                if (iw <= 0 || ih <= 0) continue;
                double inter = (double)iw * ih;
                double uni = (double)m.w * m.h + (double)k.w * k.h - inter;
                if (uni > 0 && inter / uni > 0.3) { overlaps = true; break; }
              }
              if (overlaps) continue;
              kept.push_back(m);
              if ((int)kept.size() >= maxResults) break;
            }

            OutputDebugStringA(("[findImage] final: matches=" + std::to_string(kept.size()) + "\n").c_str());

            {
              std::lock_guard<std::mutex> lock(g_frame_cache_mutex);
              g_frame_cache.valid = true;
              g_frame_cache.regionHash = regionHash;
              g_frame_cache.tplHash = tplHash;
              g_frame_cache.regionX = regionX;
              g_frame_cache.regionY = regionY;
              g_frame_cache.regionW = regionW;
              g_frame_cache.regionH = regionH;
              g_frame_cache.threshold = threshold;
              g_frame_cache.maxResults = maxResults;
              g_frame_cache.scales = scales;
              g_frame_cache.matches = kept;
              g_frame_cache.bestScore = globalBest;
            }

            // Post result back to main thread via Windows message
            {
              FindImageResultData data;
              data.result_ptr = result_ptr;
              data.bestScore = globalBest;
              data.bestX = kept.empty() ? -1 : kept.front().x;
              data.bestY = kept.empty() ? -1 : kept.front().y;
              data.tplW = kept.empty() ? tplW0 : kept.front().w;
              data.tplH = kept.empty() ? tplH0 : kept.front().h;
              data.matches = std::move(kept);
              std::lock_guard<std::mutex> lock(g_findimage_mutex);
              g_findimage_results[resultId] = std::move(data);
            }
            PostMessage(hwnd, g_findimage_result_msg, (WPARAM)resultId, 0);
          }).detach();
        } else if (call.method_name() == "dumpElements") {
          // Args: [maxDepth, maxElements, rootHwnd]
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          int maxDepth = 6;
          int maxElements = 400;
          int64_t rootHwnd = 0;
          if (args) {
            if (args->size() >= 1) maxDepth = GetInt(args->at(0));
            if (args->size() >= 2) maxElements = GetInt(args->at(1));
            if (args->size() >= 3) rootHwnd = GetInt64(args->at(2));
          }
          if (maxDepth < 1) maxDepth = 1;
          if (maxDepth > 20) maxDepth = 20;
          if (maxElements < 1) maxElements = 1;
          if (maxElements > 4000) maxElements = 4000;

          UINT elemDpi = GetDpiForWindow(nullptr);
          if (elemDpi == 0) elemDpi = 96;
          const double elemDpiScale = elemDpi / 96.0;

          auto result_ptr = result.release();
          const int elemResultId = g_elem_next_id.fetch_add(1);
          HWND elemHwnd = GetHandle();
          std::thread([result_ptr, maxDepth, maxElements, rootHwnd, elemDpiScale, elemResultId, elemHwnd]() {
            CoInitializeEx(nullptr, COINIT_MULTITHREADED);
            ElementDumpResult data;
            data.result_ptr = std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>(result_ptr);

            IUIAutomation* automation = nullptr;
            HRESULT hr = CoCreateInstance(__uuidof(CUIAutomation), nullptr, CLSCTX_INPROC_SERVER,
                                          __uuidof(IUIAutomation), reinterpret_cast<void**>(&automation));
            if (FAILED(hr) || !automation) {
              data.error = "UI Automation 初始化失败";
            } else {
              IUIAutomationElement* root = nullptr;
              if (rootHwnd != 0) {
                automation->ElementFromHandle(reinterpret_cast<UIA_HWND>(static_cast<INT_PTR>(rootHwnd)), &root);
              } else {
                automation->GetRootElement(&root);
              }
              IUIAutomationTreeWalker* walker = nullptr;
              automation->get_ControlViewWalker(&walker);
              if (!root) {
                data.error = "找不到根元素";
              } else if (!walker) {
                data.error = "控件树遍历器不可用";
              } else {
                ElementCollector collector;
                collector.walker = walker;
                collector.maxDepth = maxDepth;
                collector.maxElements = maxElements;
                collector.dpiScale = elemDpiScale;
                collector.walk(root, 0);
                data.elements = std::move(collector.out);
                data.truncated = collector.truncated;
              }
              if (walker) walker->Release();
              if (root) root->Release();
              automation->Release();
            }
            CoUninitialize();

            {
              std::lock_guard<std::mutex> lock(g_elem_mutex);
              g_elem_results[elemResultId] = std::move(data);
            }
            PostMessage(elemHwnd, g_elem_result_msg, (WPARAM)elemResultId, 0);
          }).detach();
        } else if (call.method_name() == "capturePng" || call.method_name() == "captureAnnotatedPng") {
          // Args: [x, y, w, h] 或 [x, y, w, h, marks, maxWidth]
          const bool annotated = call.method_name() == "captureAnnotatedPng";
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 4) {
            result->Error("INVALID_ARGS", annotated ? "Expected [x, y, w, h, marks, maxWidth?]" : "Expected [x, y, w, h, maxWidth?]");
            return;
          }
          const int pngX = GetInt(args->at(0));
          const int pngY = GetInt(args->at(1));
          const int pngW = GetInt(args->at(2));
          const int pngH = GetInt(args->at(3));
          if (pngW <= 0 || pngH <= 0) {
            result->Error("INVALID_ARGS", "Invalid region dimensions");
            return;
          }

          std::vector<MarkRect> marks;
          int maxWidth = 0;
          if (annotated) {
            if (args->size() >= 5) {
              if (const auto* list = std::get_if<flutter::EncodableList>(&args->at(4))) {
                for (const auto& item : *list) {
                  const auto* m = std::get_if<flutter::EncodableMap>(&item);
                  if (!m) continue;
                  MarkRect mk;
                  auto getI = [&](const char* key) -> int {
                    auto it = m->find(flutter::EncodableValue(key));
                    return it == m->end() ? 0 : GetInt(it->second);
                  };
                  mk.x = getI("x");
                  mk.y = getI("y");
                  mk.w = getI("width");
                  mk.h = getI("height");
                  auto it = m->find(flutter::EncodableValue("label"));
                  if (it != m->end()) {
                    if (const auto* s = std::get_if<std::string>(&it->second)) mk.label = _utf8ToWide(*s);
                  }
                  marks.push_back(std::move(mk));
                }
              }
            }
            if (args->size() >= 6) maxWidth = GetInt(args->at(5));
          } else if (args->size() >= 5) {
            maxWidth = GetInt(args->at(4));
          }
          if (maxWidth < 0) maxWidth = 0;
          if (maxWidth > 8192) maxWidth = 8192;

          const int outW = (maxWidth > 0 && maxWidth < pngW) ? maxWidth : pngW;
          const int outH = (outW == pngW) ? pngH : static_cast<int>(std::lround(pngH * (double)outW / pngW));
          const double pngScale = (double)outW / pngW;

          auto result_ptr = result.release();
          std::thread([result_ptr, pngX, pngY, pngW, pngH, outW, outH, pngScale, marks=std::move(marks)]() {
            auto bgra = _captureAnnotatedBgra(pngX, pngY, pngW, pngH, outW, outH, marks, pngScale);
            if (bgra.empty()) {
              result_ptr->Error("CAPTURE_FAILED", "屏幕捕获失败");
              delete result_ptr;
              return;
            }
            auto png = _encodePngFromBgra(std::move(bgra), outW, outH);
            if (png.empty()) {
              result_ptr->Error("ENCODE_FAILED", "PNG 编码失败");
              delete result_ptr;
              return;
            }
            flutter::EncodableMap payload;
            payload[flutter::EncodableValue("bytes")] = flutter::EncodableValue(png);
            payload[flutter::EncodableValue("width")] = flutter::EncodableValue(outW);
            payload[flutter::EncodableValue("height")] = flutter::EncodableValue(outH);
            payload[flutter::EncodableValue("scale")] = flutter::EncodableValue(pngScale);
            result_ptr->Success(flutter::EncodableValue(payload));
            delete result_ptr;
          }).detach();
        } else if (call.method_name() == "ocrRegion") {
          // OCR a screen region using Windows.Media.Ocr (C++/WinRT)
          // Args: [x, y, w, h, language]
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 4) {
            result->Error("INVALID_ARGS", "Expected [x, y, w, h, language?]");
            return;
          }
          int ocrX = GetInt(args->at(0));
          int ocrY = GetInt(args->at(1));
          int ocrW = GetInt(args->at(2));
          int ocrH = GetInt(args->at(3));
          std::string lang = "en";
          if (args->size() >= 5) {
            if (const auto* s = std::get_if<std::string>(&args->at(4))) lang = *s;
          }

          if (ocrW <= 0 || ocrH <= 0 || ocrW > 3840 || ocrH > 2160) {
            result->Error("INVALID_SIZE", "OCR region size out of range");
            return;
          }

          // Convert logical pixels to physical pixels for screen capture
          UINT dpi = GetDpiForWindow(nullptr);
          if (dpi == 0) dpi = 96;
          double dpiScale = dpi / 96.0;
          int physOcrX = static_cast<int>(ocrX * dpiScale);
          int physOcrY = static_cast<int>(ocrY * dpiScale);
          int physOcrW = static_cast<int>(std::ceil(ocrW * dpiScale));
          int physOcrH = static_cast<int>(std::ceil(ocrH * dpiScale));

          // Capture the region as BGRA pixels (physical pixel coordinates)
          HDC hdcScreen = GetDC(nullptr);
          HDC hdcMem = CreateCompatibleDC(hdcScreen);
          HBITMAP hBitmap = CreateCompatibleBitmap(hdcScreen, physOcrW, physOcrH);
          HBITMAP hOld = (HBITMAP)SelectObject(hdcMem, hBitmap);
          BitBlt(hdcMem, 0, 0, physOcrW, physOcrH, hdcScreen, physOcrX, physOcrY, SRCCOPY);

          BITMAPINFOHEADER bi = {};
          bi.biSize = sizeof(BITMAPINFOHEADER);
          bi.biWidth = physOcrW;
          bi.biHeight = -physOcrH; // top-down
          bi.biPlanes = 1;
          bi.biBitCount = 32;
          bi.biCompression = BI_RGB;

          std::vector<uint8_t> pixels(physOcrW * physOcrH * 4);
          GetDIBits(hdcMem, hBitmap, 0, physOcrH, pixels.data(), (BITMAPINFO*)&bi, DIB_RGB_COLORS);
          SelectObject(hdcMem, hOld);
          DeleteObject(hBitmap);
          DeleteDC(hdcMem);
          ReleaseDC(nullptr, hdcScreen);

          // Convert BGRA to RGBA for SoftwareBitmap
          std::vector<uint8_t> rgba(physOcrW * physOcrH * 4);
          for (int i = 0; i < physOcrW * physOcrH; i++) {
            rgba[i*4+0] = pixels[i*4+2]; // R
            rgba[i*4+1] = pixels[i*4+1]; // G
            rgba[i*4+2] = pixels[i*4+0]; // B
            rgba[i*4+3] = pixels[i*4+3]; // A
          }

          // Run OCR on a background thread to avoid blocking the platform thread.
          auto result_ptr = result.release();
          std::thread([result_ptr, rgba=std::move(rgba), pixels=std::move(pixels),
                       ocrX, ocrY, ocrW, ocrH, physOcrW, physOcrH, lang]() {
            try {
              // Initialize WinRT on this background thread (multi-threaded apartment for background use)
              winrt::init_apartment(winrt::apartment_type::multi_threaded);

              auto softwareBitmap = winrt::Windows::Graphics::Imaging::SoftwareBitmap(
                winrt::Windows::Graphics::Imaging::BitmapPixelFormat::Rgba8,
                physOcrW, physOcrH,
                winrt::Windows::Graphics::Imaging::BitmapAlphaMode::Premultiplied);

              {
                auto dataWriter = winrt::Windows::Storage::Streams::DataWriter();
                dataWriter.WriteBytes(winrt::array_view<uint8_t const>(rgba));
                auto buffer = dataWriter.DetachBuffer();
                softwareBitmap.CopyFromBuffer(buffer);
              }

              winrt::Windows::Media::Ocr::OcrEngine ocrEngine = nullptr;
              if (lang != "" && lang != "en") {
                std::vector<std::string> langCandidates;
                if (lang.find("zh") != std::string::npos) {
                  langCandidates = {"zh-Hans-CN", "zh-CN", "zh-Hans", "zh-CHS"};
                } else if (lang.find("ja") != std::string::npos) {
                  langCandidates = {"ja", "ja-JP"};
                } else if (lang.find("ko") != std::string::npos) {
                  langCandidates = {"ko", "ko-KR"};
                } else if (lang.find("en") != std::string::npos) {
                  langCandidates = {"en-US", "en-GB", "en"};
                } else {
                  langCandidates = {lang};
                }
                for (const auto& lc : langCandidates) {
                  try {
                    auto language = winrt::Windows::Globalization::Language(winrt::to_hstring(lc));
                    ocrEngine = winrt::Windows::Media::Ocr::OcrEngine::TryCreateFromLanguage(language);
                    if (ocrEngine != nullptr) break;
                  } catch (...) {}
                }
              }
              if (ocrEngine == nullptr) {
                ocrEngine = winrt::Windows::Media::Ocr::OcrEngine::TryCreateFromUserProfileLanguages();
              }
              if (ocrEngine == nullptr) {
                result_ptr->Error("OCR_NOT_AVAILABLE", "Windows OCR engine not available. Install OCR language pack from Windows Settings > Time & Language > Language & region.");
                delete result_ptr;
                return;
              }

              auto ocrResult = ocrEngine.RecognizeAsync(softwareBitmap).get();
              auto ocrText = winrt::to_string(ocrResult.Text());

              flutter::EncodableMap resultMap;
              resultMap[flutter::EncodableValue("text")] = flutter::EncodableValue(ocrText);
              resultMap[flutter::EncodableValue("x")] = flutter::EncodableValue(ocrX);
              resultMap[flutter::EncodableValue("y")] = flutter::EncodableValue(ocrY);
              resultMap[flutter::EncodableValue("width")] = flutter::EncodableValue(ocrW);
              resultMap[flutter::EncodableValue("height")] = flutter::EncodableValue(ocrH);
              result_ptr->Success(flutter::EncodableValue(resultMap));
            } catch (const winrt::hresult_error& ex) {
              std::string winrtError = winrt::to_string(ex.message());
              std::string ocrText;
              bool fallbackOk = _ocrFallbackPython(pixels, physOcrW, physOcrH, lang, ocrText)
                             || _ocrFallbackPowerShell(pixels, physOcrW, physOcrH, lang, ocrText);
              if (fallbackOk) {
                flutter::EncodableMap resultMap;
                resultMap[flutter::EncodableValue("text")] = flutter::EncodableValue(ocrText);
                resultMap[flutter::EncodableValue("x")] = flutter::EncodableValue(ocrX);
                resultMap[flutter::EncodableValue("y")] = flutter::EncodableValue(ocrY);
                resultMap[flutter::EncodableValue("width")] = flutter::EncodableValue(ocrW);
                resultMap[flutter::EncodableValue("height")] = flutter::EncodableValue(ocrH);
                result_ptr->Success(flutter::EncodableValue(resultMap));
              } else {
                result_ptr->Error("OCR_ERROR", ("WinRT: " + winrtError + ". Fallback methods also failed.").c_str());
              }
            } catch (const std::exception& ex) {
              std::string ocrText;
              bool fallbackOk = _ocrFallbackPython(pixels, physOcrW, physOcrH, lang, ocrText)
                             || _ocrFallbackPowerShell(pixels, physOcrW, physOcrH, lang, ocrText);
              if (fallbackOk) {
                flutter::EncodableMap resultMap;
                resultMap[flutter::EncodableValue("text")] = flutter::EncodableValue(ocrText);
                resultMap[flutter::EncodableValue("x")] = flutter::EncodableValue(ocrX);
                resultMap[flutter::EncodableValue("y")] = flutter::EncodableValue(ocrY);
                resultMap[flutter::EncodableValue("width")] = flutter::EncodableValue(ocrW);
                resultMap[flutter::EncodableValue("height")] = flutter::EncodableValue(ocrH);
                result_ptr->Success(flutter::EncodableValue(resultMap));
              } else {
                result_ptr->Error("OCR_ERROR", ex.what());
              }
            } catch (...) {
              std::string ocrText;
              bool fallbackOk = _ocrFallbackPython(pixels, physOcrW, physOcrH, lang, ocrText)
                             || _ocrFallbackPowerShell(pixels, physOcrW, physOcrH, lang, ocrText);
              if (fallbackOk) {
                flutter::EncodableMap resultMap;
                resultMap[flutter::EncodableValue("text")] = flutter::EncodableValue(ocrText);
                resultMap[flutter::EncodableValue("x")] = flutter::EncodableValue(ocrX);
                resultMap[flutter::EncodableValue("y")] = flutter::EncodableValue(ocrY);
                resultMap[flutter::EncodableValue("width")] = flutter::EncodableValue(ocrW);
                resultMap[flutter::EncodableValue("height")] = flutter::EncodableValue(ocrH);
                result_ptr->Success(flutter::EncodableValue(resultMap));
              } else {
                result_ptr->Error("OCR_ERROR", "All OCR methods failed");
              }
            }
            delete result_ptr;
          }).detach();
        } else if (call.method_name() == "sendClick") {
          // Send a mouse click at (x, y)
          // Args: [x, y, button]  button: 0=left, 1=right, 2=middle
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 2) {
            result->Error("INVALID_ARGS", "Expected [x, y, button?]");
            return;
          }
          int clickX = GetInt(args->at(0));
          int clickY = GetInt(args->at(1));
          int button = args->size() >= 3 ? GetInt(args->at(2)) : 0;

          INPUT inputs[3] = {};
          // Move mouse
          inputs[0].type = INPUT_MOUSE;
          inputs[0].mi.dx = (LONG)(clickX * 65535.0 / (GetSystemMetrics(SM_CXSCREEN) - 1));
          inputs[0].mi.dy = (LONG)(clickY * 65535.0 / (GetSystemMetrics(SM_CYSCREEN) - 1));
          inputs[0].mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_MOVE;
          // Down
          inputs[1].type = INPUT_MOUSE;
          inputs[1].mi.dx = inputs[0].mi.dx;
          inputs[1].mi.dy = inputs[0].mi.dy;
          inputs[1].mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_MOVE |
            (button == 1 ? MOUSEEVENTF_RIGHTDOWN : button == 2 ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_LEFTDOWN);
          // Up
          inputs[2].type = INPUT_MOUSE;
          inputs[2].mi.dx = inputs[0].mi.dx;
          inputs[2].mi.dy = inputs[0].mi.dy;
          inputs[2].mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_MOVE |
            (button == 1 ? MOUSEEVENTF_RIGHTUP : button == 2 ? MOUSEEVENTF_MIDDLEUP : MOUSEEVENTF_LEFTUP);

          SendInput(3, inputs, sizeof(INPUT));
          result->Success();

        } else if (call.method_name() == "sendKeyPress") {
          // Send a key press
          // Args: keyName (string) or keyCode (int) or [keyName/codigo]
          DWORD vk = 0;
          // Try direct string argument first
          if (const auto* s = std::get_if<std::string>(call.arguments())) {
            if (*s == "Enter" || *s == "Return") vk = VK_RETURN;
            else if (*s == "Space") vk = VK_SPACE;
            else if (*s == "Tab") vk = VK_TAB;
            else if (*s == "Escape" || *s == "Esc") vk = VK_ESCAPE;
            else if (*s == "Backspace") vk = VK_BACK;
            else if (*s == "Delete") vk = VK_DELETE;
            else if (s->size() == 1) vk = VkKeyScanA(s->at(0)) & 0xFF;
          } else if (const auto* args = std::get_if<flutter::EncodableList>(call.arguments())) {
            if (!args->empty()) {
              if (const auto* s2 = std::get_if<std::string>(&args->at(0))) {
                if (*s2 == "Enter" || *s2 == "Return") vk = VK_RETURN;
                else if (*s2 == "Space") vk = VK_SPACE;
                else if (*s2 == "Tab") vk = VK_TAB;
                else if (*s2 == "Escape" || *s2 == "Esc") vk = VK_ESCAPE;
                else if (*s2 == "Backspace") vk = VK_BACK;
                else if (*s2 == "Delete") vk = VK_DELETE;
                else if (s2->size() == 1) vk = VkKeyScanA(s2->at(0)) & 0xFF;
              } else {
                vk = GetInt(args->at(0));
              }
            }
          }
          if (vk != 0) {
            INPUT inputs[2] = {};
            inputs[0].type = INPUT_KEYBOARD;
            inputs[0].ki.wVk = (WORD)vk;
            inputs[1].type = INPUT_KEYBOARD;
            inputs[1].ki.wVk = (WORD)vk;
            inputs[1].ki.dwFlags = KEYEVENTF_KEYUP;
            SendInput(2, inputs, sizeof(INPUT));
          }
          result->Success();

        } else if (call.method_name() == "checkOcrAvailable") {
          // Check if Windows OCR engine is available (WinRT)
          auto result_ptr = result.release();
          std::thread([result_ptr]() {
            try {
              winrt::init_apartment(winrt::apartment_type::multi_threaded);
              auto ocrEngine = winrt::Windows::Media::Ocr::OcrEngine::TryCreateFromUserProfileLanguages();
              flutter::EncodableMap checkMap;
              checkMap[flutter::EncodableValue("available")] = flutter::EncodableValue(ocrEngine != nullptr);
              result_ptr->Success(flutter::EncodableValue(checkMap));
            } catch (...) {
              flutter::EncodableMap checkMap;
              checkMap[flutter::EncodableValue("available")] = flutter::EncodableValue(false);
              result_ptr->Success(flutter::EncodableValue(checkMap));
            }
            delete result_ptr;
          }).detach();

        } else if (call.method_name() == "checkOcrTools") {
          // Check if Tesseract and Python+pytesseract are available.
          // Run checks on a background thread to avoid blocking the platform thread,
          // which would freeze the entire UI.
          auto result_ptr = result.release();
          std::thread([result_ptr]() {
            flutter::EncodableMap toolMap;
            // Check Tesseract via 'where' command
            {
              std::string output;
              int ret = _runCommandHidden("where tesseract 2>nul", output);
              bool tessOk = (ret == 0 && !output.empty());
              toolMap[flutter::EncodableValue("tesseract")] = flutter::EncodableValue(tessOk);
            }
            // Check Python + pytesseract
            {
              bool pyOk = false;
              for (const char* pyCmd : {"python", "python3", "py"}) {
                std::string cmd = std::string(pyCmd) + " -c \"import pytesseract\" 2>nul";
                int ret = _runCommandHidden(cmd);
                if (ret == 0) { pyOk = true; break; }
              }
              toolMap[flutter::EncodableValue("python")] = flutter::EncodableValue(pyOk);
            }
            result_ptr->Success(flutter::EncodableValue(toolMap));
            delete result_ptr;
          }).detach();

        } else if (call.method_name() == "installOcrTool") {
          // Install OCR tool: "tesseract" or "python"
          std::string tool;
          if (const auto* s = std::get_if<std::string>(call.arguments())) {
            tool = *s;
          } else if (const auto* args = std::get_if<flutter::EncodableList>(call.arguments())) {
            if (!args->empty() && std::holds_alternative<std::string>(args->at(0)))
              tool = std::get<std::string>(args->at(0));
          }

          if (tool == "tesseract") {
            // Install Tesseract via winget, fallback to chocolatey — run on background thread
            auto result_ptr = result.release();
            std::thread([result_ptr]() {
              bool ok = false;
              {
                int ret = _runCommandHidden("winget install --id UB-Mannheim.TesseractOCR -e --accept-source-agreements --accept-package-agreements 2>&1");
                ok = (ret == 0);
              }
              if (!ok) {
                int ret = _runCommandHidden("choco install tesseract -y 2>&1");
                ok = (ret == 0);
              }
              if (ok) result_ptr->Success();
              else result_ptr->Error("INSTALL_FAILED", "Failed to install Tesseract OCR. Please install manually from https://github.com/UB-Mannheim/tesseract/wiki");
              delete result_ptr;
            }).detach();
          } else if (tool == "python") {
            // Install Python + pytesseract + Pillow — run on background thread
            auto result_ptr = result.release();
            std::thread([result_ptr]() {
              bool ok = false;
              {
                int ret = _runCommandHidden("winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements 2>&1");
                ok = (ret == 0);
              }
              _runCommandHidden("python -m pip install pytesseract Pillow 2>&1");
              _runCommandHidden("python3 -m pip install pytesseract Pillow 2>&1");
              _runCommandHidden("py -m pip install pytesseract Pillow 2>&1");
              if (ok) result_ptr->Success();
              else result_ptr->Error("INSTALL_FAILED", "Failed to install Python. Please install manually from https://python.org");
              delete result_ptr;
            }).detach();
          } else {
            result->Error("INVALID_TOOL", "Unknown tool: " + tool);
          }

        } else if (call.method_name() == "uninstallOcrTool") {
          std::string tool;
          if (const auto* s = std::get_if<std::string>(call.arguments())) {
            tool = *s;
          } else if (const auto* args = std::get_if<flutter::EncodableList>(call.arguments())) {
            if (!args->empty() && std::holds_alternative<std::string>(args->at(0)))
              tool = std::get<std::string>(args->at(0));
          }

          if (tool == "tesseract") {
            auto result_ptr = result.release();
            std::thread([result_ptr]() {
              _runCommandHidden("winget uninstall --id UB-Mannheim.TesseractOCR -e 2>&1");
              result_ptr->Success();
              delete result_ptr;
            }).detach();
          } else if (tool == "python") {
            auto result_ptr = result.release();
            std::thread([result_ptr]() {
              _runCommandHidden("python -m pip uninstall pytesseract Pillow -y 2>&1");
              result_ptr->Success();
              delete result_ptr;
            }).detach();
          } else {
            result->Error("INVALID_TOOL", "Unknown tool: " + tool);
          }

        } else if (call.method_name() == "checkPaddleOcr") {
          auto result_ptr = result.release();
          std::thread([result_ptr]() {
            bool pyOk = false;
            for (const char* pyCmd : {"python", "python3", "py"}) {
              std::string cmd = std::string(pyCmd) + " -c \"import paddleocr\" 2>nul";
              int ret = _runCommandHidden(cmd);
              if (ret == 0) { pyOk = true; break; }
            }
            flutter::EncodableMap checkMap;
            checkMap[flutter::EncodableValue("available")] = flutter::EncodableValue(pyOk);
            result_ptr->Success(flutter::EncodableValue(checkMap));
            delete result_ptr;
          }).detach();

        } else if (call.method_name() == "installPaddleOcr") {
          auto result_ptr = result.release();
          std::string mirrorUrl;
          if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
            if (auto it = args->find(flutter::EncodableValue("mirror")); it != args->end()) {
              if (const auto* s = std::get_if<std::string>(&it->second)) {
                mirrorUrl = *s;
              }
            }
          }
          std::thread([result_ptr, mirrorUrl]() {
            bool ok = false;
            if (!mirrorUrl.empty()) {
              for (const char* pipCmd : {"python -m pip", "python3 -m pip", "py -m pip"}) {
                std::string cmd = std::string(pipCmd) + " install paddlepaddle paddleocr -i " + mirrorUrl + " 2>&1";
                int ret = _runCommandHidden(cmd);
                if (ret == 0) { ok = true; break; }
              }
            }
            if (!ok) {
              for (const char* pipCmd : {"python -m pip", "python3 -m pip", "py -m pip"}) {
                std::string cmd = std::string(pipCmd) + " install paddlepaddle paddleocr 2>&1";
                int ret = _runCommandHidden(cmd);
                if (ret == 0) { ok = true; break; }
              }
            }
            if (!ok) {
              for (const char* pipCmd : {"python -m pip", "python3 -m pip", "py -m pip"}) {
                std::string cmd = std::string(pipCmd) + " install paddlepaddle paddleocr -i https://pypi.tuna.tsinghua.edu.cn/simple 2>&1";
                int ret = _runCommandHidden(cmd);
                if (ret == 0) { ok = true; break; }
              }
            }
            if (ok) result_ptr->Success();
            else result_ptr->Error("INSTALL_FAILED", "Failed to install PaddleOCR. Please install manually: pip install paddlepaddle paddleocr");
            delete result_ptr;
          }).detach();

        } else if (call.method_name() == "uninstallPaddleOcr") {
          auto result_ptr = result.release();
          std::thread([result_ptr]() {
            for (const char* pipCmd : {"python -m pip", "python3 -m pip", "py -m pip"}) {
              std::string cmd = std::string(pipCmd) + " uninstall paddleocr paddlepaddle -y 2>&1";
              _runCommandHidden(cmd);
            }
            result_ptr->Success();
            delete result_ptr;
          }).detach();

        } else if (call.method_name() == "paddleOcrRegion") {
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 4) {
            result->Error("INVALID_ARGS", "Expected [x, y, w, h, language?]");
            return;
          }
          int ocrX = GetInt(args->at(0));
          int ocrY = GetInt(args->at(1));
          int ocrW = GetInt(args->at(2));
          int ocrH = GetInt(args->at(3));
          std::string lang = "ch";
          if (args->size() >= 5) {
            if (const auto* s = std::get_if<std::string>(&args->at(4))) {
              if (s->find("zh") != std::string::npos || s->find("ch") != std::string::npos) lang = "ch";
              else if (s->find("en") != std::string::npos) lang = "en";
              else if (s->find("ja") != std::string::npos) lang = "japan";
              else if (s->find("ko") != std::string::npos) lang = "korean";
              else lang = *s;
            }
          }

          if (ocrW <= 0 || ocrH <= 0 || ocrW > 3840 || ocrH > 2160) {
            result->Error("INVALID_SIZE", "OCR region size out of range");
            return;
          }

          HDC hdcScreen = GetDC(nullptr);
          HDC hdcMem = CreateCompatibleDC(hdcScreen);
          HBITMAP hBitmap = CreateCompatibleBitmap(hdcScreen, ocrW, ocrH);
          HBITMAP hOld = (HBITMAP)SelectObject(hdcMem, hBitmap);
          BitBlt(hdcMem, 0, 0, ocrW, ocrH, hdcScreen, ocrX, ocrY, SRCCOPY);

          BITMAPINFOHEADER bi = {};
          bi.biSize = sizeof(BITMAPINFOHEADER);
          bi.biWidth = ocrW;
          bi.biHeight = -ocrH;
          bi.biPlanes = 1;
          bi.biBitCount = 32;
          bi.biCompression = BI_RGB;

          std::vector<uint8_t> pixels(ocrW * ocrH * 4);
          GetDIBits(hdcMem, hBitmap, 0, ocrH, pixels.data(), (BITMAPINFO*)&bi, DIB_RGB_COLORS);
          SelectObject(hdcMem, hOld);
          DeleteObject(hBitmap);
          DeleteDC(hdcMem);
          ReleaseDC(nullptr, hdcScreen);

          std::string bmpPath = _ocrSaveTempBmp(pixels, ocrW, ocrH);
          if (bmpPath.empty()) {
            result->Error("SAVE_FAILED", "Failed to save temp BMP for PaddleOCR");
            return;
          }

          auto result_ptr = result.release();
          std::thread([result_ptr, bmpPath, ocrX, ocrY, ocrW, ocrH, lang]() {
            std::string safeTempDir = _getSafeTempDir();
            std::string pyPath = safeTempDir + "clicker_paddle_" +
              std::to_string(GetCurrentProcessId()) + "_" + std::to_string(GetTickCount64()) + ".py";

            FILE* pyf = nullptr;
            fopen_s(&pyf, pyPath.c_str(), "w");
            if (!pyf) {
              remove(bmpPath.c_str());
              result_ptr->Error("SCRIPT_ERROR", "Failed to create PaddleOCR script");
              delete result_ptr;
              return;
            }

            fprintf(pyf,
              "import sys\n"
              "import json\n"
              "import traceback\n"
              "import os\n"
              "import shutil\n"
              "os.environ['FLAGS_fraction_of_gpu_memory_to_use'] = '0.1'\n"
              "def try_ocr(lang, img_path, retry=True):\n"
              "  try:\n"
              "    from paddleocr import PaddleOCR\n"
              "    ocr = PaddleOCR(use_angle_cls=True, lang=lang)\n"
              "    result = ocr.ocr(img_path, cls=True)\n"
              "    lines = []\n"
              "    all_text = []\n"
              "    if result and result[0]:\n"
              "      for line in result[0]:\n"
              "        text = line[1][0]\n"
              "        confidence = line[1][1]\n"
              "        box = line[0]\n"
              "        x1 = int(box[0][0])\n"
              "        y1 = int(box[0][1])\n"
              "        x2 = int(box[2][0])\n"
              "        y2 = int(box[2][1])\n"
              "        lines.append({'text': text, 'x': x1, 'y': y1, 'width': x2-x1, 'height': y2-y1, 'confidence': confidence})\n"
              "        all_text.append(text)\n"
              "    output = {'text': '\\n'.join(all_text), 'lines': lines}\n"
              "    return output\n"
              "  except Exception as e:\n"
              "    err_str = str(e)\n"
              "    if 'parse_error' in err_str and retry:\n"
              "      for cache_dir in [os.path.expanduser('~/.paddleocr'), os.path.expanduser('~/inference')]:\n"
              "        if os.path.exists(cache_dir):\n"
              "          shutil.rmtree(cache_dir, ignore_errors=True)\n"
              "      return try_ocr(lang, img_path, retry=False)\n"
              "    raise\n"
              "try:\n"
              "  output = try_ocr('%s', r'%s')\n"
              "  print('<<PADDLE_OCR_JSON>>' + json.dumps(output, ensure_ascii=False))\n"
              "except Exception as e:\n"
              "  paddle_ver = 'unknown'\n"
              "  ocr_ver = 'unknown'\n"
              "  try:\n"
              "    import paddle; paddle_ver = paddle.__version__\n"
              "  except: pass\n"
              "  try:\n"
              "    import paddleocr; ocr_ver = paddleocr.__version__\n"
              "  except: pass\n"
              "  err_info = 'paddle=' + paddle_ver + ' paddleocr=' + ocr_ver + ' error=' + str(e)\n"
              "  print('<<PADDLE_OCR_JSON>>' + json.dumps({'error': err_info, 'traceback': traceback.format_exc()}, ensure_ascii=False))\n",
              lang.c_str(), bmpPath.c_str());
            fclose(pyf);

            std::string ocrOutput;
            std::string lastPyCmd;
            int lastRet = -1;
            bool foundPy = false;
            for (const char* pyCmd : {"python", "python3", "py"}) {
              std::string cmd = std::string(pyCmd) + " \"" + pyPath + "\"";
              lastPyCmd = cmd;
              std::string output;
              int ret = _runCommandHidden(cmd, output);
              lastRet = ret;
              if (ret == 0) {
                ocrOutput = output;
                foundPy = true;
                break;
              }
              // If python is found but script fails, keep the error output
              if (!output.empty()) {
                ocrOutput = output;
              }
            }

            remove(bmpPath.c_str());
            remove(pyPath.c_str());

            if (!foundPy || ocrOutput.empty()) {
              std::string errMsg = "PaddleOCR execution failed";
              if (lastRet != -1) {
                errMsg += " (exit=" + std::to_string(lastRet) + ")";
              }
              if (!ocrOutput.empty()) {
                // Append last few lines of output for diagnosis
                size_t maxLen = std::min(ocrOutput.size(), (size_t)500);
                errMsg += ": " + ocrOutput.substr(ocrOutput.size() - maxLen);
              }
              result_ptr->Error("PADDLE_OCR_ERROR", errMsg.c_str());
              delete result_ptr;
              return;
            }

            while (!ocrOutput.empty() && (ocrOutput.back() == '\n' || ocrOutput.back() == '\r' || ocrOutput.back() == ' '))
              ocrOutput.pop_back();

            // Try to find JSON output using our marker — PaddlePaddle may output
            // warnings/errors to stderr (like json.exception.parse_error) which we ignore
            const char* marker = "<<PADDLE_OCR_JSON>>";
            size_t markerPos = ocrOutput.find(marker);
            if (markerPos == std::string::npos) {
              // No JSON found — return raw output for diagnosis
              std::string rawErr = "PaddleOCR: no JSON output";
              if (!ocrOutput.empty()) {
                size_t maxLen = std::min(ocrOutput.size(), (size_t)500);
                rawErr += ": " + ocrOutput.substr(0, maxLen);
              }
              result_ptr->Error("PADDLE_OCR_ERROR", rawErr.c_str());
              delete result_ptr;
              return;
            }
            std::string jsonStr = ocrOutput.substr(markerPos + strlen(marker));

            std::string fullText;
            flutter::EncodableList lineList;
            bool hasError = false;
            std::string errorMsg;

            size_t textPos = jsonStr.find("\"text\":");
            size_t errorPos = jsonStr.find("\"error\":");

            if (errorPos != std::string::npos && (textPos == std::string::npos || errorPos < textPos)) {
              size_t q1 = jsonStr.find('"', errorPos + 8);
              if (q1 != std::string::npos) {
                size_t q2 = jsonStr.find('"', q1 + 1);
                if (q2 != std::string::npos) errorMsg = jsonStr.substr(q1 + 1, q2 - q1 - 1);
              }
              hasError = true;
            }

            if (hasError) {
              result_ptr->Error("PADDLE_OCR_ERROR", ("PaddleOCR: " + errorMsg).c_str());
              delete result_ptr;
              return;
            }

            if (textPos != std::string::npos) {
              size_t q1 = jsonStr.find('"', textPos + 7);
              if (q1 != std::string::npos) {
                size_t q2 = q1 + 1;
                while (q2 < jsonStr.size()) {
                  if (jsonStr[q2] == '"' && jsonStr[q2-1] != '\\') break;
                  q2++;
                }
                fullText = jsonStr.substr(q1 + 1, q2 - q1 - 1);
                std::string escNewline = "\\n";
                size_t pos = 0;
                while ((pos = fullText.find(escNewline, pos)) != std::string::npos) {
                  fullText.replace(pos, 2, "\n");
                  pos++;
                }
              }
            }

            size_t linesPos = jsonStr.find("\"lines\":");
            if (linesPos != std::string::npos) {
              size_t arrStart = jsonStr.find('[', linesPos);
              if (arrStart != std::string::npos) {
                int depth = 0;
                size_t arrEnd = arrStart;
                for (size_t i = arrStart; i < jsonStr.size(); i++) {
                  if (jsonStr[i] == '[') depth++;
                  else if (jsonStr[i] == ']') { depth--; if (depth == 0) { arrEnd = i; break; } }
                }
                std::string linesArr = jsonStr.substr(arrStart, arrEnd - arrStart + 1);

                size_t searchPos = 0;
                while (true) {
                  size_t objStart = linesArr.find('{', searchPos);
                  if (objStart == std::string::npos) break;
                  size_t objEnd = linesArr.find('}', objStart);
                  if (objEnd == std::string::npos) break;
                  std::string obj = linesArr.substr(objStart, objEnd - objStart + 1);
                  searchPos = objEnd + 1;

                  auto extractStr = [&](const std::string& key) -> std::string {
                    size_t kp = obj.find("\"" + key + "\":");
                    if (kp == std::string::npos) return "";
                    size_t q1 = obj.find('"', kp + key.size() + 3);
                    if (q1 == std::string::npos) return "";
                    size_t q2 = obj.find('"', q1 + 1);
                    if (q2 == std::string::npos) return "";
                    return obj.substr(q1 + 1, q2 - q1 - 1);
                  };
                  auto extractInt = [&](const std::string& key) -> int {
                    size_t kp = obj.find("\"" + key + "\":");
                    if (kp == std::string::npos) return 0;
                    size_t vp = kp + key.size() + 2;
                    while (vp < obj.size() && (obj[vp] == ' ' || obj[vp] == ':')) vp++;
                    std::string numStr;
                    while (vp < obj.size() && (obj[vp] == '-' || (obj[vp] >= '0' && obj[vp] <= '9'))) {
                      numStr += obj[vp]; vp++;
                    }
                    return numStr.empty() ? 0 : std::stoi(numStr);
                  };

                  flutter::EncodableMap lineMap;
                  lineMap[flutter::EncodableValue("text")] = flutter::EncodableValue(extractStr("text"));
                  lineMap[flutter::EncodableValue("x")] = flutter::EncodableValue(extractInt("x"));
                  lineMap[flutter::EncodableValue("y")] = flutter::EncodableValue(extractInt("y"));
                  lineMap[flutter::EncodableValue("width")] = flutter::EncodableValue(extractInt("width"));
                  lineMap[flutter::EncodableValue("height")] = flutter::EncodableValue(extractInt("height"));
                  lineList.push_back(flutter::EncodableValue(lineMap));
                }
              }
            }

            flutter::EncodableMap resultMap;
            resultMap[flutter::EncodableValue("text")] = flutter::EncodableValue(fullText);
            resultMap[flutter::EncodableValue("x")] = flutter::EncodableValue(ocrX);
            resultMap[flutter::EncodableValue("y")] = flutter::EncodableValue(ocrY);
            resultMap[flutter::EncodableValue("width")] = flutter::EncodableValue(ocrW);
            resultMap[flutter::EncodableValue("height")] = flutter::EncodableValue(ocrH);
            resultMap[flutter::EncodableValue("lines")] = flutter::EncodableValue(lineList);
            result_ptr->Success(flutter::EncodableValue(resultMap));
            delete result_ptr;
          }).detach();

        } else if (call.method_name() == "saveScreenshot") {
          // Save a screen region as PNG file
          // Args: [x, y, w, h, filePath]
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 5) {
            result->Error("INVALID_ARGS", "Expected [x, y, w, h, filePath]");
            return;
          }
          int ssX = GetInt(args->at(0));
          int ssY = GetInt(args->at(1));
          int ssW = GetInt(args->at(2));
          int ssH = GetInt(args->at(3));
          std::string filePath;
          if (const auto* s = std::get_if<std::string>(&args->at(4))) filePath = *s;

          if (ssW <= 0 || ssH <= 0 || filePath.empty()) {
            result->Error("INVALID_ARGS", "Invalid screenshot parameters");
            return;
          }

          // Capture screen region
          HDC hdcScreen = GetDC(nullptr);
          HDC hdcMem = CreateCompatibleDC(hdcScreen);
          HBITMAP hBitmap = CreateCompatibleBitmap(hdcScreen, ssW, ssH);
          HBITMAP hOld = (HBITMAP)SelectObject(hdcMem, hBitmap);
          BitBlt(hdcMem, 0, 0, ssW, ssH, hdcScreen, ssX, ssY, SRCCOPY);

          // Save as BMP (PNG requires GDI+ or WIC, BMP is simpler and sufficient for template matching)
          BITMAPINFOHEADER bi = {};
          bi.biSize = sizeof(BITMAPINFOHEADER);
          bi.biWidth = ssW;
          bi.biHeight = ssH; // bottom-up
          bi.biPlanes = 1;
          bi.biBitCount = 32;
          bi.biCompression = BI_RGB;

          std::vector<uint8_t> pixels(ssW * ssH * 4);
          GetDIBits(hdcMem, hBitmap, 0, ssH, pixels.data(), (BITMAPINFO*)&bi, DIB_RGB_COLORS);
          SelectObject(hdcMem, hOld);
          DeleteObject(hBitmap);
          DeleteDC(hdcMem);
          ReleaseDC(nullptr, hdcScreen);

          // Write BMP file
          std::wstring wFilePath(filePath.begin(), filePath.end());
          FILE* f = nullptr;
          _wfopen_s(&f, wFilePath.c_str(), L"wb");
          if (f) {
            BITMAPFILEHEADER bfh = {};
            bfh.bfType = 0x4D42;
            bfh.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
            bfh.bfSize = bfh.bfOffBits + (DWORD)pixels.size();

            BITMAPINFOHEADER bmi = {};
            bmi.biSize = sizeof(BITMAPINFOHEADER);
            bmi.biWidth = ssW;
            bmi.biHeight = ssH;
            bmi.biPlanes = 1;
            bmi.biBitCount = 32;
            bmi.biCompression = BI_RGB;
            bmi.biSizeImage = (DWORD)pixels.size();

            fwrite(&bfh, sizeof(bfh), 1, f);
            fwrite(&bmi, sizeof(bmi), 1, f);
            fwrite(pixels.data(), 1, pixels.size(), f);
            fclose(f);
            result->Success(flutter::EncodableValue(true));
          } else {
            result->Error("FILE_ERROR", "Failed to save screenshot");
          }
        } else if (call.method_name() == "initSystemTray") {
          InitSystemTray();
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "destroySystemTray") {
          DestroySystemTray();
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "showSystemTray") {
          ShowSystemTray();
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "hideSystemTray") {
          HideSystemTray();
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "startFastClicker") {
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 5) {
            result->Error("INVALID_ARGS", "Expected [intervalUs, x, y, button, targetCount]");
            return;
          }
          int intervalUs = GetInt(args->at(0));
          int x = GetInt(args->at(1));
          int y = GetInt(args->at(2));
          int button = GetInt(args->at(3));
          int targetCount = GetInt(args->at(4));
          // Optional background mode params: [backgroundMode, hwnd, clientX, clientY]
          bool bgMode = false;
          HWND targetHwnd = nullptr;
          int clientX = 0, clientY = 0;
          if (args->size() >= 9) {
            const auto* bgPtr = std::get_if<bool>(&args->at(5));
            bgMode = bgPtr ? *bgPtr : false;
            int64_t hwndVal = GetInt64(args->at(6));
            targetHwnd = reinterpret_cast<HWND>(static_cast<intptr_t>(hwndVal));
            clientX = GetInt(args->at(7));
            clientY = GetInt(args->at(8));
          }
          // Optional keyboard mode params: [isKeyboard, keyVk, keyActionMode, comboKeys...]
          bool isKeyboard = false;
          int keyVk = 0;
          int keyActionMode = 0;
          std::vector<int> comboKeys;
          int dartGeneration = 0;
          if (args->size() >= 12) {
            const auto* kbPtr = std::get_if<bool>(&args->at(9));
            isKeyboard = kbPtr ? *kbPtr : false;
            keyVk = GetInt(args->at(10));
            keyActionMode = GetInt(args->at(11));
            // combo keys start at index 12, last arg is dartGeneration
            for (size_t i = 12; i < args->size() - 1; i++) {
              comboKeys.push_back(GetInt(args->at(i)));
            }
            // Last argument is Dart-side generation counter
            if (args->size() > 12) {
              dartGeneration = GetInt(args->at(args->size() - 1));
            }
          }
          g_clicker.dart_generation = dartGeneration;
          StartFastClicker(intervalUs, x, y, button, targetCount, bgMode, targetHwnd, clientX, clientY,
              isKeyboard, keyVk, keyActionMode, comboKeys);
          result->Success(flutter::EncodableValue(static_cast<int>(g_clicker.generation)));
        } else if (call.method_name() == "stopFastClicker") {
          StopFastClicker();
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "getClickCount") {
          result->Success(flutter::EncodableValue(g_clicker.click_count));
        } else if (call.method_name() == "getClickerDebugInfo") {
          result->Success(flutter::EncodableValue(flutter::EncodableMap{
            {flutter::EncodableValue("running"), flutter::EncodableValue(g_clicker.running ? 1 : 0)},
            {flutter::EncodableValue("stop_requested"), flutter::EncodableValue(g_clicker.stop_requested ? 1 : 0)},
            {flutter::EncodableValue("click_count"), flutter::EncodableValue(g_clicker.click_count)},
            {flutter::EncodableValue("generation"), flutter::EncodableValue(static_cast<int>(g_clicker.generation))},
            {flutter::EncodableValue("thread_alive"), flutter::EncodableValue(clicker_thread_ ? 1 : 0)},
            {flutter::EncodableValue("interval_ms"), flutter::EncodableValue(g_clicker.interval_us / 1000.0)},
            {flutter::EncodableValue("x"), flutter::EncodableValue(g_clicker.x)},
            {flutter::EncodableValue("y"), flutter::EncodableValue(g_clicker.y)},
            {flutter::EncodableValue("button"), flutter::EncodableValue(g_clicker.button)},
            {flutter::EncodableValue("is_keyboard"), flutter::EncodableValue(g_clicker.is_keyboard ? 1 : 0)},
          }));
        } else if (call.method_name() == "enableAutoStart") {
          // Add to Windows startup registry
          HKEY hKey;
          wchar_t exePath[MAX_PATH];
          GetModuleFileNameW(nullptr, exePath, MAX_PATH);
          if (RegOpenKeyExW(HKEY_CURRENT_USER,
              L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
              0, KEY_SET_VALUE, &hKey) == ERROR_SUCCESS) {
            RegSetValueExW(hKey, L"Clicker", 0, REG_SZ,
                (const BYTE*)exePath, static_cast<DWORD>((wcslen(exePath) + 1) * sizeof(wchar_t)));
            RegCloseKey(hKey);
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "disableAutoStart") {
          // Remove from Windows startup registry
          HKEY hKey;
          if (RegOpenKeyExW(HKEY_CURRENT_USER,
              L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
              0, KEY_SET_VALUE, &hKey) == ERROR_SUCCESS) {
            RegDeleteValueW(hKey, L"Clicker");
            RegCloseKey(hKey);
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "captureKey") {
          // Start capturing next key press for UI key selection
          g_capturing_key = true;
          g_capture_channel = platform_channel_.get();
          // Install hooks if not already installed
          if (!keyboard_hook_) {
            g_flutter_window_for_hooks = this;
            keyboard_hook_ = SetWindowsHookExW(WH_KEYBOARD_LL, KeyboardHookProc, nullptr, 0);
            mouse_hook_ = SetWindowsHookExW(WH_MOUSE_LL, MouseHookProc, nullptr, 0);
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "registerHoldTriggerKeys") {
          // Args: list of [triggerKey, action, mouseButton/keyVk/keyActionMode/comboKeys, intervalMs, bgMode, hwnd, cx, cy]
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args) {
            result->Error("INVALID_ARGS", "Expected list of trigger key configs");
            return;
          }
          // Stop all existing triggers first
          EnterCriticalSection(&g_hold_trigger_cs);
          for (int i = 0; i < g_hold_trigger_count; i++) {
            StopHoldTrigger(&g_hold_triggers[i]);
            if (g_hold_triggers[i].thread) {
              WaitForSingleObject(g_hold_triggers[i].thread, 100);
              CloseHandle(g_hold_triggers[i].thread);
              g_hold_triggers[i].thread = nullptr;
            }
          }
          g_hold_trigger_count = 0;

          for (const auto& item : *args) {
            const auto* cfgPtr = std::get_if<flutter::EncodableList>(&item);
            if (!cfgPtr || cfgPtr->size() < 4 || g_hold_trigger_count >= kMaxHoldTriggers) continue;
            const auto& cfg = *cfgPtr;

            auto& entry = g_hold_triggers[g_hold_trigger_count++];
            entry.trigger_vk = 0;
            entry.is_mouse_trigger = false;
            entry.mouse_trigger_button = 0;
            entry.is_keyboard = false;
            entry.key_vk = 0;
            entry.key_action_mode = 0;
            for (int& k : entry.combo_keys) k = 0;
            entry.combo_key_count = 0;
            entry.mouse_button = 0;
            entry.interval_ms = 50;
            entry.background_mode = false;
            entry.target_hwnd = nullptr;
            entry.client_x = 0;
            entry.client_y = 0;
            entry.thread = nullptr;
            entry.stop_requested = false;
            entry.generation++;
            entry.active = false;
            const auto* triggerNamePtr = std::get_if<std::string>(&cfg[0]);
            if (triggerNamePtr) {
              entry.trigger_vk = KeyNameToVk(*triggerNamePtr);
              OutputDebugStringA(("[HoldTrigger] trigger=" + *triggerNamePtr + " vk=" + std::to_string(entry.trigger_vk) + "\n").c_str());
            }
            int actionType = GetInt(cfg[1]);
            entry.interval_ms = GetInt(cfg[2]);
            if (entry.interval_ms < 10) entry.interval_ms = 10;

            // Parse trigger type: cfg[8] = "keyboard" or "mouse", cfg[9] = mouse button (0/1/2)
            if (cfg.size() >= 10) {
              const auto* triggerTypePtr = std::get_if<std::string>(&cfg[8]);
              if (triggerTypePtr && *triggerTypePtr == "mouse") {
                entry.is_mouse_trigger = true;
                entry.mouse_trigger_button = GetInt(cfg[9]);
              }
            }

            if (actionType == 0) {
              // Mouse click
              entry.is_keyboard = false;
              entry.mouse_button = GetInt(cfg[3]);
            } else if (actionType == 1) {
              // Key repeat
              entry.is_keyboard = true;
              entry.key_action_mode = 0;
              const auto* keyNamePtr = std::get_if<std::string>(&cfg[3]);
              if (keyNamePtr) entry.key_vk = KeyNameToVk(*keyNamePtr);
            } else if (actionType == 2) {
              // Key combo
              entry.is_keyboard = true;
              entry.key_action_mode = 2;
              const auto* comboListPtr = std::get_if<flutter::EncodableList>(&cfg[3]);
              entry.combo_key_count = 0;
              if (comboListPtr) {
                for (const auto& k : *comboListPtr) {
                  if (entry.combo_key_count >= 8) break;
                  const auto* knPtr = std::get_if<std::string>(&k);
                  if (knPtr) entry.combo_keys[entry.combo_key_count++] = KeyNameToVk(*knPtr);
                }
              }
            }

            // Optional background mode params
            if (cfg.size() >= 8) {
              const auto* bgPtr = std::get_if<bool>(&cfg[4]);
              entry.background_mode = bgPtr ? *bgPtr : false;
              int64_t hwndVal = GetInt64(cfg[5]);
              entry.target_hwnd = reinterpret_cast<HWND>(static_cast<intptr_t>(hwndVal));
              entry.client_x = GetInt(cfg[6]);
              entry.client_y = GetInt(cfg[7]);
            }
          }
          LeaveCriticalSection(&g_hold_trigger_cs);

          // Install hooks if not already installed (needed for hold trigger detection)
          if (!keyboard_hook_) {
            g_flutter_window_for_hooks = this;
            keyboard_hook_ = SetWindowsHookExW(WH_KEYBOARD_LL, KeyboardHookProc, nullptr, 0);
            mouse_hook_ = SetWindowsHookExW(WH_MOUSE_LL, MouseHookProc, nullptr, 0);
          }

          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "unregisterHoldTriggerKeys") {
          EnterCriticalSection(&g_hold_trigger_cs);
          for (int i = 0; i < g_hold_trigger_count; i++) {
            StopHoldTrigger(&g_hold_triggers[i]);
            // Wait for thread and close handle
            if (g_hold_triggers[i].thread) {
              WaitForSingleObject(g_hold_triggers[i].thread, 100);
              CloseHandle(g_hold_triggers[i].thread);
              g_hold_triggers[i].thread = nullptr;
            }
          }
          g_hold_trigger_count = 0;
          LeaveCriticalSection(&g_hold_trigger_cs);

          // Uninstall hooks only when nothing else needs them
          if (!is_recording_ && g_hook_hotkey_count == 0 && !g_user_input_monitor) {
            if (keyboard_hook_) { UnhookWindowsHookEx(keyboard_hook_); keyboard_hook_ = nullptr; }
            if (mouse_hook_) { UnhookWindowsHookEx(mouse_hook_); mouse_hook_ = nullptr; }
            g_flutter_window_for_hooks = nullptr;
          }

          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "enumerateWindows") {
          // Return list of visible windows: [{hwnd, title, className}]
          flutter::EncodableList windowList;
          EnumWindows([](HWND hwnd, LPARAM lParam) -> BOOL {
            if (!IsWindowVisible(hwnd)) return TRUE;
            wchar_t title[256] = {};
            GetWindowTextW(hwnd, title, 256);
            if (title[0] == L'\0') return TRUE;
            wchar_t cls[256] = {};
            GetClassNameW(hwnd, cls, 256);
            auto* list = reinterpret_cast<flutter::EncodableList*>(lParam);
            // Convert wstring to UTF-8 string
            auto w2u = [](const std::wstring& ws) -> std::string {
              if (ws.empty()) return "";
              int len = WideCharToMultiByte(CP_UTF8, 0, ws.c_str(), (int)ws.size(), nullptr, 0, nullptr, nullptr);
              std::string s(len, 0);
              WideCharToMultiByte(CP_UTF8, 0, ws.c_str(), (int)ws.size(), &s[0], len, nullptr, nullptr);
              return s;
            };
            flutter::EncodableMap entry;
            entry[flutter::EncodableValue("hwnd")] = flutter::EncodableValue(static_cast<int64_t>(reinterpret_cast<intptr_t>(hwnd)));
            entry[flutter::EncodableValue("title")] = flutter::EncodableValue(w2u(title));
            entry[flutter::EncodableValue("className")] = flutter::EncodableValue(w2u(cls));
            list->push_back(flutter::EncodableValue(entry));
            return TRUE;
          }, reinterpret_cast<LPARAM>(&windowList));
          result->Success(flutter::EncodableValue(windowList));
        } else if (call.method_name() == "getForegroundWindow") {
          HWND fg = GetForegroundWindow();
          result->Success(flutter::EncodableValue(static_cast<int64_t>(reinterpret_cast<intptr_t>(fg))));
        } else if (call.method_name() == "setForegroundWindow") {
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 1) {
            result->Error("INVALID_ARGS", "Expected [hwnd]");
            return;
          }
          HWND hwnd = reinterpret_cast<HWND>(static_cast<intptr_t>(GetInt64(args->at(0))));
          // AllowSetForegroundWindow to bypass foreground lock
          AllowSetForegroundWindow(ASFW_ANY);
          SetForegroundWindow(hwnd);
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "switchToFloatingWindow") {
          // Batch window operations for floating mode switch — single platform call
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 1) {
            result->Error("INVALID_ARGS", "Expected [alwaysOnTop]");
            return;
          }
          const auto* aotPtr = std::get_if<bool>(&args->at(0));
          bool alwaysOnTop = aotPtr ? *aotPtr : false;
          HWND hw = GetHandle();

          // Get DPI for scaling logical pixels to physical
          UINT dpi = GetDpiForWindow(hw);
          double scale = dpi / 96.0;
          int w = static_cast<int>(280 * scale);
          int h = static_cast<int>(95 * scale);

          // Set minimum size via WM_GETMINMAXINFO handling
          // (window_manager handles this, but we set size directly)
          SetWindowPos(hw, alwaysOnTop ? HWND_TOPMOST : HWND_NOTOPMOST,
                       0, 0, w, h, SWP_NOMOVE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
          ShowWindow(hw, SW_SHOWNOACTIVATE);
          SetForegroundWindow(hw);

          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "switchToMainWindow") {
          // Batch window operations for main mode switch — single platform call
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 1) {
            result->Error("INVALID_ARGS", "Expected [alwaysOnTop]");
            return;
          }
          const auto* aotPtr = std::get_if<bool>(&args->at(0));
          bool alwaysOnTop = aotPtr ? *aotPtr : false;
          HWND hw = GetHandle();

          UINT dpi = GetDpiForWindow(hw);
          double scale = dpi / 96.0;
          int w = static_cast<int>(1080 * scale);
          int h = static_cast<int>(760 * scale);

          // Center on the monitor the window is currently on
          HMONITOR mon = MonitorFromWindow(hw, MONITOR_DEFAULTTONEAREST);
          MONITORINFO mi = { sizeof(mi) };
          GetMonitorInfoW(mon, &mi);
          int x = mi.rcWork.left + (mi.rcWork.right - mi.rcWork.left - w) / 2;
          int y = mi.rcWork.top + (mi.rcWork.bottom - mi.rcWork.top - h) / 2;

          // Remove topmost first, then reposition and optionally re-apply
          SetWindowPos(hw, HWND_NOTOPMOST, x, y, w, h, SWP_NOACTIVATE | SWP_FRAMECHANGED);
          if (alwaysOnTop) {
            SetWindowPos(hw, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
          }
          ShowWindow(hw, SW_SHOWNOACTIVATE);
          SetForegroundWindow(hw);

          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "setAlwaysOnTop") {
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 1) {
            result->Error("INVALID_ARGS", "Expected [alwaysOnTop]");
            return;
          }
          const auto* aotPtr = std::get_if<bool>(&args->at(0));
          bool alwaysOnTop = aotPtr ? *aotPtr : false;
          HWND hw = GetHandle();
          if (alwaysOnTop) {
            SetWindowPos(hw, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
          } else {
            SetWindowPos(hw, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "bringToFront") {
          HWND hw = GetHandle();
          AllowSetForegroundWindow(ASFW_ANY);
          if (IsIconic(hw)) {
            ShowWindow(hw, SW_RESTORE);
          }
          SetForegroundWindow(hw);
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "backgroundClick") {
          // Send a single background click via PostMessage
          // args = [hwnd, clientX, clientY, button, fromScreen]
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 4) {
            result->Error("INVALID_ARGS", "Expected [hwnd, clientX, clientY, button]");
            return;
          }
          HWND targetHwnd = reinterpret_cast<HWND>(static_cast<intptr_t>(GetInt64(args->at(0))));
          int clientX = GetInt(args->at(1));
          int clientY = GetInt(args->at(2));
          int button = GetInt(args->at(3));  // 0=left, 1=right, 2=middle
          int fromScreen = args->size() >= 5 ? GetInt(args->at(4)) : 0;
          if (targetHwnd && IsWindow(targetHwnd)) {
            LPARAM lp = 0;
            _prepareBackgroundTarget(targetHwnd, clientX, clientY, fromScreen, &lp, true);
            UINT msg_down = WM_LBUTTONDOWN, msg_up = WM_LBUTTONUP;
            WPARAM wp_down = MK_LBUTTON;
            if (button == 1) { msg_down = WM_RBUTTONDOWN; msg_up = WM_RBUTTONUP; wp_down = MK_RBUTTON; }
            else if (button == 2) { msg_down = WM_MBUTTONDOWN; msg_up = WM_MBUTTONUP; wp_down = MK_MBUTTON; }
            PostMessage(targetHwnd, msg_down, wp_down, lp);
            PostMessage(targetHwnd, msg_up, 0, lp);
            result->Success(flutter::EncodableValue(true));
          } else {
            result->Success(flutter::EncodableValue(false));
          }
        } else if (call.method_name() == "backgroundMouseDown") {
          // Send background mouse down via PostMessage
          // args = [hwnd, clientX, clientY, button, fromScreen]
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 4) {
            result->Error("INVALID_ARGS", "Expected [hwnd, clientX, clientY, button]");
            return;
          }
          HWND targetHwnd = reinterpret_cast<HWND>(static_cast<intptr_t>(GetInt64(args->at(0))));
          int clientX = GetInt(args->at(1));
          int clientY = GetInt(args->at(2));
          int button = GetInt(args->at(3));
          int fromScreen = args->size() >= 5 ? GetInt(args->at(4)) : 0;
          if (targetHwnd && IsWindow(targetHwnd)) {
            LPARAM lp = 0;
            _prepareBackgroundTarget(targetHwnd, clientX, clientY, fromScreen, &lp, true);
            UINT msg_down = WM_LBUTTONDOWN; WPARAM wp_down = MK_LBUTTON;
            if (button == 1) { msg_down = WM_RBUTTONDOWN; wp_down = MK_RBUTTON; }
            else if (button == 2) { msg_down = WM_MBUTTONDOWN; wp_down = MK_MBUTTON; }
            PostMessage(targetHwnd, msg_down, wp_down, lp);
            result->Success(flutter::EncodableValue(true));
          } else {
            result->Success(flutter::EncodableValue(false));
          }
        } else if (call.method_name() == "backgroundMouseUp") {
          // Send background mouse up via PostMessage
          // args = [hwnd, clientX, clientY, button, fromScreen]
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 4) {
            result->Error("INVALID_ARGS", "Expected [hwnd, clientX, clientY, button]");
            return;
          }
          HWND targetHwnd = reinterpret_cast<HWND>(static_cast<intptr_t>(GetInt64(args->at(0))));
          int clientX = GetInt(args->at(1));
          int clientY = GetInt(args->at(2));
          int button = GetInt(args->at(3));
          int fromScreen = args->size() >= 5 ? GetInt(args->at(4)) : 0;
          if (targetHwnd && IsWindow(targetHwnd)) {
            LPARAM lp = 0;
            _prepareBackgroundTarget(targetHwnd, clientX, clientY, fromScreen, &lp, false);
            UINT msg_up = WM_LBUTTONUP;
            if (button == 1) msg_up = WM_RBUTTONUP;
            else if (button == 2) msg_up = WM_MBUTTONUP;
            PostMessage(targetHwnd, msg_up, 0, lp);
            result->Success(flutter::EncodableValue(true));
          } else {
            result->Success(flutter::EncodableValue(false));
          }
        } else if (call.method_name() == "resizeFloatingWindow") {
          // Resize floating window: args = [width, height] in logical pixels
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 2) {
            result->Error("INVALID_ARGS", "Expected [width, height]");
            return;
          }
          const auto* wPtr = std::get_if<int>(&args->at(0));
          const auto* hPtr = std::get_if<int>(&args->at(1));
          if (!wPtr || !hPtr) {
            result->Error("INVALID_ARGS", "Expected int width and height");
            return;
          }
          HWND hw = GetHandle();
          UINT dpi = GetDpiForWindow(hw);
          double scale = dpi / 96.0;
          int w = static_cast<int>(*wPtr * scale);
          int h = static_cast<int>(*hPtr * scale);
          SetWindowPos(hw, nullptr, 0, 0, w, h, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "reapplyDwmFixes") {
          // Re-apply DWM frame extension after flutter_acrylic overrides it.
          HWND hw = GetHandle();
          MARGINS margins = { 0, 0, 0, 1 };
          DwmExtendFrameIntoClientArea(hw, &margins);
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "destroyWindow") {
          // Immediately destroy the window and quit the application.
          // This is faster than windowManager.destroy() which only calls PostQuitMessage.
          HWND hw = GetHandle();
          DestroyWindow(hw);
          PostQuitMessage(0);
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "maximizeWindow") {
          ShowWindow(GetHandle(), SW_MAXIMIZE);
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "unmaximizeWindow") {
          ShowWindow(GetHandle(), SW_RESTORE);
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "minimizeWindow") {
          ShowWindow(GetHandle(), SW_MINIMIZE);
          result->Success(flutter::EncodableValue(true));
        } else {
          result->NotImplemented();
        }
      });

  // -- Raw input channel ----------------------------------------------------
  raw_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.clicker.pro/rawinput",
          &flutter::StandardMethodCodec::GetInstance());
  g_raw_input_channel = raw_channel_.get();

  raw_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto* arguments = call.arguments();
        const auto* list =
            arguments ? std::get_if<flutter::EncodableList>(arguments) : nullptr;
        const bool enable =
            list != nullptr && !list->empty() &&
            std::get_if<bool>(&list->at(0)) != nullptr &&
            std::get<bool>(list->at(0));
        if (call.method_name() == "setRawInputEnabled") {
          if (enable == g_raw_input_enabled) {
            result->Success(flutter::EncodableValue(g_raw_input_enabled));
            return;
          }
          if (RegisterRawInputDevicesFor(GetHandle(), enable)) {
            g_raw_input_enabled = enable;
            result->Success(flutter::EncodableValue(enable));
          } else {
            result->Error("RAW_INPUT_FAILED", "RegisterRawInputDevices failed");
          }
        } else if (call.method_name() == "setUserInputMonitor") {
          if (enable) {
            g_flutter_window_for_hooks = this;
            if (!keyboard_hook_) {
              keyboard_hook_ =
                  SetWindowsHookExW(WH_KEYBOARD_LL, KeyboardHookProc, nullptr, 0);
            }
            if (!mouse_hook_) {
              mouse_hook_ =
                  SetWindowsHookExW(WH_MOUSE_LL, MouseHookProc, nullptr, 0);
            }
          }
          g_user_input_monitor = enable;
          GetCursorPos(&g_user_move_last);
          result->Success(flutter::EncodableValue(
              enable ? (keyboard_hook_ != nullptr && mouse_hook_ != nullptr) : true));
        } else {
          result->NotImplemented();
        }
      });

  // -- Macro recording channel ----------------------------------------------
  record_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "com.clicker.pro/record",
          &flutter::StandardMethodCodec::GetInstance());

  record_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "startRecording") {
          if (is_recording_) {
            result->Success(flutter::EncodableValue(false));
            return;
          }
          is_recording_ = true;
          record_start_tick_ = GetTickCount();
          g_flutter_window_for_hooks = this;

          // Install low-level hooks only if not already installed (e.g. by hold trigger)
          if (!keyboard_hook_) {
            keyboard_hook_ = SetWindowsHookExW(
                WH_KEYBOARD_LL, KeyboardHookProc,
                nullptr, 0);
          }
          if (!mouse_hook_) {
            mouse_hook_ = SetWindowsHookExW(
                WH_MOUSE_LL, MouseHookProc,
                nullptr, 0);
          }

          if (!keyboard_hook_ || !mouse_hook_) {
            // Clean up on failure
            if (keyboard_hook_) { UnhookWindowsHookEx(keyboard_hook_); keyboard_hook_ = nullptr; }
            if (mouse_hook_) { UnhookWindowsHookEx(mouse_hook_); mouse_hook_ = nullptr; }
            is_recording_ = false;
            g_flutter_window_for_hooks = nullptr;
            result->Error("HOOK_FAILED", "SetWindowsHookEx low-level hooks failed");
            return;
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "stopRecording") {
          is_recording_ = false;
          // Only uninstall hooks if hold trigger is not active and no hotkeys registered
          if (g_hold_trigger_count == 0 && g_hook_hotkey_count == 0 && !g_user_input_monitor) {
            if (keyboard_hook_) {
              UnhookWindowsHookEx(keyboard_hook_);
              keyboard_hook_ = nullptr;
            }
            if (mouse_hook_) {
              UnhookWindowsHookEx(mouse_hook_);
              mouse_hook_ = nullptr;
            }
            g_flutter_window_for_hooks = nullptr;
          }
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  // Remove the native title bar style and force-disable DWM window
  // transitions. Keeping WS_CAPTION re-enables the system maximize/minimize/
  // close animation, but on a Flutter window DWM waits for a synchronous
  // redraw the surface can't deliver — producing the multi-second stall
  // before the transition starts. Dropping the caption style makes window
  // state changes apply instantly (WS_THICKFRAME still allows resizing,
  // WS_MAXIMIZEBOX/WS_MINIMIZEBOX still allow maximize/minimize).
  LONG style = GetWindowLong(hwnd, GWL_STYLE);
  style &= ~(WS_CAPTION | WS_SYSMENU);
  SetWindowLong(hwnd, GWL_STYLE, style);

  BOOL disableTransitions = TRUE;
  DwmSetWindowAttribute(hwnd, DWMWA_TRANSITIONS_FORCEDISABLED, &disableTransitions, sizeof(disableTransitions));

  return true;
}

void FlutterWindow::OnDestroy() {
  // Stop fast clicker if running.
  StopFastClicker();
  // Wait for clicker thread to fully exit before destroying window
  if (clicker_thread_) {
    WaitForSingleObject(clicker_thread_, 2000);
    CloseHandle(clicker_thread_);
    clicker_thread_ = nullptr;
  }

  // Destroy overlay if active.
  DestroyOverlayWindow();

  // Destroy system tray icon.
  DestroySystemTray();

  // Stop recording if active.
  if (keyboard_hook_) {
    UnhookWindowsHookEx(keyboard_hook_);
    keyboard_hook_ = nullptr;
  }
  if (mouse_hook_) {
    UnhookWindowsHookEx(mouse_hook_);
    mouse_hook_ = nullptr;
  }
  is_recording_ = false;
  g_flutter_window_for_hooks = nullptr;

  // Unregister all hotkeys.
  for (int id : registered_hotkey_ids_) {
    UnregisterHotKey(GetHandle(), id);
  }
  registered_hotkey_ids_.clear();
  g_hook_hotkey_count = 0;
  g_hotkey_channel = nullptr;

  // Stop all hold trigger threads.
  if (g_hold_trigger_cs_initialized) {
    EnterCriticalSection(&g_hold_trigger_cs);
    for (int i = 0; i < g_hold_trigger_count; i++) {
      StopHoldTrigger(&g_hold_triggers[i]);
      if (g_hold_triggers[i].thread) {
        WaitForSingleObject(g_hold_triggers[i].thread, 200);
        CloseHandle(g_hold_triggers[i].thread);
        g_hold_triggers[i].thread = nullptr;
      }
    }
    g_hold_trigger_count = 0;
    LeaveCriticalSection(&g_hold_trigger_cs);
    DeleteCriticalSection(&g_hold_trigger_cs);
    g_hold_trigger_cs_initialized = false;
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

// -- Low-Level Keyboard Hook ------------------------------------------------

LRESULT CALLBACK FlutterWindow::KeyboardHookProc(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HC_ACTION) {
    auto* kb = reinterpret_cast<KBDLLHOOKSTRUCT*>(lparam);
    int vk = static_cast<int>(kb->vkCode);

    // Key capture mode (for UI key selection)
    if (g_capturing_key && g_capture_channel) {
      if (wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN) {
        // Convert VK code to key name string
        std::string keyName = VkToKeyName(vk);
        g_capturing_key = false;
        g_capture_channel->InvokeMethod(
            "onKeyCaptured",
            std::make_unique<flutter::EncodableValue>(keyName));
        g_capture_channel = nullptr;
        return 1; // Suppress the key
      }
    }

    // Hold trigger: detect key down/up for registered trigger keys
    // Ignore injected events (from SendInput) to prevent feedback loop
    bool key_down = (wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN);
    bool key_up = (wparam == WM_KEYUP || wparam == WM_SYSKEYUP);
    bool is_injected = (kb->flags & LLKHF_INJECTED) != 0;

    if (g_user_input_monitor && !is_injected && (key_down || key_up) &&
        g_raw_input_channel) {
      flutter::EncodableMap map;
      map[flutter::EncodableValue("kind")] = flutter::EncodableValue("keyboard");
      map[flutter::EncodableValue("vk")] = flutter::EncodableValue(vk);
      map[flutter::EncodableValue("down")] = flutter::EncodableValue(key_down);
      g_raw_input_channel->InvokeMethod(
          "onUserInput", std::make_unique<flutter::EncodableValue>(map));
    }

    // Track modifier key state for hook-based hotkeys
    if (!is_injected) {
      if (vk == VK_MENU || vk == VK_LMENU || vk == VK_RMENU) {
        if (key_down) g_hook_modifiers |= 0x0001; else g_hook_modifiers &= ~0x0001;
      } else if (vk == VK_CONTROL || vk == VK_LCONTROL || vk == VK_RCONTROL) {
        if (key_down) g_hook_modifiers |= 0x0002; else g_hook_modifiers &= ~0x0002;
      } else if (vk == VK_SHIFT || vk == VK_LSHIFT || vk == VK_RSHIFT) {
        if (key_down) g_hook_modifiers |= 0x0004; else g_hook_modifiers &= ~0x0004;
      } else if (vk == VK_LWIN || vk == VK_RWIN) {
        if (key_down) g_hook_modifiers |= 0x0008; else g_hook_modifiers &= ~0x0008;
      }
    }

    // Hook-based hotkey detection (fallback for keys RegisterHotKey couldn't grab)
    if (key_down && !is_injected && g_hook_hotkey_count > 0 && g_hotkey_channel) {
      for (int i = 0; i < g_hook_hotkey_count; i++) {
        if (g_hook_hotkeys[i].vk == vk && g_hook_hotkeys[i].modifiers == g_hook_modifiers) {
          g_hotkey_channel->InvokeMethod(
              "onHotkey",
              std::make_unique<flutter::EncodableValue>(g_hook_hotkeys[i].id));
          return 1; // Suppress the key
        }
      }
    }

    if ((key_down || key_up) && !is_injected && g_hold_trigger_count > 0) {
      EnterCriticalSection(&g_hold_trigger_cs);
      for (int i = 0; i < g_hold_trigger_count; i++) {
        if (g_hold_triggers[i].trigger_vk == vk) {
          if (key_down && !g_hold_triggers[i].active) {
            OutputDebugStringA("[HoldTrigger] KEY DOWN matched trigger, starting\n");
            StartHoldTrigger(&g_hold_triggers[i]);
          } else if (key_up && g_hold_triggers[i].active) {
            OutputDebugStringA("[HoldTrigger] KEY UP matched trigger, stopping\n");
            StopHoldTrigger(&g_hold_triggers[i]);
          }
          break;
        }
      }
      LeaveCriticalSection(&g_hold_trigger_cs);
    }

    // Macro recording
    auto* self = g_flutter_window_for_hooks;
    if (self && self->record_channel_ && self->is_recording_) {
      if (wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN ||
          wparam == WM_KEYUP || wparam == WM_SYSKEYUP) {
        DWORD elapsed = GetTickCount() - self->record_start_tick_;
        int message = static_cast<int>(wparam);
        int scan = static_cast<int>(kb->scanCode);
        int flags = static_cast<int>(kb->flags);

        flutter::EncodableMap map;
        map[flutter::EncodableValue("time")] = flutter::EncodableValue(static_cast<int>(elapsed));
        map[flutter::EncodableValue("source")] = flutter::EncodableValue("keyboard");
        map[flutter::EncodableValue("message")] = flutter::EncodableValue(message);
        map[flutter::EncodableValue("vk")] = flutter::EncodableValue(vk);
        map[flutter::EncodableValue("scan")] = flutter::EncodableValue(scan);
        map[flutter::EncodableValue("flags")] = flutter::EncodableValue(flags);

        self->record_channel_->InvokeMethod(
            "onRecordEvent",
            std::make_unique<flutter::EncodableValue>(map));
      }
    }
  }
  return CallNextHookEx(nullptr, code, wparam, lparam);
}

// -- Low-Level Mouse Hook ---------------------------------------------------

LRESULT CALLBACK FlutterWindow::MouseHookProc(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HC_ACTION && g_flutter_window_for_hooks) {
    auto* ms = reinterpret_cast<MSLLHOOKSTRUCT*>(lparam);
    auto* self = g_flutter_window_for_hooks;

    // Hold trigger: detect mouse button down/up for registered mouse triggers
    // Ignore injected events (from SendInput) to prevent feedback loop
    bool is_mouse_injected = (ms->flags & LLMHF_INJECTED) != 0;

    if (g_user_input_monitor && !is_mouse_injected && g_raw_input_channel) {
      int kind_delta = 0;
      if (wparam == WM_MOUSEMOVE) {
        if (g_self_set_pos.x == ms->pt.x && g_self_set_pos.y == ms->pt.y) {
          // 连点自己挪的鼠标不算用户输入
          g_user_move_last = ms->pt;
        } else {
          kind_delta = std::abs(static_cast<int>(ms->pt.x) - g_user_move_last.x) +
                       std::abs(static_cast<int>(ms->pt.y) - g_user_move_last.y);
          // 慢速移动累计到 4px 才算，上报后重置基准
          if (kind_delta >= 4) g_user_move_last = ms->pt;
        }
      }
      const bool button_event =
          wparam == WM_LBUTTONDOWN || wparam == WM_LBUTTONUP ||
          wparam == WM_RBUTTONDOWN || wparam == WM_RBUTTONUP ||
          wparam == WM_MBUTTONDOWN || wparam == WM_MBUTTONUP ||
          wparam == WM_XBUTTONDOWN || wparam == WM_XBUTTONUP ||
          wparam == WM_MOUSEWHEEL || wparam == WM_MOUSEHWHEEL;
      if (button_event || kind_delta >= 4) {
        flutter::EncodableMap map;
        map[flutter::EncodableValue("kind")] = flutter::EncodableValue("mouse");
        map[flutter::EncodableValue("message")] =
            flutter::EncodableValue(static_cast<int>(wparam));
        map[flutter::EncodableValue("dx")] = flutter::EncodableValue(kind_delta);
        g_raw_input_channel->InvokeMethod(
            "onUserInput", std::make_unique<flutter::EncodableValue>(map));
      }
    }
    if (g_hold_trigger_count > 0 && !is_mouse_injected &&
        (wparam == WM_LBUTTONDOWN || wparam == WM_LBUTTONUP ||
         wparam == WM_RBUTTONDOWN || wparam == WM_RBUTTONUP ||
         wparam == WM_MBUTTONDOWN || wparam == WM_MBUTTONUP)) {
      int btn = 0; // 0=left, 1=right, 2=middle
      if (wparam == WM_RBUTTONDOWN || wparam == WM_RBUTTONUP) btn = 1;
      else if (wparam == WM_MBUTTONDOWN || wparam == WM_MBUTTONUP) btn = 2;
      bool is_down = (wparam == WM_LBUTTONDOWN || wparam == WM_RBUTTONDOWN || wparam == WM_MBUTTONDOWN);

      EnterCriticalSection(&g_hold_trigger_cs);
      for (int i = 0; i < g_hold_trigger_count; i++) {
        if (g_hold_triggers[i].is_mouse_trigger && g_hold_triggers[i].mouse_trigger_button == btn) {
          if (is_down && !g_hold_triggers[i].active) {
            StartHoldTrigger(&g_hold_triggers[i]);
          } else if (!is_down && g_hold_triggers[i].active) {
            StopHoldTrigger(&g_hold_triggers[i]);
          }
          break;
        }
      }
      LeaveCriticalSection(&g_hold_trigger_cs);
    }

    if (self && self->record_channel_ && self->is_recording_) {
      // Forward mouse events: down, up, move, wheel
      if (wparam == WM_LBUTTONDOWN || wparam == WM_LBUTTONUP ||
          wparam == WM_RBUTTONDOWN || wparam == WM_RBUTTONUP ||
          wparam == WM_MBUTTONDOWN || wparam == WM_MBUTTONUP ||
          wparam == WM_XBUTTONDOWN || wparam == WM_XBUTTONUP ||
          wparam == WM_MOUSEWHEEL || wparam == WM_MOUSEHWHEEL) {
        DWORD elapsed = GetTickCount() - self->record_start_tick_;
        int message = static_cast<int>(wparam);
        int x = static_cast<int>(ms->pt.x);
        int y = static_cast<int>(ms->pt.y);
        int mouseData = static_cast<int>(ms->mouseData);
        int flags = static_cast<int>(ms->flags);

        flutter::EncodableMap map;
        map[flutter::EncodableValue("time")] = flutter::EncodableValue(static_cast<int>(elapsed));
        map[flutter::EncodableValue("source")] = flutter::EncodableValue("mouse");
        map[flutter::EncodableValue("message")] = flutter::EncodableValue(message);
        map[flutter::EncodableValue("x")] = flutter::EncodableValue(x);
        map[flutter::EncodableValue("y")] = flutter::EncodableValue(y);
        map[flutter::EncodableValue("mouseData")] = flutter::EncodableValue(mouseData);
        map[flutter::EncodableValue("flags")] = flutter::EncodableValue(flags);

        self->record_channel_->InvokeMethod(
            "onRecordEvent",
            std::make_unique<flutter::EncodableValue>(map));
      }
    }
  }
  return CallNextHookEx(nullptr, code, wparam, lparam);
}

// -- Message Handler --------------------------------------------------------

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_INPUT) {
    if (g_raw_input_enabled && raw_channel_) {
      UINT size = 0;
      auto handle = reinterpret_cast<HRAWINPUT>(lparam);
      if (GetRawInputData(handle, RID_INPUT, nullptr, &size,
                          sizeof(RAWINPUTHEADER)) == 0 &&
          size > 0 && size <= sizeof(RAWINPUT)) {
        RAWINPUT raw;
        if (GetRawInputData(handle, RID_INPUT, &raw, &size,
                            sizeof(RAWINPUTHEADER)) == size) {
          if (raw.header.dwType == RIM_TYPEMOUSE) {
            const auto& mouse = raw.data.mouse;
            if ((mouse.usFlags & MOUSE_MOVE_ABSOLUTE) == 0 &&
                (mouse.lLastX != 0 || mouse.lLastY != 0)) {
              flutter::EncodableMap map;
              map[flutter::EncodableValue("dx")] =
                  flutter::EncodableValue(static_cast<int>(mouse.lLastX));
              map[flutter::EncodableValue("dy")] =
                  flutter::EncodableValue(static_cast<int>(mouse.lLastY));
              map[flutter::EncodableValue("buttons")] =
                  flutter::EncodableValue(static_cast<int>(mouse.usButtonFlags));
              raw_channel_->InvokeMethod(
                  "onRawMouseMove",
                  std::make_unique<flutter::EncodableValue>(map));
            }
          } else if (raw.header.dwType == RIM_TYPEKEYBOARD) {
            const auto& keyboard = raw.data.keyboard;
            if (keyboard.VKey != 255) {
              flutter::EncodableMap map;
              map[flutter::EncodableValue("vk")] =
                  flutter::EncodableValue(static_cast<int>(keyboard.VKey));
              map[flutter::EncodableValue("down")] = flutter::EncodableValue(
                  (keyboard.Flags & RI_KEY_BREAK) == 0);
              map[flutter::EncodableValue("scan")] =
                  flutter::EncodableValue(static_cast<int>(keyboard.MakeCode));
              raw_channel_->InvokeMethod(
                  "onRawKey", std::make_unique<flutter::EncodableValue>(map));
            }
          }
        }
      }
    }
  }

  if (message == WM_DROPFILES) {
    HDROP drop = reinterpret_cast<HDROP>(wparam);
    const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
    flutter::EncodableList paths;
    for (UINT i = 0; i < count; ++i) {
      const UINT len = DragQueryFileW(drop, i, nullptr, 0);
      if (len == 0) continue;
      std::wstring buf(len + 1, L'\0');
      DragQueryFileW(drop, i, buf.data(), len + 1);
      buf.resize(len);
      paths.push_back(flutter::EncodableValue(_wideToUtf8(buf)));
    }
    DragFinish(drop);
    if (!paths.empty() && platform_channel_) {
      platform_channel_->InvokeMethod(
          "onFilesDropped",
          std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
              {flutter::EncodableValue("paths"), flutter::EncodableValue(paths)},
          }));
    }
    return 0;
  }

  // Handle system-level hotkey messages.
  if (message == WM_HOTKEY) {
    int id = static_cast<int>(wparam);

    if ((id == 1 || id == 3) && g_clicker.running) {
      StopFastClicker();
    }

    if (hotkey_channel_) {
      hotkey_channel_->InvokeMethod(
          "onHotkey",
          std::make_unique<flutter::EncodableValue>(id));
    }
    return 0;
  }

  // Handle system tray callback messages.
  if (tray_callback_msg_ != 0 && message == tray_callback_msg_) {
    switch (LOWORD(lparam)) {
      case WM_LBUTTONUP: {
        if (platform_channel_) {
          platform_channel_->InvokeMethod("onTrayIconClick", nullptr);
        }
        break;
      }
      case WM_RBUTTONUP: {
        ShowTrayMenu();
        break;
      }
    }
    return 0;
  }

  if (clicker_stopped_msg_ != 0 && message == clicker_stopped_msg_) {
    // wparam = 发出退出消息的线程的 generation。
    // 只有当前代线程退出才通知 Dart —— 防止「停止后立即重启」时
    // 旧线程的退出消息带新代数误杀新会话（UI 显示停止但新线程还在点）。
    uint64_t threadGen = (uint64_t)wparam;
    if (threadGen == g_clicker.generation && platform_channel_) {
      platform_channel_->InvokeMethod("onFastClickerStopped",
        std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
          {flutter::EncodableValue("count"), flutter::EncodableValue(g_clicker.click_count)},
          {flutter::EncodableValue("generation"), flutter::EncodableValue(g_clicker.dart_generation)},
        }));
    }
    return 0;
  }

  if (g_elem_result_msg != 0 && message == g_elem_result_msg) {
    int id = (int)wparam;
    ElementDumpResult data;
    {
      std::lock_guard<std::mutex> lock(g_elem_mutex);
      auto it = g_elem_results.find(id);
      if (it == g_elem_results.end()) return 0;
      data = std::move(it->second);
      g_elem_results.erase(it);
    }
    if (!data.error.empty()) {
      data.result_ptr->Error("UIA_FAILED", data.error);
      return 0;
    }
    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("elements")] = flutter::EncodableValue(data.elements);
    payload[flutter::EncodableValue("count")] = flutter::EncodableValue(static_cast<int>(data.elements.size()));
    payload[flutter::EncodableValue("truncated")] = flutter::EncodableValue(data.truncated);
    data.result_ptr->Success(flutter::EncodableValue(payload));
    return 0;
  }

  if (g_findimage_result_msg != 0 && message == g_findimage_result_msg) {
    int id = (int)wparam;
    FindImageResultData data;
    {
      std::lock_guard<std::mutex> lock(g_findimage_mutex);
      auto it = g_findimage_results.find(id);
      if (it == g_findimage_results.end()) return 0;
      data = it->second;
      g_findimage_results.erase(it);
    }
    flutter::EncodableList matches;
    for (const auto& box : data.matches) {
      flutter::EncodableMap m;
      m[flutter::EncodableValue("x")] = flutter::EncodableValue(box.x);
      m[flutter::EncodableValue("y")] = flutter::EncodableValue(box.y);
      m[flutter::EncodableValue("width")] = flutter::EncodableValue(box.w);
      m[flutter::EncodableValue("height")] = flutter::EncodableValue(box.h);
      m[flutter::EncodableValue("score")] = flutter::EncodableValue(box.score);
      m[flutter::EncodableValue("matched")] = flutter::EncodableValue(true);
      matches.push_back(flutter::EncodableValue(m));
    }
    flutter::EncodableMap meta;
    meta[flutter::EncodableValue("best_score")] = flutter::EncodableValue(data.bestScore);
    matches.push_back(flutter::EncodableValue(meta));
    OutputDebugStringA(("[findImage] main thread callback: matches=" + std::to_string(data.matches.size()) + "\n").c_str());
    data.result_ptr->Success(flutter::EncodableValue(matches));
    delete data.result_ptr;
    return 0;
  }

  if (g_perform_click_msg != 0 && message == g_perform_click_msg) {
    int click_type = (int)(wparam >> 16);
    // hold 模式的 press/release 必须无条件执行 ——
    // release 若被 running 守卫丢弃，按键会永远卡住不松开
    if (click_type == 3) {
      BYTE vk = (BYTE)(wparam & 0xFF);
      keybd_event(vk, 0, 0, 0);
      return 0;
    }
    if (click_type == 4) {
      BYTE vk = (BYTE)(wparam & 0xFF);
      keybd_event(vk, 0, KEYEVENTF_KEYUP, 0);
      return 0;
    }
    if (!g_clicker.running) return 0;
    if (click_type == 0) {
      DWORD flags_down = (DWORD)(wparam & 0xFFFF);
      DWORD flags_up = (DWORD)lparam;
      // Game-friendly injection (raw-input games ignore bare mouse_event).
      POINT pt;
      if (GetCursorPos(&pt)) {
        LONG dx = (LONG)(pt.x * 65535.0 / (GetSystemMetrics(SM_CXSCREEN) - 1));
        LONG dy = (LONG)(pt.y * 65535.0 / (GetSystemMetrics(SM_CYSCREEN) - 1));
        INPUT inputs[2] = {};
        inputs[0].type = INPUT_MOUSE;
        inputs[0].mi.dx = dx;
        inputs[0].mi.dy = dy;
        inputs[0].mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_MOVE | flags_down;
        inputs[1].type = INPUT_MOUSE;
        inputs[1].mi.dx = dx;
        inputs[1].mi.dy = dy;
        inputs[1].mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_MOVE | flags_up;
        SendInput(2, inputs, sizeof(INPUT));
      } else {
        mouse_event(flags_down, 0, 0, 0, 0);
        mouse_event(flags_up, 0, 0, 0, 0);
      }
    } else if (click_type == 1) {
      BYTE vk = (BYTE)(wparam & 0xFF);
      keybd_event(vk, 0, 0, 0);
      keybd_event(vk, 0, KEYEVENTF_KEYUP, 0);
    } else if (click_type == 2) {
      int n = (int)(wparam & 0xFF);
      BYTE vks[8];
      for (int i = 0; i < n && i < 8; i++) {
        vks[i] = (BYTE)((lparam >> (i * 8)) & 0xFF);
      }
      for (int i = 0; i < n; i++) keybd_event(vks[i], 0, 0, 0);
      for (int i = 0; i < n; i++) keybd_event(vks[i], 0, KEYEVENTF_KEYUP, 0);
    }
    return 0;
  }

  // Handle tray menu commands
  if (message == WM_COMMAND && HIWORD(wparam) == 0) {
    int cmdId = LOWORD(wparam);
    if (cmdId == 1001 && platform_channel_) {
      // Show main window
      platform_channel_->InvokeMethod("onTrayShowMain", nullptr);
    } else if (cmdId == 1002 && platform_channel_) {
      // Show floating window
      platform_channel_->InvokeMethod("onTrayFloating", nullptr);
    } else if (cmdId == 1003 && platform_channel_) {
      // Exit
      platform_channel_->InvokeMethod("onTrayExit", nullptr);
    }
    return 0;
  }

  // Remove native title bar: handle WM_NCCALCSIZE to expand client area
  // and prevent native caption buttons from being drawn.
  if (message == WM_NCCALCSIZE && wparam == TRUE) {
    return 0;
  }

  // Prevent the system from redrawing the non-client area when the window
  // activation state changes (focus in/out). Without this, Windows draws
  // a white active/inactive border on every focus change.
  if (message == WM_NCACTIVATE) {
    return TRUE;
  }

  // Prevent background erase to avoid white flash during window state changes.
  if (message == WM_ERASEBKGND) {
    return 1;
  }

  // Handle WM_NCHITTEST to control hit-testing for custom title bar.
  // Return HTCLIENT for the top area to prevent native caption buttons.
  // The Flutter-side custom title bar handles its own drag and buttons.

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

// -- System Tray Implementation ---------------------------------------------

void FlutterWindow::InitSystemTray() {
  if (tray_icon_created_) return;

  // Register a custom window message for tray callbacks
  tray_callback_msg_ = RegisterWindowMessageW(L"ClickerTrayCallback");

  // Load app icon from resource (reliable in both debug and release)
  HICON appIcon = LoadIconW(GetModuleHandle(nullptr), MAKEINTRESOURCEW(101));
  if (!appIcon) {
    // Fallback: create a simple colored circle icon programmatically
    int iconSize = GetSystemMetrics(SM_CXSMICON);
    HDC screenDC = GetDC(nullptr);
    HDC memDC = CreateCompatibleDC(screenDC);

    // Color bitmap
    HBITMAP hColorBmp = CreateCompatibleBitmap(screenDC, iconSize, iconSize);
    HBITMAP hOldColor = (HBITMAP)SelectObject(memDC, hColorBmp);

    HBRUSH bgBrush = CreateSolidBrush(RGB(30, 30, 60));
    RECT rc = {0, 0, iconSize, iconSize};
    FillRect(memDC, &rc, bgBrush);
    DeleteObject(bgBrush);

    HBRUSH circleBrush = CreateSolidBrush(RGB(80, 140, 255));
    HPEN hPen = CreatePen(PS_SOLID, 1, RGB(80, 140, 255));
    HPEN hOldPen = (HPEN)SelectObject(memDC, hPen);
    SelectObject(memDC, circleBrush);
    int margin = iconSize / 6;
    Ellipse(memDC, margin, margin, iconSize - margin, iconSize - margin);
    SelectObject(memDC, hOldPen);
    DeleteObject(hPen);
    DeleteObject(circleBrush);
    SelectObject(memDC, hOldColor);

    // Mask bitmap — black = opaque, white = transparent
    // Draw circle as opaque, background as transparent
    HDC maskDC = CreateCompatibleDC(nullptr);
    HBITMAP hMaskBmp = CreateBitmap(iconSize, iconSize, 1, 1, nullptr);
    HBITMAP hOldMask = (HBITMAP)SelectObject(maskDC, hMaskBmp);
    // Start all white (transparent)
    PatBlt(maskDC, 0, 0, iconSize, iconSize, WHITENESS);
    // Draw black circle (opaque area)
    HBRUSH blackBrush = (HBRUSH)GetStockObject(BLACK_BRUSH);
    HPEN blackPen = CreatePen(PS_SOLID, 1, RGB(0, 0, 0));
    HPEN oldMaskPen = (HPEN)SelectObject(maskDC, blackPen);
    SelectObject(maskDC, blackBrush);
    Ellipse(maskDC, margin, margin, iconSize - margin, iconSize - margin);
    SelectObject(maskDC, oldMaskPen);
    DeleteObject(blackPen);
    SelectObject(maskDC, hOldMask);

    DeleteDC(maskDC);
    DeleteDC(memDC);
    ReleaseDC(nullptr, screenDC);

    ICONINFO ii = {};
    ii.fIcon = TRUE;
    ii.hbmMask = hMaskBmp;
    ii.hbmColor = hColorBmp;
    appIcon = CreateIconIndirect(&ii);

    DeleteObject(hColorBmp);
    DeleteObject(hMaskBmp);
  }

  // Setup NOTIFYICONDATA
  ZeroMemory(&tray_icon_data_, sizeof(tray_icon_data_));
  tray_icon_data_.cbSize = sizeof(NOTIFYICONDATAW);
  tray_icon_data_.hWnd = GetHandle();
  tray_icon_data_.uID = 1;
  tray_icon_data_.uFlags = NIF_ICON | NIF_TIP | NIF_MESSAGE;
  tray_icon_data_.uCallbackMessage = tray_callback_msg_;
  tray_icon_data_.hIcon = appIcon;
  wcscpy_s(tray_icon_data_.szTip, L"Clicker");

  Shell_NotifyIconW(NIM_ADD, &tray_icon_data_);
  tray_icon_created_ = true;

  // Create context menu
  tray_menu_ = CreatePopupMenu();
  AppendMenuW(tray_menu_, MF_STRING, 1001, L"\x663E\x793A\x4E3B\x7A97\x53E3");  // Show Main Window
  AppendMenuW(tray_menu_, MF_STRING, 1002, L"\x60AC\x6D6E\x7A97");               // Floating Window
  AppendMenuW(tray_menu_, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(tray_menu_, MF_STRING, 1003, L"\x9000\x51FA");                       // Exit
}

void FlutterWindow::DestroySystemTray() {
  if (tray_icon_created_) {
    Shell_NotifyIconW(NIM_DELETE, &tray_icon_data_);
    if (tray_icon_data_.hIcon) {
      DestroyIcon(tray_icon_data_.hIcon);
      tray_icon_data_.hIcon = nullptr;
    }
    tray_icon_created_ = false;
  }
  if (tray_menu_) {
    DestroyMenu(tray_menu_);
    tray_menu_ = nullptr;
  }
}

void FlutterWindow::ShowSystemTray() {
  if (tray_icon_created_) {
    Shell_NotifyIconW(NIM_ADD, &tray_icon_data_);
  }
}

void FlutterWindow::HideSystemTray() {
  if (tray_icon_created_) {
    Shell_NotifyIconW(NIM_DELETE, &tray_icon_data_);
  }
}

void FlutterWindow::ShowTrayMenu() {
  POINT pt;
  GetCursorPos(&pt);
  // Need to set foreground window for menu to dismiss properly
  SetForegroundWindow(GetHandle());
  TrackPopupMenu(tray_menu_, TPM_BOTTOMALIGN | TPM_LEFTALIGN,
                 pt.x, pt.y, 0, GetHandle(), nullptr);
  // Required for menu to dismiss when clicking outside
  PostMessage(GetHandle(), WM_NULL, 0, 0);
}

// ─── Fast Clicker (Native Thread) ────────────────────────────────────────
//
// Design:
// - Uses a generation counter to invalidate old threads without blocking.
// - StopFastClicker never blocks the platform thread (no WaitForSingleObject,
//   no timeKillEvent with TIME_KILL_SYNCHRONOUS).
// - Simple Sleep loop with timeBeginPeriod(1) for 1ms precision.
// - Minimum interval: 1ms. Sub-ms is physically impossible with SendInput.
// Note: g_clicker struct is defined earlier in the file (before MessageHandler).

static void SendOneClick() {
  // 前台输入直接在本线程调用 mouse_event/keybd_event（线程安全 API）。
  // 不再 PostMessage 到 UI 线程 —— 旧路径受 Flutter 消息循环吞吐限制，
  // UI 繁忙时点击延迟/丢失。
  if (g_clicker.is_keyboard) {
    if (g_clicker.key_action_mode == 0) {
      keybd_event(static_cast<BYTE>(g_clicker.key_vk), 0, 0, 0);
      keybd_event(static_cast<BYTE>(g_clicker.key_vk), 0, KEYEVENTF_KEYUP, 0);
    } else if (g_clicker.key_action_mode == 2) {
      int n = g_clicker.combo_key_count;
      if (n > 8) n = 8;
      for (int i = 0; i < n; i++) {
        keybd_event(static_cast<BYTE>(g_clicker.combo_keys[i]), 0, 0, 0);
      }
      for (int i = 0; i < n; i++) {
        keybd_event(static_cast<BYTE>(g_clicker.combo_keys[i]), 0, KEYEVENTF_KEYUP, 0);
      }
    }
    g_clicker.click_count++;
    return;
  }

  if (g_clicker.background_mode && g_clicker.target_hwnd) {
    // Scroll buttons not supported in background mode
    if (g_clicker.button >= 5) {
      g_clicker.click_count++;
      return;
    }
    LPARAM lp = MAKELPARAM(static_cast<WORD>(g_clicker.client_x),
                            static_cast<WORD>(g_clicker.client_y));
    WPARAM wp = MK_LBUTTON;
    UINT msg_down = WM_LBUTTONDOWN;
    UINT msg_up = WM_LBUTTONUP;
    if (g_clicker.button == 1) {
      msg_down = WM_RBUTTONDOWN; msg_up = WM_RBUTTONUP;
    } else if (g_clicker.button == 2) {
      msg_down = WM_MBUTTONDOWN; msg_up = WM_MBUTTONUP;
    } else if (g_clicker.button == 3 || g_clicker.button == 4) {
      // X buttons (side buttons) — use WM_XBUTTONDOWN/UP
      msg_down = WM_XBUTTONDOWN; msg_up = WM_XBUTTONUP;
      wp = MAKELPARAM((g_clicker.button == 4) ? XBUTTON2 : XBUTTON1, 0);
    }
    PostMessage(g_clicker.target_hwnd, msg_down, wp, lp);
    PostMessage(g_clicker.target_hwnd, msg_up, 0, lp);
    g_clicker.click_count++;
    return;
  }

  {
    if (g_clicker.x >= 0 && g_clicker.y >= 0) {
      g_self_set_pos.x = g_clicker.x;
      g_self_set_pos.y = g_clicker.y;
      SetCursorPos(g_clicker.x, g_clicker.y);
    }

    // Handle scroll buttons
    if (g_clicker.button == 5 || g_clicker.button == 6) {
      // 5 = scrollUp, 6 = scrollDown
      int delta = (g_clicker.button == 5) ? 120 : -120;
      mouse_event(MOUSEEVENTF_WHEEL, 0, 0, (DWORD)delta, 0);
      g_clicker.click_count++;
      return;
    }

    DWORD flags_down = MOUSEEVENTF_LEFTDOWN;
    DWORD flags_up = MOUSEEVENTF_LEFTUP;
    DWORD mouse_data = 0;
    if (g_clicker.button == 1) { flags_down = MOUSEEVENTF_RIGHTDOWN; flags_up = MOUSEEVENTF_RIGHTUP; }
    else if (g_clicker.button == 2) { flags_down = MOUSEEVENTF_MIDDLEDOWN; flags_up = MOUSEEVENTF_MIDDLEUP; }
    else if (g_clicker.button == 3) { flags_down = MOUSEEVENTF_XDOWN; flags_up = MOUSEEVENTF_XUP; mouse_data = XBUTTON1; }
    else if (g_clicker.button == 4) { flags_down = MOUSEEVENTF_XDOWN; flags_up = MOUSEEVENTF_XUP; mouse_data = XBUTTON2; }

    // Use SendInput with an explicit absolute move (same as the macro player's
    // "sendClick"). Fullscreen / borderless games that read raw input ignore
    // SetCursorPos + bare mouse_event, but accept MOUSEEVENTF_ABSOLUTE|MOVE.
    int cx = g_clicker.x;
    int cy = g_clicker.y;
    if (cx < 0 || cy < 0) {
      POINT pt;
      if (GetCursorPos(&pt)) { cx = pt.x; cy = pt.y; }
    }
    LONG dx = (LONG)(cx * 65535.0 / (GetSystemMetrics(SM_CXSCREEN) - 1));
    LONG dy = (LONG)(cy * 65535.0 / (GetSystemMetrics(SM_CYSCREEN) - 1));

    INPUT inputs[2] = {};
    inputs[0].type = INPUT_MOUSE;
    inputs[0].mi.dx = dx;
    inputs[0].mi.dy = dy;
    inputs[0].mi.mouseData = mouse_data;
    inputs[0].mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_MOVE | flags_down;
    inputs[1].type = INPUT_MOUSE;
    inputs[1].mi.dx = dx;
    inputs[1].mi.dy = dy;
    inputs[1].mi.mouseData = mouse_data;
    inputs[1].mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_MOVE | flags_up;
    SendInput(2, inputs, sizeof(INPUT));
  }

  g_clicker.click_count++;
}

static bool IsCurrentGeneration(uint64_t gen) {
  return g_clicker.generation == gen;
}

static DWORD WINAPI ClickerThreadFunc(LPVOID param) {
  uint64_t my_generation = g_clicker.generation;
  SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST);

  // Request 1ms timer resolution from the OS.
  // Without this, Sleep(1) actually sleeps ~15ms.
  timeBeginPeriod(1);

  // 高精度等待：waitable timer（100ns 单位，Win10 1803+ 高分辨率模式）。
  // 同时监听 stop 事件 —— stop 请求在微秒级唤醒线程，不再等睡满间隔。
#ifndef CREATE_WAITABLE_TIMER_HIGH_RESOLUTION
#define CREATE_WAITABLE_TIMER_HIGH_RESOLUTION 0x00000002
#endif
  HANDLE timer = CreateWaitableTimerExW(nullptr, nullptr,
      CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
  if (!timer) {
    timer = CreateWaitableTimerExW(nullptr, nullptr, 0, TIMER_ALL_ACCESS);
  }

  // 等待一个点击间隔。返回 false 表示被 stop 事件打断（应立即退出）。
  auto waitInterval = [&]() -> bool {
    if (timer && g_clicker_stop_event) {
      LARGE_INTEGER due;
      due.QuadPart = -(LONGLONG)g_clicker.interval_us * 10;  // 100ns 单位，负值 = 相对
      SetWaitableTimer(timer, &due, 0, nullptr, nullptr, FALSE);
      HANDLE handles[2] = { timer, g_clicker_stop_event };
      DWORD wr = WaitForMultipleObjects(2, handles, FALSE, INFINITE);
      return wr != (WAIT_OBJECT_0 + 1);
    }
    // 回退路径：分段 Sleep（2ms 一段），每段检查 stop
    int64_t remain = g_clicker.interval_us;
    while (remain > 0) {
      if (g_clicker.stop_requested) return false;
      int64_t chunk = remain > 2000 ? 2000 : remain;
      Sleep(static_cast<DWORD>((chunk + 999) / 1000));
      remain -= chunk;
    }
    return !g_clicker.stop_requested;
  };

  // Keyboard hold mode: press key once, wait for stop, then release
  if (g_clicker.is_keyboard && g_clicker.key_action_mode == 1) {
    keybd_event(static_cast<BYTE>(g_clicker.key_vk), 0, 0, 0);
    g_clicker.click_count++;

    while (IsCurrentGeneration(my_generation) && !g_clicker.stop_requested) {
      if (!waitInterval()) break;
    }

    keybd_event(static_cast<BYTE>(g_clicker.key_vk), 0, KEYEVENTF_KEYUP, 0);
  } else {
    // Normal repeat/combo/mouse mode
    while (IsCurrentGeneration(my_generation) && !g_clicker.stop_requested) {
      if (g_clicker.target_count > 0 && g_clicker.click_count >= g_clicker.target_count) {
        g_clicker.stop_requested = true;
        break;
      }
      SendOneClick();
      if (!waitInterval()) break;
    }
  }

  if (timer) CloseHandle(timer);
  timeEndPeriod(1);

  g_clicker.running = false;

  // 退出通知带线程自己的 generation —— UI 线程只认当前代，
  // 防止「停止后立即重启」时旧线程的退出消息误杀新会话。
  if (IsCurrentGeneration(my_generation) && g_clicker.self_hwnd && g_clicker_stopped_msg) {
    PostMessage(g_clicker.self_hwnd, g_clicker_stopped_msg,
                (WPARAM)my_generation, 0);
  }

  return 0;
}

void FlutterWindow::StartFastClicker(int intervalUs, int x, int y, int button, int targetCount,
    bool bgMode, HWND targetHwnd, int clientX, int clientY,
    bool isKeyboard, int keyVk, int keyActionMode,
    const std::vector<int>& comboKeys) {
  if (!g_clicker_stop_event) {
    g_clicker_stop_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  }

  g_clicker.generation++;
  g_clicker.stop_requested = true;
  g_clicker.running = false;
  // 唤醒睡眠中的老线程（waitable timer 等待被事件打断）
  if (g_clicker_stop_event) SetEvent(g_clicker_stop_event);

  if (clicker_thread_) {
    // 老线程已被 stop 事件唤醒，通常微秒级退出；上限 2s 兜底
    WaitForSingleObject(clicker_thread_, 2000);
    CloseHandle(clicker_thread_);
    clicker_thread_ = nullptr;
  }
  if (g_clicker_stop_event) ResetEvent(g_clicker_stop_event);

  // Set up new clicker state
  // 间隔以微秒精度保留；下限 1ms（更快的物理间隔对 SendInput 无意义）
  int interval_us = intervalUs;
  if (interval_us < 1000) interval_us = 1000;

  g_clicker.interval_us = interval_us;
  g_clicker.x = x;
  g_clicker.y = y;
  g_clicker.button = button;
  g_clicker.click_count = 0;
  g_clicker.target_count = targetCount;
  g_clicker.stop_requested = false;
  g_clicker.running = true;
  g_clicker.channel = platform_channel_.get();
  g_clicker.background_mode = bgMode;
  g_clicker.target_hwnd = targetHwnd;
  g_clicker.client_x = clientX;
  g_clicker.client_y = clientY;
  g_clicker.self_hwnd = GetHandle();
  // Keyboard mode
  g_clicker.is_keyboard = isKeyboard;
  g_clicker.key_vk = keyVk;
  g_clicker.key_action_mode = keyActionMode;
  g_clicker.combo_key_count = 0;
  for (int i = 0; i < (int)comboKeys.size() && i < 8; i++) {
    g_clicker.combo_keys[i] = comboKeys[i];
    g_clicker.combo_key_count++;
  }

  // Bump generation for the new thread
  g_clicker.generation++;

  clicker_thread_ = CreateThread(nullptr, 0, ClickerThreadFunc, this, 0, nullptr);
  if (!clicker_thread_) {
    g_clicker.running = false;
    g_clicker.stop_requested = true;
    OutputDebugStringA("[StartFastClicker] CreateThread FAILED!");
  }
  clicker_running_ = (clicker_thread_ != nullptr);
}

void FlutterWindow::StopFastClicker() {
  g_clicker.stop_requested = true;
  g_clicker.running = false;
  clicker_running_ = false;
  // 立即唤醒睡眠中的点击线程 —— stop 毫秒级生效
  if (g_clicker_stop_event) SetEvent(g_clicker_stop_event);
}

#pragma warning(disable: 4819)
#include "flutter_window.h"

#include <dwmapi.h>
#include <mmsystem.h>
#include <optional>
#include <algorithm>
#include <vector>

#pragma comment(lib, "winmm.lib")
#pragma comment(lib, "dwmapi.lib")

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
      INPUT inputs[2] = {};
      inputs[0].type = INPUT_KEYBOARD;
      inputs[0].ki.wVk = static_cast<WORD>(entry->key_vk);
      inputs[1].type = INPUT_KEYBOARD;
      inputs[1].ki.wVk = static_cast<WORD>(entry->key_vk);
      inputs[1].ki.dwFlags = KEYEVENTF_KEYUP;
      SendInput(2, inputs, sizeof(INPUT));
    } else if (entry->key_action_mode == 2) {
      int n = entry->combo_key_count;
      if (n > 8) n = 8;
      INPUT inputs[16] = {};
      for (int i = 0; i < n; i++) {
        inputs[i].type = INPUT_KEYBOARD;
        inputs[i].ki.wVk = static_cast<WORD>(entry->combo_keys[i]);
      }
      for (int i = 0; i < n; i++) {
        inputs[n + i].type = INPUT_KEYBOARD;
        inputs[n + i].ki.wVk = static_cast<WORD>(entry->combo_keys[i]);
        inputs[n + i].ki.dwFlags = KEYEVENTF_KEYUP;
      }
      SendInput(n * 2, inputs, sizeof(INPUT));
    }
  } else {
    if (entry->background_mode && entry->target_hwnd) {
      LPARAM lp = MAKELPARAM(static_cast<WORD>(entry->client_x),
                              static_cast<WORD>(entry->client_y));
      UINT msg_down = WM_LBUTTONDOWN, msg_up = WM_LBUTTONUP;
      if (entry->mouse_button == 1) { msg_down = WM_RBUTTONDOWN; msg_up = WM_RBUTTONUP; }
      else if (entry->mouse_button == 2) { msg_down = WM_MBUTTONDOWN; msg_up = WM_MBUTTONUP; }
      PostMessage(entry->target_hwnd, msg_down, MK_LBUTTON, lp);
      PostMessage(entry->target_hwnd, msg_up, 0, lp);
    } else {
      INPUT inputs[2] = {};
      DWORD flags_down = MOUSEEVENTF_LEFTDOWN, flags_up = MOUSEEVENTF_LEFTUP;
      if (entry->mouse_button == 1) { flags_down = MOUSEEVENTF_RIGHTDOWN; flags_up = MOUSEEVENTF_RIGHTUP; }
      else if (entry->mouse_button == 2) { flags_down = MOUSEEVENTF_MIDDLEDOWN; flags_up = MOUSEEVENTF_MIDDLEUP; }
      inputs[0].type = INPUT_MOUSE;
      inputs[0].mi.dwFlags = flags_down;
      inputs[1].type = INPUT_MOUSE;
      inputs[1].mi.dwFlags = flags_up;
      SendInput(2, inputs, sizeof(INPUT));
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

// -- Overlay Window Implementation -------------------------------------------

OverlayState g_overlay;
static const COLORREF OVERLAY_BG_COLOR = RGB(255, 0, 255); // Magenta = transparent via color key
static const COLORREF CROSSHAIR_COLOR = RGB(255, 60, 60);
static const COLORREF RECT_COLOR = RGB(0, 180, 255);
static const wchar_t kOverlayClassName[] = L"ClickerOverlayWnd";
static const int OVERLAY_TIMER_ID = 1;
static const int OVERLAY_FPS = 30;

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
  // Fill background with magenta (transparent via color key)
  HBRUSH bgBrush = CreateSolidBrush(OVERLAY_BG_COLOR);
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

  if (g_overlay.mode == OverlayMode::Crosshair) {
    // Draw crosshair lines
    HPEN hPen = CreatePen(PS_SOLID, 1, CROSSHAIR_COLOR);
    HPEN hOldPen = (HPEN)SelectObject(hdc, hPen);
    MoveToEx(hdc, 0, pt.y, nullptr);
    LineTo(hdc, w, pt.y);
    MoveToEx(hdc, pt.x, 0, nullptr);
    LineTo(hdc, pt.x, h);
    SelectObject(hdc, hOldPen);
    DeleteObject(hPen);

    // Draw small center circle
    HBRUSH circleBrush = CreateSolidBrush(CROSSHAIR_COLOR);
    HBRUSH oldBrush = (HBRUSH)SelectObject(hdc, circleBrush);
    HPEN oldPen2 = (HPEN)SelectObject(hdc, GetStockObject(NULL_PEN));
    Ellipse(hdc, pt.x - 6, pt.y - 6, pt.x + 6, pt.y + 6);
    SelectObject(hdc, oldPen2);
    SelectObject(hdc, oldBrush);
    DeleteObject(circleBrush);

    // Draw coordinate text near cursor
    SetBkColor(hdc, OVERLAY_BG_COLOR);
    SetTextColor(hdc, CROSSHAIR_COLOR);
    wchar_t coordText[64];
    swprintf_s(coordText, L"(%d, %d)", pt.x, pt.y);
    TextOutW(hdc, pt.x + 12, pt.y + 12, coordText, (int)wcslen(coordText));

  } else if (g_overlay.mode == OverlayMode::WindowPick) {
    // Draw crosshair relative to the overlay (which covers the target window)
    HPEN hPen = CreatePen(PS_SOLID, 1, CROSSHAIR_COLOR);
    HPEN hOldPen = (HPEN)SelectObject(hdc, hPen);
    MoveToEx(hdc, 0, pt.y, nullptr);
    LineTo(hdc, w, pt.y);
    MoveToEx(hdc, pt.x, 0, nullptr);
    LineTo(hdc, pt.x, h);
    SelectObject(hdc, hOldPen);
    DeleteObject(hPen);

    // Draw center circle
    HBRUSH circleBrush = CreateSolidBrush(CROSSHAIR_COLOR);
    HBRUSH oldBrush = (HBRUSH)SelectObject(hdc, circleBrush);
    HPEN oldPen2 = (HPEN)SelectObject(hdc, GetStockObject(NULL_PEN));
    Ellipse(hdc, pt.x - 6, pt.y - 6, pt.x + 6, pt.y + 6);
    SelectObject(hdc, oldPen2);
    SelectObject(hdc, oldBrush);
    DeleteObject(circleBrush);

    // Draw client-area coordinates
    SetBkColor(hdc, OVERLAY_BG_COLOR);
    SetTextColor(hdc, CROSSHAIR_COLOR);
    wchar_t coordText[64];
    swprintf_s(coordText, L"(%d, %d)", pt.x, pt.y);
    TextOutW(hdc, pt.x + 12, pt.y + 12, coordText, (int)wcslen(coordText));

    // Draw hint text
    SetTextColor(hdc, RGB(255, 255, 255));
    TextOutW(hdc, 8, 8, L"Click to pick coordinates (ESC to cancel)", 41);

  } else if (g_overlay.mode == OverlayMode::AreaSelect) {
    if (g_overlay.dragging) {
      HPEN hPen = CreatePen(PS_SOLID, 2, RECT_COLOR);
      HBRUSH hOldBrush = (HBRUSH)SelectObject(hdc, GetStockObject(NULL_BRUSH));
      HPEN hOldPen = (HPEN)SelectObject(hdc, hPen);

      int x1 = g_overlay.dragStart.x < g_overlay.dragCurrent.x ? g_overlay.dragStart.x : g_overlay.dragCurrent.x;
      int y1 = g_overlay.dragStart.y < g_overlay.dragCurrent.y ? g_overlay.dragStart.y : g_overlay.dragCurrent.y;
      int x2 = g_overlay.dragStart.x < g_overlay.dragCurrent.x ? g_overlay.dragCurrent.x : g_overlay.dragStart.x;
      int y2 = g_overlay.dragStart.y < g_overlay.dragCurrent.y ? g_overlay.dragCurrent.y : g_overlay.dragStart.y;
      Rectangle(hdc, x1, y1, x2, y2);

      SetBkColor(hdc, OVERLAY_BG_COLOR);
      SetTextColor(hdc, RECT_COLOR);
      wchar_t sizeText[64];
      swprintf_s(sizeText, L"%dx%d", x2 - x1, y2 - y1);
      TextOutW(hdc, x1, y1 - 18, sizeText, (int)wcslen(sizeText));

      SelectObject(hdc, hOldPen);
      SelectObject(hdc, hOldBrush);
      DeleteObject(hPen);
    } else {
      HPEN hPen = CreatePen(PS_SOLID, 1, RECT_COLOR);
      HPEN hOldPen = (HPEN)SelectObject(hdc, hPen);
      MoveToEx(hdc, 0, pt.y, nullptr);
      LineTo(hdc, w, pt.y);
      MoveToEx(hdc, pt.x, 0, nullptr);
      LineTo(hdc, pt.x, h);
      SelectObject(hdc, hOldPen);
      DeleteObject(hPen);
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
    wc.hbrBackground = CreateSolidBrush(OVERLAY_BG_COLOR);
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

  // Make magenta background transparent
  SetLayeredWindowAttributes(g_overlay.hwnd, OVERLAY_BG_COLOR, 0, LWA_COLORKEY);

  // Start repaint timer at 30fps
  SetTimer(g_overlay.hwnd, OVERLAY_TIMER_ID, 1000 / OVERLAY_FPS, nullptr);

  // Show and focus
  ShowWindow(g_overlay.hwnd, SW_SHOW);
  SetForegroundWindow(g_overlay.hwnd);
  SetFocus(g_overlay.hwnd);
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

  HWND hwnd = GetHandle();

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
          BOOL success = RegisterHotKey(GetHandle(), id, modifiers, vk);
          if (success) {
            registered_hotkey_ids_.push_back(id);
          }
          result->Success(flutter::EncodableValue(success != 0));
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
          result->Success(flutter::EncodableValue(success != 0));
        } else if (call.method_name() == "unregisterAll") {
          for (int id : registered_hotkey_ids_) {
            UnregisterHotKey(GetHandle(), id);
          }
          registered_hotkey_ids_.clear();
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
        } else if (call.method_name() == "getPixelColor") {
          const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
          if (!args || args->size() < 2) {
            result->Error("INVALID_ARGS", "Expected [x, y]");
            return;
          }
          int x = GetInt(args->at(0));
          int y = GetInt(args->at(1));
          HDC hdc = GetDC(nullptr);
          COLORREF color = GetPixel(hdc, x, y);
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
          if (w <= 0 || h <= 0 || w > 1920 || h > 1080) {
            result->Error("INVALID_SIZE", "Capture size out of range");
            return;
          }
          HDC hdcScreen = GetDC(nullptr);
          HDC hdcMem = CreateCompatibleDC(hdcScreen);
          HBITMAP hBitmap = CreateCompatibleBitmap(hdcScreen, w, h);
          HBITMAP hOld = (HBITMAP)SelectObject(hdcMem, hBitmap);
          BitBlt(hdcMem, 0, 0, w, h, hdcScreen, x, y, SRCCOPY);
          SelectObject(hdcMem, hOld);

          BITMAPINFOHEADER bi = {};
          bi.biSize = sizeof(BITMAPINFOHEADER);
          bi.biWidth = w;
          bi.biHeight = -h;
          bi.biPlanes = 1;
          bi.biBitCount = 32;
          bi.biCompression = BI_RGB;

          std::vector<uint8_t> pixels(w * h * 4);
          GetDIBits(hdcMem, hBitmap, 0, h, pixels.data(), (BITMAPINFO*)&bi, DIB_RGB_COLORS);

          DeleteObject(hBitmap);
          DeleteDC(hdcMem);
          ReleaseDC(nullptr, hdcScreen);

          result->Success(flutter::EncodableValue(pixels));
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
          int tplW = GetInt(args->at(5));
          int tplH = GetInt(args->at(6));
          double threshold = 0.8;
          if (const auto* d = std::get_if<double>(&args->at(7))) threshold = *d;
          else if (const auto* i32 = std::get_if<int32_t>(&args->at(7))) threshold = static_cast<double>(*i32);
          else if (const auto* i64 = std::get_if<int64_t>(&args->at(7))) threshold = static_cast<double>(*i64);

          if (!tplBytes || tplW <= 0 || tplH <= 0 || regionW <= 0 || regionH <= 0) {
            result->Error("INVALID_ARGS", "Invalid template or region dimensions");
            return;
          }

          // Convert EncodableList to uint8_t vector
          std::vector<uint8_t> tplData(tplBytes->size());
          for (size_t idx = 0; idx < tplBytes->size(); idx++) {
            if (const auto* b32 = std::get_if<int32_t>(&tplBytes->at(idx))) tplData[idx] = static_cast<uint8_t>(*b32);
            else if (const auto* b64 = std::get_if<int64_t>(&tplBytes->at(idx))) tplData[idx] = static_cast<uint8_t>(*b64);
          }

          // Capture the screen region
          HDC hdcScreen = GetDC(nullptr);
          HDC hdcMem = CreateCompatibleDC(hdcScreen);
          HBITMAP hBitmap = CreateCompatibleBitmap(hdcScreen, regionW, regionH);
          HBITMAP hOld = (HBITMAP)SelectObject(hdcMem, hBitmap);
          BitBlt(hdcMem, 0, 0, regionW, regionH, hdcScreen, regionX, regionY, SRCCOPY);

          BITMAPINFOHEADER bi = {};
          bi.biSize = sizeof(BITMAPINFOHEADER);
          bi.biWidth = regionW;
          bi.biHeight = -regionH;
          bi.biPlanes = 1;
          bi.biBitCount = 32;
          bi.biCompression = BI_RGB;

          std::vector<uint8_t> regionPixels(regionW * regionH * 4);
          GetDIBits(hdcMem, hBitmap, 0, regionH, regionPixels.data(), (BITMAPINFO*)&bi, DIB_RGB_COLORS);
          SelectObject(hdcMem, hOld);
          DeleteObject(hBitmap);
          DeleteDC(hdcMem);
          ReleaseDC(nullptr, hdcScreen);

          // Template matching using normalized cross-correlation (simplified: sum of absolute differences)
          // Search for the template in the region
          flutter::EncodableList matches;
          int searchW = regionW - tplW + 1;
          int searchH = regionH - tplH + 1;
          if (searchW <= 0 || searchH <= 0) {
            result->Success(flutter::EncodableValue(matches));
            return;
          }

          // Sample step for performance (skip pixels for large searches)
          int step = 1;
          if (searchW * searchH > 500000) step = 2;
          if (searchW * searchH > 2000000) step = 3;

          double bestScore = 0;
          int bestX = -1, bestY = -1;

          for (int sy = 0; sy < searchH; sy += step) {
            for (int sx = 0; sx < searchW; sx += step) {
              double totalDiff = 0;
              int sampleCount = 0;
              // Sample every 2nd pixel for speed
              for (int ty = 0; ty < tplH; ty += 2) {
                for (int tx = 0; tx < tplW; tx += 2) {
                  int rIdx = ((sy + ty) * regionW + (sx + tx)) * 4;
                  int tIdx = (ty * tplW + tx) * 4;
                  if (rIdx + 3 >= (int)regionPixels.size() || tIdx + 3 >= (int)tplData.size()) continue;
                  // BGRA comparison
                  int db = abs((int)regionPixels[rIdx] - (int)tplData[tIdx]);
                  int dg = abs((int)regionPixels[rIdx+1] - (int)tplData[tIdx+1]);
                  int dr = abs((int)regionPixels[rIdx+2] - (int)tplData[tIdx+2]);
                  totalDiff += (db + dg + dr) / (255.0 * 3.0);
                  sampleCount++;
                }
              }
              if (sampleCount == 0) continue;
              double score = 1.0 - (totalDiff / sampleCount);
              if (score >= threshold && score > bestScore) {
                bestScore = score;
                bestX = regionX + sx;
                bestY = regionY + sy;
              }
            }
          }

          if (bestX >= 0 && bestY >= 0) {
            flutter::EncodableMap match;
            match[flutter::EncodableValue("x")] = flutter::EncodableValue(bestX);
            match[flutter::EncodableValue("y")] = flutter::EncodableValue(bestY);
            match[flutter::EncodableValue("width")] = flutter::EncodableValue(tplW);
            match[flutter::EncodableValue("height")] = flutter::EncodableValue(tplH);
            match[flutter::EncodableValue("score")] = flutter::EncodableValue(bestScore);
            matches.push_back(flutter::EncodableValue(match));
          }

          result->Success(flutter::EncodableValue(matches));
        } else if (call.method_name() == "ocrRegion") {
          // OCR a screen region using Windows.Media.Ocr (WinRT)
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

          // Capture the region as BGRA pixels
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

          // Convert BGRA to RGBA for SoftwareBitmap
          std::vector<uint8_t> rgba(ocrW * ocrH * 4);
          for (int i = 0; i < ocrW * ocrH; i++) {
            rgba[i*4+0] = pixels[i*4+2]; // R
            rgba[i*4+1] = pixels[i*4+1]; // G
            rgba[i*4+2] = pixels[i*4+0]; // B
            rgba[i*4+3] = pixels[i*4+3]; // A
          }

          // Use WinRT OCR
          // We need to initialize WinRT and use OcrEngine
          // This requires C++/WinRT headers which may not be available
          // Fallback: try to use PowerShell via command line for OCR
          // For now, return the captured image data so Dart can process it
          // We'll implement a proper WinRT OCR in a future update

          // Save to a temp BMP file and use Windows OCR via PowerShell
          char tempDir[MAX_PATH];
          GetTempPathA(MAX_PATH, tempDir);
          std::string tempPath = std::string(tempDir) + "clicker_ocr_" + std::to_string(GetCurrentProcessId()) + "_" + std::to_string(GetTickCount64()) + ".bmp";

          // Write BMP file
          FILE* f = nullptr;
          fopen_s(&f, tempPath.c_str(), "wb");
          if (f) {
            BITMAPFILEHEADER bfh = {};
            bfh.bfType = 0x4D42; // 'BM'
            bfh.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
            bfh.bfSize = bfh.bfOffBits + (DWORD)pixels.size();

            BITMAPINFOHEADER bmi = {};
            bmi.biSize = sizeof(BITMAPINFOHEADER);
            bmi.biWidth = ocrW;
            bmi.biHeight = ocrH;
            bmi.biPlanes = 1;
            bmi.biBitCount = 32;
            bmi.biCompression = BI_RGB;
            bmi.biSizeImage = (DWORD)pixels.size();

            // BMP stores rows bottom-up, but our pixels are top-down, so flip
            std::vector<uint8_t> flipped(pixels.size());
            int rowSize = ocrW * 4;
            for (int y = 0; y < ocrH; y++) {
              memcpy(&flipped[(ocrH - 1 - y) * rowSize], &pixels[y * rowSize], rowSize);
            }

            fwrite(&bfh, sizeof(bfh), 1, f);
            fwrite(&bmi, sizeof(bmi), 1, f);
            fwrite(flipped.data(), 1, flipped.size(), f);
            fclose(f);

            // Use PowerShell to call Windows.Media.Ocr
            std::string psCmd =
              "Add-Type -AssemblyName System.Runtime.WindowsRuntime; "
              "[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime] | Out-Null; "
              "[Windows.Media.Ocr.OcrEngine,Windows.Media.Ocr,ContentType=WindowsRuntime] | Out-Null; "
              "[Windows.Graphics.Imaging.SoftwareBitmap,Windows.Graphics.Imaging,ContentType=WindowsRuntime] | Out-Null; "
              "[Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime] | Out-Null; "
              "$file = [Windows.Storage.StorageFile]::GetFileFromPathAsync('" + tempPath + "').AsTask().GetAwaiter().GetResult(); "
              "$stream = $file.OpenAsync([Windows.Storage.FileAccessMode]::Read).AsTask().GetAwaiter().GetResult(); "
              "$decoder = [Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream).AsTask().GetAwaiter().GetResult(); "
              "$bmp = $decoder.GetSoftwareBitmapAsync().AsTask().GetAwaiter().GetResult(); "
              "$ocrEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages(); "
              "if ($ocrEngine -eq $null) { Write-Output 'OCR_NOT_AVAILABLE' } else { "
              "$result = $ocrEngine.RecognizeAsync($bmp).AsTask().GetAwaiter().GetResult(); "
              "Write-Output $result.Text }";

            // Escape for cmd.exe
            std::string cmd = "powershell -NoProfile -NonInteractive -Command \"" + psCmd + "\"";

            // Execute PowerShell
            std::string ocrText;
            char buffer[256];
            FILE* pipe = _popen(cmd.c_str(), "r");
            if (pipe) {
              while (fgets(buffer, sizeof(buffer), pipe)) {
                ocrText += buffer;
              }
              _pclose(pipe);
            }

            // Clean up temp file
            remove(tempPath.c_str());

            // Trim whitespace
            while (!ocrText.empty() && (ocrText.back() == '\n' || ocrText.back() == '\r' || ocrText.back() == ' '))
              ocrText.pop_back();

            if (ocrText == "OCR_NOT_AVAILABLE") {
              result->Error("OCR_NOT_AVAILABLE", "Windows OCR engine not available. Install OCR language pack.");
              return;
            }

            flutter::EncodableMap ocrResult;
            ocrResult[flutter::EncodableValue("text")] = flutter::EncodableValue(ocrText);
            ocrResult[flutter::EncodableValue("x")] = flutter::EncodableValue(ocrX);
            ocrResult[flutter::EncodableValue("y")] = flutter::EncodableValue(ocrY);
            ocrResult[flutter::EncodableValue("width")] = flutter::EncodableValue(ocrW);
            ocrResult[flutter::EncodableValue("height")] = flutter::EncodableValue(ocrH);
            result->Success(flutter::EncodableValue(ocrResult));
          } else {
            result->Error("FILE_ERROR", "Failed to create temp file for OCR");
          }
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
          if (args->size() >= 12) {
            const auto* kbPtr = std::get_if<bool>(&args->at(9));
            isKeyboard = kbPtr ? *kbPtr : false;
            keyVk = GetInt(args->at(10));
            keyActionMode = GetInt(args->at(11));
            // combo keys start at index 12
            for (size_t i = 12; i < args->size(); i++) {
              comboKeys.push_back(GetInt(args->at(i)));
            }
          }
          StartFastClicker(intervalUs, x, y, button, targetCount, bgMode, targetHwnd, clientX, clientY,
              isKeyboard, keyVk, keyActionMode, comboKeys);
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "stopFastClicker") {
          StopFastClicker();
          result->Success(flutter::EncodableValue(true));
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
            if (triggerNamePtr) entry.trigger_vk = KeyNameToVk(*triggerNamePtr);
            int actionType = GetInt(cfg[1]);
            entry.interval_ms = GetInt(cfg[2]);
            if (entry.interval_ms < 10) entry.interval_ms = 10;

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
          int w = static_cast<int>(920 * scale);
          int h = static_cast<int>(720 * scale);

          // Center on screen
          int screenW = GetSystemMetrics(SM_CXSCREEN);
          int screenH = GetSystemMetrics(SM_CYSCREEN);
          int x = (screenW - w) / 2;
          int y = (screenH - h) / 2;

          // Remove topmost first, then reposition and optionally re-apply
          SetWindowPos(hw, HWND_NOTOPMOST, x, y, w, h, SWP_NOACTIVATE | SWP_FRAMECHANGED);
          if (alwaysOnTop) {
            SetWindowPos(hw, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
          }
          ShowWindow(hw, SW_SHOWNOACTIVATE);
          SetForegroundWindow(hw);

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
          // Use PostMessage to avoid blocking the platform thread.
          // ShowWindow(SW_MAXIMIZE) is synchronous and waits for WM_SIZE
          // handling to complete, causing ~1s delay.
          PostMessage(GetHandle(), WM_SYSCOMMAND, SC_MAXIMIZE, 0);
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "unmaximizeWindow") {
          PostMessage(GetHandle(), WM_SYSCOMMAND, SC_RESTORE, 0);
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "minimizeWindow") {
          PostMessage(GetHandle(), WM_SYSCOMMAND, SC_MINIMIZE, 0);
          result->Success(flutter::EncodableValue(true));
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

          // Install low-level keyboard hook
          keyboard_hook_ = SetWindowsHookExW(
              WH_KEYBOARD_LL, KeyboardHookProc,
              nullptr, 0);
          // Install low-level mouse hook
          mouse_hook_ = SetWindowsHookExW(
              WH_MOUSE_LL, MouseHookProc,
              nullptr, 0);

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
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  // Remove the native title bar style to prevent system from drawing
  // caption buttons that would overlap with our custom title bar.
  // We keep WS_THICKFRAME for resize and WS_MAXIMIZEBOX/WS_MINIMIZEBOX
  // for window state transitions.
  LONG style = GetWindowLong(hwnd, GWL_STYLE);
  style &= ~(WS_CAPTION | WS_SYSMENU);  // Remove caption and system menu
  SetWindowLong(hwnd, GWL_STYLE, style);

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
    bool key_down = (wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN);
    bool key_up = (wparam == WM_KEYUP || wparam == WM_SYSKEYUP);

    if ((key_down || key_up) && g_hold_trigger_count > 0) {
      EnterCriticalSection(&g_hold_trigger_cs);
      for (int i = 0; i < g_hold_trigger_count; i++) {
        if (g_hold_triggers[i].trigger_vk == vk) {
          if (key_down && !g_hold_triggers[i].active) {
            StartHoldTrigger(&g_hold_triggers[i]);
          } else if (key_up && g_hold_triggers[i].active) {
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
    if (self && self->record_channel_ && self->is_recording_) {
      // Forward mouse events: down, up, move, wheel
      if (wparam == WM_LBUTTONDOWN || wparam == WM_LBUTTONUP ||
          wparam == WM_RBUTTONDOWN || wparam == WM_RBUTTONUP ||
          wparam == WM_MBUTTONDOWN || wparam == WM_MBUTTONUP ||
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
  // Handle system-level hotkey messages.
  if (message == WM_HOTKEY) {
    int id = static_cast<int>(wparam);

    // Stop the clicker IMMEDIATELY in C++ for start/stop and emergency stop
    // hotkeys, without waiting for the Dart round-trip. This eliminates
    // 20-50ms of latency that makes 1ms clicking feel unresponsive.
    if (id == 1 || id == 3) {  // startStopClicker or emergencyStop
      StopFastClicker();

      // Also notify Dart to stop immediately (for keyboard mode which uses
      // Dart Timers, not the native clicker thread). This bypasses the normal
      // onHotkey → toggle() path which has extra latency.
      if (hotkey_channel_) {
        hotkey_channel_->InvokeMethod(
            "onStopClickerImmediate",
            std::make_unique<flutter::EncodableValue>(id));
      }
    }

    // Notify Dart for normal hotkey handling (toggle, UI updates, etc.)
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
        // Left click: show main window
        if (platform_channel_) {
          platform_channel_->InvokeMethod("onTrayIconClick", nullptr);
        }
        break;
      }
      case WM_RBUTTONUP: {
        // Right click: show context menu
        ShowTrayMenu();
        break;
      }
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

static struct {
  volatile bool running = false;
  volatile bool stop_requested = false;
  volatile uint64_t generation = 0;
  int interval_ms = 10;           // milliseconds per click (min 1)
  int x = -1;
  int y = -1;
  int button = 0;                 // 0=left, 1=right, 2=middle (mouse only)
  volatile int click_count = 0;
  int target_count = -1;
  flutter::MethodChannel<flutter::EncodableValue>* channel = nullptr;
  bool background_mode = false;
  HWND target_hwnd = nullptr;
  int client_x = 0;
  int client_y = 0;
  // Keyboard mode fields
  bool is_keyboard = false;       // true = keyboard mode, false = mouse mode
  int key_vk = 0;                 // Virtual key code for keyboard repeat
  int key_action_mode = 0;        // 0=repeat, 1=hold, 2=combo
  int combo_keys[8] = {};         // VK codes for combo mode
  int combo_key_count = 0;
} g_clicker;

static void SendOneClick() {
  if (g_clicker.is_keyboard) {
    // Keyboard repeat mode: press and release the key
    if (g_clicker.key_action_mode == 0) {
      INPUT inputs[2] = {};
      inputs[0].type = INPUT_KEYBOARD;
      inputs[0].ki.wVk = static_cast<WORD>(g_clicker.key_vk);
      inputs[1].type = INPUT_KEYBOARD;
      inputs[1].ki.wVk = static_cast<WORD>(g_clicker.key_vk);
      inputs[1].ki.dwFlags = KEYEVENTF_KEYUP;
      SendInput(2, inputs, sizeof(INPUT));
    } else if (g_clicker.key_action_mode == 2) {
      // Combo mode: press all keys down, then release all
      int n = g_clicker.combo_key_count;
      if (n > 8) n = 8;
      INPUT inputs[16] = {};
      for (int i = 0; i < n; i++) {
        inputs[i].type = INPUT_KEYBOARD;
        inputs[i].ki.wVk = static_cast<WORD>(g_clicker.combo_keys[i]);
      }
      for (int i = 0; i < n; i++) {
        inputs[n + i].type = INPUT_KEYBOARD;
        inputs[n + i].ki.wVk = static_cast<WORD>(g_clicker.combo_keys[i]);
        inputs[n + i].ki.dwFlags = KEYEVENTF_KEYUP;
      }
      SendInput(n * 2, inputs, sizeof(INPUT));
    }
    g_clicker.click_count++;
    return;
  }

  // Mouse mode
  if (g_clicker.background_mode && g_clicker.target_hwnd) {
    LPARAM lp = MAKELPARAM(static_cast<WORD>(g_clicker.client_x),
                            static_cast<WORD>(g_clicker.client_y));
    WPARAM wp = MK_LBUTTON;
    UINT msg_down = WM_LBUTTONDOWN;
    UINT msg_up = WM_LBUTTONUP;
    if (g_clicker.button == 1) {
      msg_down = WM_RBUTTONDOWN; msg_up = WM_RBUTTONUP;
    } else if (g_clicker.button == 2) {
      msg_down = WM_MBUTTONDOWN; msg_up = WM_MBUTTONUP;
    }
    PostMessage(g_clicker.target_hwnd, msg_down, wp, lp);
    PostMessage(g_clicker.target_hwnd, msg_up, 0, lp);
    g_clicker.click_count++;
  } else {
    if (g_clicker.x >= 0 && g_clicker.y >= 0) {
      SetCursorPos(g_clicker.x, g_clicker.y);
    }
    INPUT inputs[2] = {};
    DWORD flags_down = MOUSEEVENTF_LEFTDOWN;
    DWORD flags_up = MOUSEEVENTF_LEFTUP;
    if (g_clicker.button == 1) { flags_down = MOUSEEVENTF_RIGHTDOWN; flags_up = MOUSEEVENTF_RIGHTUP; }
    else if (g_clicker.button == 2) { flags_down = MOUSEEVENTF_MIDDLEDOWN; flags_up = MOUSEEVENTF_MIDDLEUP; }

    inputs[0].type = INPUT_MOUSE;
    inputs[0].mi.dwFlags = flags_down;
    inputs[1].type = INPUT_MOUSE;
    inputs[1].mi.dwFlags = flags_up;
    SendInput(2, inputs, sizeof(INPUT));
    g_clicker.click_count++;
  }
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

  int sleep_ms = g_clicker.interval_ms;
  if (sleep_ms < 1) sleep_ms = 1;

  // Keyboard hold mode: press key once, wait for stop, then release
  if (g_clicker.is_keyboard && g_clicker.key_action_mode == 1) {
    INPUT inputs[1] = {};
    inputs[0].type = INPUT_KEYBOARD;
    inputs[0].ki.wVk = static_cast<WORD>(g_clicker.key_vk);
    SendInput(1, inputs, sizeof(INPUT));
    g_clicker.click_count++;

    // Wait until stopped
    while (IsCurrentGeneration(my_generation) && !g_clicker.stop_requested) {
      Sleep(sleep_ms);
    }

    // Release the key
    INPUT up = {};
    up.type = INPUT_KEYBOARD;
    up.ki.wVk = static_cast<WORD>(g_clicker.key_vk);
    up.ki.dwFlags = KEYEVENTF_KEYUP;
    SendInput(1, &up, sizeof(INPUT));
  } else {
    // Normal repeat/combo/mouse mode
    while (IsCurrentGeneration(my_generation) && !g_clicker.stop_requested) {
      if (g_clicker.target_count > 0 && g_clicker.click_count >= g_clicker.target_count) {
        g_clicker.stop_requested = true;
        break;
      }
      SendOneClick();
      Sleep(sleep_ms);
    }
  }

  timeEndPeriod(1);

  g_clicker.running = false;

  // Notify Dart when thread exits. Only notify if our generation is still
  // current (i.e., no new StartFastClicker was called). If generation
  // changed, a new thread was started and will handle its own notification.
  if (IsCurrentGeneration(my_generation) && g_clicker.channel) {
    g_clicker.channel->InvokeMethod("onFastClickerStopped",
      std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
        {flutter::EncodableValue("count"), flutter::EncodableValue(g_clicker.click_count)},
      }));
  }

  return 0;
}

void FlutterWindow::StartFastClicker(int intervalUs, int x, int y, int button, int targetCount,
    bool bgMode, HWND targetHwnd, int clientX, int clientY,
    bool isKeyboard, int keyVk, int keyActionMode,
    const std::vector<int>& comboKeys) {
  // Invalidate any running thread by bumping generation.
  g_clicker.generation++;
  g_clicker.stop_requested = true;
  g_clicker.running = false;

  // Clean up old thread handle.
  // Old thread exits quickly because it checks generation every loop.
  if (clicker_thread_) {
    WaitForSingleObject(clicker_thread_, 100);
    CloseHandle(clicker_thread_);
    clicker_thread_ = nullptr;
  }

  // Set up new clicker state
  // Enforce minimum 10ms interval
  int interval_ms = intervalUs / 1000;
  if (interval_ms < 10) interval_ms = 10;

  g_clicker.interval_ms = interval_ms;
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
  clicker_running_ = true;
}

void FlutterWindow::StopFastClicker() {
  // Signal the thread to stop. The thread checks this flag on every loop
  // iteration and will exit within 1ms (the Sleep duration).
  g_clicker.stop_requested = true;
  g_clicker.running = false;

  // No timer to kill — we use a simple Sleep loop now.
  // No WaitForSingleObject — that would block the platform thread.
  clicker_running_ = false;

  // The thread will send onFastClickerStopped when it exits.
  // Do NOT bump generation here — the thread needs to see its generation
  // is still current so it sends the notification to Dart.
}

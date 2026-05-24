#include "flutter_window.h"

#pragma warning(disable: 4819)

#include <dwmapi.h>
#include <mmsystem.h>
#include <optional>
#include <atomic>
#include <algorithm>

#pragma comment(lib, "winmm.lib")

#include "flutter/generated_plugin_registrant.h"
#include "flutter/standard_method_codec.h"

// Global pointer for low-level hooks (must be global for SetWindowsHookEx).
static FlutterWindow* g_flutter_window_for_hooks = nullptr;

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

  int screenW = GetSystemMetrics(SM_CXSCREEN);
  int screenH = GetSystemMetrics(SM_CYSCREEN);

  g_overlay.channel = channel;
  g_overlay.dragging = false;
  g_overlay.dragStart = {};
  g_overlay.dragCurrent = {};

  g_overlay.hwnd = CreateWindowExW(
    WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TOOLWINDOW,
    kOverlayClassName, L"",
    WS_POPUP | WS_VISIBLE,
    0, 0, screenW, screenH,
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
          int id = std::get<int>(args->at(0));
          int modifiers = std::get<int>(args->at(1));
          int vk = std::get<int>(args->at(2));
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
          int id = std::get<int>(args->at(0));
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
          int x = std::get<int>(args->at(0));
          int y = std::get<int>(args->at(1));
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
          int x = std::get<int>(args->at(0));
          int y = std::get<int>(args->at(1));
          int w = std::get<int>(args->at(2));
          int h = std::get<int>(args->at(3));
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
        } else if (call.method_name() == "startAreaSelectOverlay") {
          // Start area selection overlay
          g_overlay.mode = OverlayMode::AreaSelect;
          CreateOverlayWindow(platform_channel_.get());
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "stopOverlay") {
          DestroyOverlayWindow();
          result->Success(flutter::EncodableValue(true));
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
          int intervalUs = std::get<int>(args->at(0));
          int x = std::get<int>(args->at(1));
          int y = std::get<int>(args->at(2));
          int button = std::get<int>(args->at(3));
          int targetCount = std::get<int>(args->at(4));
          // Optional background mode params: [backgroundMode, hwnd, clientX, clientY]
          bool bgMode = false;
          HWND targetHwnd = nullptr;
          int clientX = 0, clientY = 0;
          if (args->size() >= 9) {
            bgMode = std::get<bool>(args->at(5));
            int64_t hwndVal = std::get<int>(args->at(6));
            targetHwnd = reinterpret_cast<HWND>(static_cast<intptr_t>(hwndVal));
            clientX = std::get<int>(args->at(7));
            clientY = std::get<int>(args->at(8));
          }
          StartFastClicker(intervalUs, x, y, button, targetCount, bgMode, targetHwnd, clientX, clientY);
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
  HWND hwnd = GetHandle();
  LONG style = GetWindowLong(hwnd, GWL_STYLE);
  style &= ~(WS_CAPTION | WS_SYSMENU);  // Remove caption and system menu
  SetWindowLong(hwnd, GWL_STYLE, style);

  // Extend frame into client area to keep window shadow and rounded corners
  MARGINS margins = {0, 0, 0, 1};  // 1px bottom margin to keep shadow
  DwmExtendFrameIntoClientArea(hwnd, &margins);

  return true;
}

void FlutterWindow::OnDestroy() {
  // Stop fast clicker if running.
  StopFastClicker();

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

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

// -- Low-Level Keyboard Hook ------------------------------------------------

LRESULT CALLBACK FlutterWindow::KeyboardHookProc(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HC_ACTION && g_flutter_window_for_hooks) {
    auto* kb = reinterpret_cast<KBDLLHOOKSTRUCT*>(lparam);
    auto* self = g_flutter_window_for_hooks;
    if (self && self->record_channel_ && self->is_recording_) {
      // Only forward key down and key up events (ignore syskey for now)
      if (wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN ||
          wparam == WM_KEYUP || wparam == WM_SYSKEYUP) {
        DWORD elapsed = GetTickCount() - self->record_start_tick_;
        int message = static_cast<int>(wparam);
        int vk = static_cast<int>(kb->vkCode);
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

// ─── Fast Clicker (Native Thread + Multimedia Timer) ──────────────────────

// Global clicker state (shared between thread and callbacks)
static struct {
  bool running = false;
  std::atomic<bool> stop_requested{false};
  int interval_us = 10000;        // microseconds per click
  int x = -1;                     // target x (-1 = current)
  int y = -1;                     // target y
  int button = 0;                 // 0=left, 1=right, 2=middle
  int click_count = 0;
  int target_count = -1;          // -1 = infinite
  MMRESULT timer_id = 0;
  flutter::MethodChannel<flutter::EncodableValue>* channel = nullptr;
  // Background mode
  bool background_mode = false;   // use PostMessage instead of SendInput
  HWND target_hwnd = nullptr;     // target window handle
  int client_x = 0;              // click position relative to client area
  int client_y = 0;
} g_clicker;

static void SendOneClick() {
  if (g_clicker.background_mode && g_clicker.target_hwnd) {
    // Background mode: PostMessage to target window
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
    // Foreground mode: SendInput
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

static void CALLBACK ClickerTimerProc(UINT uID, UINT uMsg, DWORD_PTR dwUser, DWORD_PTR dw1, DWORD_PTR dw2) {
  if (!g_clicker.running || g_clicker.stop_requested) return;

  // Check count limit
  if (g_clicker.target_count > 0 && g_clicker.click_count >= g_clicker.target_count) {
    g_clicker.stop_requested = true;
    return;
  }

  // Double-check stop flag right before sending to reduce overshoot
  if (!g_clicker.stop_requested) {
    SendOneClick();
  }
}

static DWORD WINAPI ClickerThreadFunc(LPVOID param) {
  // Calculate timer resolution in ms (minimum 1ms)
  int timer_ms = (g_clicker.interval_us / 1000);
  if (timer_ms < 1) timer_ms = 1;

  // Start multimedia timer — runs in this thread's context with high precision
  g_clicker.timer_id = timeSetEvent(
    timer_ms, 1,          // period=ms, resolution=1ms
    (LPTIMECALLBACK)ClickerTimerProc,
    (DWORD_PTR)nullptr,
    TIME_PERIODIC | TIME_KILL_SYNCHRONOUS);

  if (g_clicker.timer_id == 0) {
    // Fallback: use Sleep loop if timeSetEvent fails
    while (!g_clicker.stop_requested && g_clicker.running) {
      if (g_clicker.target_count > 0 && g_clicker.click_count >= g_clicker.target_count) break;
      SendOneClick();
      if (g_clicker.interval_us >= 1000) {
        Sleep(g_clicker.interval_us / 1000);
      } else {
        // For sub-ms intervals, just spin (still in separate thread so UI is fine)
        // But yield to prevent 100% CPU burn on single core
        for (int i = 0; i < (1000 / (g_clicker.interval_us > 10 ? g_clicker.interval_us : 10)) && !g_clicker.stop_requested; i++) {
          SendOneClick();
          if (g_clicker.target_count > 0 && g_clicker.click_count >= g_clicker.target_count) break;
          Sleep(0); // yield
        }
      }
    }
  } else {
    // Wait until stop is requested
    while (!g_clicker.stop_requested && g_clicker.running) {
      if (g_clicker.target_count > 0 && g_clicker.click_count >= g_clicker.target_count) {
        g_clicker.stop_requested = true;
        break;
      }
      Sleep(5);
    }
    timeKillEvent(g_clicker.timer_id);
    g_clicker.timer_id = 0;
  }

  g_clicker.running = false;

  // Notify Dart that clicking stopped
  if (g_clicker.channel) {
    g_clicker.channel->InvokeMethod("onFastClickerStopped",
      std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
        {flutter::EncodableValue("count"), flutter::EncodableValue(g_clicker.click_count)},
      }));
  }

  return 0;
}

void FlutterWindow::StartFastClicker(int intervalUs, int x, int y, int button, int targetCount,
    bool bgMode, HWND targetHwnd, int clientX, int clientY) {
  StopFastClicker();

  g_clicker.interval_us = intervalUs;
  g_clicker.x = x;
  g_clicker.y = y;
  g_clicker.button = button;
  g_clicker.target_count = targetCount;
  g_clicker.click_count = 0;
  g_clicker.stop_requested = false;
  g_clicker.running = true;
  g_clicker.channel = platform_channel_.get();
  g_clicker.background_mode = bgMode;
  g_clicker.target_hwnd = targetHwnd;
  g_clicker.client_x = clientX;
  g_clicker.client_y = clientY;

  clicker_thread_ = CreateThread(nullptr, 0, ClickerThreadFunc, this, 0, nullptr);
  clicker_running_ = true;
}

void FlutterWindow::StopFastClicker() {
  if (clicker_running_) {
    g_clicker.stop_requested = true;

    // Kill timer FIRST to stop new callbacks immediately
    if (g_clicker.timer_id != 0) {
      timeKillEvent(g_clicker.timer_id);
      g_clicker.timer_id = 0;
    }

    if (clicker_thread_) {
      WaitForSingleObject(clicker_thread_, 100); // wait up to 100ms
      CloseHandle(clicker_thread_);
      clicker_thread_ = nullptr;
    }
    clicker_running_ = false;
  }
  g_clicker.running = false;
}

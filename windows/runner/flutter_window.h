#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <shellapi.h>

#include <memory>
#include <vector>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Method channel for system-level hotkey communication.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> hotkey_channel_;

  // Method channel for platform utilities (cursor position, etc.).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> platform_channel_;

  // Method channel for macro recording hooks.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> record_channel_;

  // System tray
  NOTIFYICONDATAW tray_icon_data_ = {};
  bool tray_icon_created_ = false;
  UINT tray_callback_msg_ = 0;
  UINT clicker_stopped_msg_ = 0;
  HMENU tray_menu_ = nullptr;

  void InitSystemTray();
  void DestroySystemTray();
  void ShowSystemTray();
  void HideSystemTray();
  void ShowTrayMenu();

  // Track registered hotkey IDs for cleanup.
  std::vector<int> registered_hotkey_ids_;

  // Journal record hook handles (using low-level hooks for stability).
  HHOOK keyboard_hook_ = nullptr;
  HHOOK mouse_hook_ = nullptr;
  bool is_recording_ = false;
  DWORD record_start_tick_ = 0;

  // Static hook procedures (forwards to instance).
  static LRESULT CALLBACK KeyboardHookProc(int code, WPARAM wparam, LPARAM lparam);
  static LRESULT CALLBACK MouseHookProc(int code, WPARAM wparam, LPARAM lparam);

  // Fast clicker (native thread timer)
  HANDLE clicker_thread_ = nullptr;
  bool clicker_running_ = false;
  bool clicker_stop_requested_ = false;

  void StartFastClicker(int intervalUs, int x, int y, int button, int targetCount,
      bool bgMode = false, HWND targetHwnd = nullptr, int clientX = 0, int clientY = 0,
      bool isKeyboard = false, int keyVk = 0, int keyActionMode = 0,
      const std::vector<int>& comboKeys = {});
  void StopFastClicker();
};

// -- Screen Overlay Window --------------------------------------------------
// A transparent fullscreen overlay for color picking and area selection.
// Uses color-key transparency: magenta background is transparent,
// crosshair and selection rectangle are drawn in visible colors.

enum class OverlayMode { None, Crosshair, AreaSelect, WindowPick, DetectionBox };

struct DetectionBox {
  int x, y, w, h;
  float confidence;
  int class_id;
  char class_name[64];
};

struct OverlayState {
  HWND hwnd = nullptr;
  OverlayMode mode = OverlayMode::None;
  bool dragging = false;
  POINT dragStart = {};
  POINT dragCurrent = {};
  flutter::MethodChannel<flutter::EncodableValue>* channel = nullptr;
  HWND target_window = nullptr;
  std::vector<DetectionBox> detection_boxes;
};

// Global overlay state (needed for WndProc)
extern OverlayState g_overlay;

void CreateOverlayWindow(flutter::MethodChannel<flutter::EncodableValue>* channel);
void DestroyOverlayWindow();
void UpdateOverlayCrosshair();

#endif  // RUNNER_FLUTTER_WINDOW_H_

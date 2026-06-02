#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/extensions/XInput2.h>
#endif

#include <thread>
#include <vector>
#include <string>
#include <cstring>
#include <cstdlib>
#include <cmath>
#include <algorithm>
#include <sstream>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* platform_channel;
  FlMethodChannel* hotkey_channel;
  FlMethodChannel* record_channel;
  GtkWidget* overlay_window;
  gboolean overlay_dragging;
  gint overlay_start_x;
  gint overlay_start_y;
  gboolean is_recording;
  guint64 record_start_tick;
  gboolean capturing_key;
  std::vector<int> registered_hotkey_codes;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

#ifdef GDK_WINDOWING_X11

static Display* GetXDisplay() {
  GdkDisplay* gdk_display = gdk_display_get_default();
  if (!gdk_display) return XOpenDisplay(nullptr);
  return gdk_x11_display_get_xdisplay(gdk_display);
}

static std::vector<uint8_t> CaptureScreenRectX11(int x, int y, int w, int h) {
  Display* disp = GetXDisplay();
  if (!disp) return {};

  Window root = DefaultRootWindow(disp);
  XWindowAttributes attrs;
  XGetWindowAttributes(disp, root, &attrs);

  if (x < 0 || y < 0 || w <= 0 || h <= 0 || w > 3840 || h > 2160) {
    return {};
  }

  XImage* img = XGetImage(disp, root, x, y, w, h, AllPlanes, ZPixmap);
  if (!img) return {};

  std::vector<uint8_t> pixels(w * h * 4);
  for (int row = 0; row < h; row++) {
    for (int col = 0; col < w; col++) {
      unsigned long pixel = XGetPixel(img, col, row);
      int idx = (row * w + col) * 4;
      pixels[idx + 0] = static_cast<uint8_t>(pixel & 0xFF);
      pixels[idx + 1] = static_cast<uint8_t>((pixel >> 8) & 0xFF);
      pixels[idx + 2] = static_cast<uint8_t>((pixel >> 16) & 0xFF);
      pixels[idx + 3] = 0xFF;
    }
  }
  XDestroyImage(img);
  return pixels;
}

static void GetScreenSizeX11(int* width, int* height) {
  Display* disp = GetXDisplay();
  if (!disp) {
    *width = 1920;
    *height = 1080;
    return;
  }
  *width = DisplayWidth(disp, DefaultScreen(disp));
  *height = DisplayHeight(disp, DefaultScreen(disp));
}

static void GetCursorPositionX11(int* x, int* y) {
  Display* disp = GetXDisplay();
  if (!disp) {
    *x = 0; *y = 0;
    return;
  }
  Window root = DefaultRootWindow(disp);
  Window root_ret, child_ret;
  int win_x, win_y;
  unsigned int mask;
  XQueryPointer(disp, root, &root_ret, &child_ret, x, y, &win_x, &win_y, &mask);
}

static void GetPixelColorX11(int px, int py, int* r, int* g, int* b) {
  Display* disp = GetXDisplay();
  if (!disp) {
    *r = *g = *b = 0;
    return;
  }
  Window root = DefaultRootWindow(disp);
  XImage* img = XGetImage(disp, root, px, py, 1, 1, AllPlanes, ZPixmap);
  if (!img) {
    *r = *g = *b = 0;
    return;
  }
  unsigned long pixel = XGetPixel(img, 0, 0);
  *r = static_cast<int>(pixel & 0xFF);
  *g = static_cast<int>((pixel >> 8) & 0xFF);
  *b = static_cast<int>((pixel >> 16) & 0xFF);
  XDestroyImage(img);
}

#endif

static gint64 GetTimeMs() {
  GTimeVal tv;
  g_get_current_time(&tv);
  return (gint64)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

static void OnOverlayDraw(GtkWidget* widget, cairo_t* cr, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (!self->overlay_window) return;

  cairo_set_source_rgba(cr, 0, 0, 0, 0);
  cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
  cairo_paint(cr);

#ifdef GDK_WINDOWING_X11
  int mx = 0, my = 0;
  GetCursorPositionX11(&mx, &my);

  GtkAllocation alloc;
  gtk_widget_get_allocation(widget, &alloc);

  cairo_set_source_rgb(cr, 1.0, 0.24, 0.24);
  cairo_set_line_width(cr, 1.0);
  cairo_move_to(cr, 0, my);
  cairo_line_to(cr, alloc.width, my);
  cairo_move_to(cr, mx, 0);
  cairo_line_to(cr, mx, alloc.height);
  cairo_stroke(cr);

  cairo_set_source_rgb(cr, 0.0, 0.7, 1.0);
  cairo_set_line_width(cr, 2.0);
  cairo_arc(cr, mx, my, 8, 0, 2 * M_PI);
  cairo_stroke(cr);
#endif
}

static gboolean OnOverlayButtonPress(GtkWidget* widget, GdkEventButton* event, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);

  if (event->button == 1) {
    self->overlay_dragging = TRUE;
    self->overlay_start_x = static_cast<gint>(event->x_root);
    self->overlay_start_y = static_cast<gint>(event->y_root);
  }
  return TRUE;
}

static gboolean OnOverlayButtonRelease(GtkWidget* widget, GdkEventButton* event, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);

  if (event->button == 1 && self->overlay_dragging) {
    self->overlay_dragging = FALSE;
    int x2 = static_cast<int>(event->x_root);
    int y2 = static_cast<int>(event->y_root);
    int x1 = self->overlay_start_x;
    int y1 = self->overlay_start_y;

    if (self->platform_channel) {
      g_autoptr(FlValue) args = fl_value_new_map();
      fl_value_set_string_take(args, "x1", fl_value_new_int(x1));
      fl_value_set_string_take(args, "y1", fl_value_new_int(y1));
      fl_value_set_string_take(args, "x2", fl_value_new_int(x2));
      fl_value_set_string_take(args, "y2", fl_value_new_int(y2));
      fl_method_channel_invoke_method(self->platform_channel, "onOverlayAreaSelected", args, nullptr, nullptr, nullptr);
    }
    gtk_widget_destroy(self->overlay_window);
    self->overlay_window = nullptr;
  } else if (event->button == 3) {
    if (self->platform_channel) {
      fl_method_channel_invoke_method(self->platform_channel, "onOverlayCancelled", nullptr, nullptr, nullptr, nullptr);
    }
    gtk_widget_destroy(self->overlay_window);
    self->overlay_window = nullptr;
  }
  return TRUE;
}

static gboolean OnOverlayMotionNotify(GtkWidget* widget, GdkEventMotion* event, gpointer user_data) {
  gtk_widget_queue_draw(widget);
  return TRUE;
}

static gboolean OnOverlayKeyPress(GtkWidget* widget, GdkEventKey* event, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (event->keyval == GDK_KEY_Escape) {
    if (self->platform_channel) {
      fl_method_channel_invoke_method(self->platform_channel, "onOverlayCancelled", nullptr, nullptr, nullptr, nullptr);
    }
    gtk_widget_destroy(self->overlay_window);
    self->overlay_window = nullptr;
    return TRUE;
  }
  return FALSE;
}

static void CreateOverlayWindow(MyApplication* self, const char* mode) {
  if (self->overlay_window) {
    gtk_widget_destroy(self->overlay_window);
    self->overlay_window = nullptr;
  }

  self->overlay_dragging = FALSE;
  self->overlay_start_x = 0;
  self->overlay_start_y = 0;

  self->overlay_window = gtk_window_new(GTK_WINDOW_POPUP);
  gtk_window_set_decorated(GTK_WINDOW(self->overlay_window), FALSE);
  gtk_window_set_keep_above(GTK_WINDOW(self->overlay_window), TRUE);
  gtk_window_fullscreen(GTK_WINDOW(self->overlay_window));
  gtk_widget_set_events(self->overlay_window,
      GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK |
      GDK_POINTER_MOTION_MASK | GDK_KEY_PRESS_MASK);

  GdkScreen* screen = gtk_window_get_screen(GTK_WINDOW(self->overlay_window));
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual) {
    gtk_widget_set_visual(self->overlay_window, visual);
  }

  g_signal_connect(self->overlay_window, "draw", G_CALLBACK(OnOverlayDraw), self);
  g_signal_connect(self->overlay_window, "button-press-event", G_CALLBACK(OnOverlayButtonPress), self);
  g_signal_connect(self->overlay_window, "button-release-event", G_CALLBACK(OnOverlayButtonRelease), self);
  g_signal_connect(self->overlay_window, "motion-notify-event", G_CALLBACK(OnOverlayMotionNotify), self);
  g_signal_connect(self->overlay_window, "key-press-event", G_CALLBACK(OnOverlayKeyPress), self);

  gtk_widget_show_all(self->overlay_window);
  gtk_widget_grab_focus(self->overlay_window);
}

static void DestroyOverlayWindow(MyApplication* self) {
  if (self->overlay_window) {
    gtk_widget_destroy(self->overlay_window);
    self->overlay_window = nullptr;
  }
}

static int GetIntFromFlValue(FlValue* val) {
  if (fl_value_get_type(val) == FL_VALUE_TYPE_INT) return static_cast<int>(fl_value_get_int(val));
  if (fl_value_get_type(val) == FL_VALUE_TYPE_FLOAT) return static_cast<int>(fl_value_get_float(val));
  return 0;
}

static void PlatformMethodHandler(FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

#ifdef GDK_WINDOWING_X11
  if (strcmp(method, "captureScreenRect") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (fl_value_get_type(args) != FL_VALUE_TYPE_LIST || fl_value_get_length(args) < 4) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Expected [x, y, w, h]", nullptr));
    } else {
      int x = GetIntFromFlValue(fl_value_get_list_value(args, 0));
      int y = GetIntFromFlValue(fl_value_get_list_value(args, 1));
      int w = GetIntFromFlValue(fl_value_get_list_value(args, 2));
      int h = GetIntFromFlValue(fl_value_get_list_value(args, 3));

      auto pixels = CaptureScreenRectX11(x, y, w, h);
      if (pixels.empty()) {
        response = FL_METHOD_RESPONSE(fl_method_error_response_new("CAPTURE_FAILED", "XGetImage failed", nullptr));
      } else {
        g_autoptr(FlValue) result = fl_value_new_uint8_list(pixels.data(), pixels.size());
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
      }
    }
  } else if (strcmp(method, "getScreenSize") == 0) {
    int w, h;
    GetScreenSizeX11(&w, &h);
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "width", fl_value_new_int(w));
    fl_value_set_string_take(map, "height", fl_value_new_int(h));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
  } else if (strcmp(method, "getCursorPosition") == 0) {
    int x, y;
    GetCursorPositionX11(&x, &y);
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "x", fl_value_new_int(x));
    fl_value_set_string_take(map, "y", fl_value_new_int(y));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
  } else if (strcmp(method, "getPixelColor") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (fl_value_get_type(args) != FL_VALUE_TYPE_LIST || fl_value_get_length(args) < 2) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Expected [x, y]", nullptr));
    } else {
      int x = GetIntFromFlValue(fl_value_get_list_value(args, 0));
      int y = GetIntFromFlValue(fl_value_get_list_value(args, 1));
      int r, g, b;
      GetPixelColorX11(x, y, &r, &g, &b);
      g_autoptr(FlValue) map = fl_value_new_map();
      fl_value_set_string_take(map, "r", fl_value_new_int(r));
      fl_value_set_string_take(map, "g", fl_value_new_int(g));
      fl_value_set_string_take(map, "b", fl_value_new_int(b));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
    }
  } else if (strcmp(method, "startAreaSelectOverlay") == 0) {
    CreateOverlayWindow(self, "area");
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "startPickOverlay") == 0) {
    CreateOverlayWindow(self, "pick");
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "startWindowPickOverlay") == 0) {
    CreateOverlayWindow(self, "pick");
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "stopOverlay") == 0) {
    DestroyOverlayWindow(self);
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "showDetectionBoxes") == 0) {
    CreateOverlayWindow(self, "detection");
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "updateDetectionBoxes") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "saveScreenshot") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (fl_value_get_type(args) != FL_VALUE_TYPE_LIST || fl_value_get_length(args) < 5) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Expected [x, y, w, h, path]", nullptr));
    } else {
      int x = GetIntFromFlValue(fl_value_get_list_value(args, 0));
      int y = GetIntFromFlValue(fl_value_get_list_value(args, 1));
      int w = GetIntFromFlValue(fl_value_get_list_value(args, 2));
      int h = GetIntFromFlValue(fl_value_get_list_value(args, 3));
      const char* path = "";
      FlValue* path_val = fl_value_get_list_value(args, 4);
      if (fl_value_get_type(path_val) == FL_VALUE_TYPE_STRING) {
        path = fl_value_get_string(path_val);
      }

      auto pixels = CaptureScreenRectX11(x, y, w, h);
      if (pixels.empty()) {
        response = FL_METHOD_RESPONSE(fl_method_error_response_new("CAPTURE_FAILED", "Screen capture failed", nullptr));
      } else {
        FILE* f = fopen(path, "wb");
        if (f) {
          int row_size = w * 4;
          int pad = (4 - (row_size % 4)) % 4;
          int row_stride = row_size + pad;
          int img_size = row_stride * h;

          uint8_t bfh[14] = {0x42, 0x4D, 0, 0, 0, 0, 0, 0, 0, 0, 54, 0, 0, 0};
          uint32_t file_size = 54 + img_size;
          memcpy(bfh + 2, &file_size, 4);

          uint8_t bih[40] = {};
          int32_t bi_size = 40;
          int32_t bi_w = w;
          int32_t bi_h = h;
          int16_t bi_planes = 1;
          int16_t bi_bpp = 32;
          memcpy(bih, &bi_size, 4);
          memcpy(bih + 4, &bi_w, 4);
          memcpy(bih + 8, &bi_h, 4);
          memcpy(bih + 12, &bi_planes, 2);
          memcpy(bih + 14, &bi_bpp, 2);

          fwrite(bfh, 1, 14, f);
          fwrite(bih, 1, 40, f);

          std::vector<uint8_t> row(row_stride, 0);
          for (int r = h - 1; r >= 0; r--) {
            for (int c = 0; c < w; c++) {
              int src = (r * w + c) * 4;
              row[c * 4 + 0] = pixels[src + 2];
              row[c * 4 + 1] = pixels[src + 1];
              row[c * 4 + 2] = pixels[src + 0];
              row[c * 4 + 3] = 0;
            }
            fwrite(row.data(), 1, row_stride, f);
          }
          fclose(f);
          g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
          response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
        } else {
          response = FL_METHOD_RESPONSE(fl_method_error_response_new("FILE_ERROR", "Failed to open file", nullptr));
        }
      }
    }
  } else if (strcmp(method, "findImage") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (fl_value_get_type(args) != FL_VALUE_TYPE_LIST || fl_value_get_length(args) < 8) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Expected [rx, ry, rw, rh, tplBytes, tw, th, threshold]", nullptr));
    } else {
      int regionX = GetIntFromFlValue(fl_value_get_list_value(args, 0));
      int regionY = GetIntFromFlValue(fl_value_get_list_value(args, 1));
      int regionW = GetIntFromFlValue(fl_value_get_list_value(args, 2));
      int regionH = GetIntFromFlValue(fl_value_get_list_value(args, 3));
      FlValue* tpl_val = fl_value_get_list_value(args, 4);
      int tplW = GetIntFromFlValue(fl_value_get_list_value(args, 5));
      int tplH = GetIntFromFlValue(fl_value_get_list_value(args, 6));
      double threshold = 0.8;
      FlValue* thresh_val = fl_value_get_list_value(args, 7);
      if (fl_value_get_type(thresh_val) == FL_VALUE_TYPE_FLOAT) threshold = fl_value_get_float(thresh_val);
      else if (fl_value_get_type(thresh_val) == FL_VALUE_TYPE_INT) threshold = static_cast<double>(fl_value_get_int(thresh_val));

      auto regionPixels = CaptureScreenRectX11(regionX, regionY, regionW, regionH);
      if (regionPixels.empty() || fl_value_get_type(tpl_val) != FL_VALUE_TYPE_UINT8_LIST) {
        g_autoptr(FlValue) list = fl_value_new_list();
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
      } else {
        const uint8_t* tplData = fl_value_get_uint8_list(tpl_val);
        size_t tplLen = fl_value_get_length(tpl_val);

        int searchW = regionW - tplW + 1;
        int searchH = regionH - tplH + 1;
        double bestScore = 0;
        int bestX = -1, bestY = -1;

        int step = 1;
        if (searchW * searchH > 500000) step = 2;
        if (searchW * searchH > 2000000) step = 3;

        for (int sy = 0; sy < searchH; sy += step) {
          for (int sx = 0; sx < searchW; sx += step) {
            double totalDiff = 0;
            int sampleCount = 0;
            for (int ty = 0; ty < tplH; ty += 2) {
              for (int tx = 0; tx < tplW; tx += 2) {
                int rIdx = ((sy + ty) * regionW + (sx + tx)) * 4;
                int tIdx = (ty * tplW + tx) * 4;
                if (rIdx + 3 >= (int)regionPixels.size() || tIdx + 3 >= (int)tplLen) continue;
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

        g_autoptr(FlValue) list = fl_value_new_list();
        if (bestX >= 0 && bestY >= 0) {
          g_autoptr(FlValue) match = fl_value_new_map();
          fl_value_set_string_take(match, "x", fl_value_new_int(bestX));
          fl_value_set_string_take(match, "y", fl_value_new_int(bestY));
          fl_value_set_string_take(match, "width", fl_value_new_int(tplW));
          fl_value_set_string_take(match, "height", fl_value_new_int(tplH));
          fl_value_set_string_take(match, "score", fl_value_new_float(bestScore));
          fl_value_list_append(list, match);
        }
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
      }
    }
  } else if (strcmp(method, "ocrRegion") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new("OCR_NOT_AVAILABLE", "OCR on Linux requires Tesseract. Install via: sudo apt install tesseract-ocr", nullptr));
  } else if (strcmp(method, "getForegroundWindowTitle") == 0) {
    Display* disp = GetXDisplay();
    if (!disp) {
      g_autoptr(FlValue) result = fl_value_new_string("");
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    } else {
      Window focused;
      int revert_to;
      XGetInputFocus(disp, &focused, &revert_to);
      if (focused == None || focused == PointerRoot) {
        g_autoptr(FlValue) result = fl_value_new_string("");
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
      } else {
        XTextProperty prop;
        char* title = nullptr;
        if (XGetWMName(disp, focused, &prop) && prop.value) {
          title = reinterpret_cast<char*>(prop.value);
          XFree(prop.value);
        }
        g_autoptr(FlValue) result = fl_value_new_string(title ? title : "");
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
        if (title) XFree(title);
      }
    }
  } else if (strcmp(method, "enumerateWindows") == 0) {
    Display* disp = GetXDisplay();
    g_autoptr(FlValue) list = fl_value_new_list();
    if (disp) {
      Window root = DefaultRootWindow(disp);
      Window parent;
      Window* children;
      unsigned int num_children;
      if (XQueryTree(disp, root, &root, &parent, &children, &num_children)) {
        for (unsigned int i = 0; i < num_children; i++) {
          XWindowAttributes wa;
          if (XGetWindowAttributes(disp, children[i], &wa) && wa.map_state == IsViewable) {
            XTextProperty prop;
            if (XGetWMName(disp, children[i], &prop) && prop.value) {
              char* name = reinterpret_cast<char*>(prop.value);
              g_autoptr(FlValue) entry = fl_value_new_map();
              fl_value_set_string_take(entry, "hwnd", fl_value_new_int(static_cast<int64_t>(children[i])));
              fl_value_set_string_take(entry, "title", fl_value_new_string(name));
              fl_value_set_string_take(entry, "className", fl_value_new_string(""));
              fl_value_list_append(list, entry);
              XFree(prop.value);
            }
          }
        }
        if (children) XFree(children);
      }
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
  } else
#endif
  if (strcmp(method, "startFastClicker") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "stopFastClicker") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "initSystemTray") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "destroySystemTray") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "enableAutoStart") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "disableAutoStart") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "captureKey") == 0) {
    self->capturing_key = TRUE;
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void HotkeyMethodHandler(FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "registerHotkey") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "unregisterHotkey") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "unregisterAll") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void RecordMethodHandler(FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "startRecording") == 0) {
    self->is_recording = TRUE;
    self->record_start_tick = static_cast<guint64>(GetTimeMs());
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "stopRecording") == 0) {
    self->is_recording = FALSE;
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  gtk_window_set_title(window, "Clicker");
  gtk_window_set_default_size(window, 920, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();

  self->platform_channel = fl_method_channel_new(
      fl_engine_get_messenger(fl_view_get_engine(view)),
      "com.clicker.pro/platform",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->platform_channel, PlatformMethodHandler, self, nullptr);

  self->hotkey_channel = fl_method_channel_new(
      fl_engine_get_messenger(fl_view_get_engine(view)),
      "clicker/hotkeys",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->hotkey_channel, HotkeyMethodHandler, self, nullptr);

  self->record_channel = fl_method_channel_new(
      fl_engine_get_messenger(fl_view_get_engine(view)),
      "com.clicker.pro/record",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->record_channel, RecordMethodHandler, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, gint* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;
  return TRUE;
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  if (self->overlay_window) {
    gtk_widget_destroy(self->overlay_window);
    self->overlay_window = nullptr;
  }
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->platform_channel = nullptr;
  self->hotkey_channel = nullptr;
  self->record_channel = nullptr;
  self->overlay_window = nullptr;
  self->overlay_dragging = FALSE;
  self->overlay_start_x = 0;
  self->overlay_start_y = 0;
  self->is_recording = FALSE;
  self->record_start_tick = 0;
  self->capturing_key = FALSE;
}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
    "application-id", "com.clicker.pro",
    "flags", G_APPLICATION_NON_UNIQUE,
    nullptr));
}

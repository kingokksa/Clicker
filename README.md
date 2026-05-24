# Clicker Pro

> 🖱 跨平台连点器 / 按键精灵 · Windows `.exe` + Android `.apk`

现代化的自动点击与宏录制工具，基于 Flutter + Material Design 3。

## ✨ 功能

| 功能 | 说明 |
|------|------|
| **自动连点** | 单击/双击、左/右/中键、跟随鼠标或固定位置、10ms~10s 间隔 |
| **位置选取** | 全屏半透明十字光标，点击即获取坐标 |
| **重复模式** | 无限点击 / 指定次数 / 定时关闭 |
| **宏录制** | 录制鼠标+键盘事件序列，保存复用 |
| **宏回放** | 速度调节、循环播放、进度显示 |
| **全局快捷键** | F6 启停、F8 录制、F12 紧急停止（可自定义） |
| **配置管理** | 保存/加载多套配置方案 |
| **暗色/亮色** | Material Design 3 双主题 |
| **📱 跨平台** | Windows EXE + Android APK 同一套代码 |

## 🚀 构建

### 环境要求

- **Flutter SDK** >= 3.16（[安装指引](https://docs.flutter.dev/get-started/install)）
- **Windows**: Visual Studio 2022（勾选 "使用 C++ 的桌面开发"）
- **Android**: Android Studio + Android SDK 33+

### 克隆并安装依赖

```bash
cd Clicker
flutter pub get
```

### Windows 构建 `.exe`

```bash
# 调试运行
flutter run -d windows

# 发布构建（输出在 build/windows/x64/runner/Release/）
flutter build windows --release
```

### Android 构建 `.apk`

```bash
# 调试运行
flutter run -d android

# 发布构建（输出在 build/app/outputs/flutter-apk/）
flutter build apk --release

# 分 ABI 打包（体积更小）
flutter build apk --split-per-abi
```

> ⚠️ **Android 使用须知**：安装后需在 **设置 → 无障碍 → 已安装的服务** 中启用 "Clicker Pro" 才能使用自动点击。

## 🏗 项目结构

```
Clicker/
├── lib/                               # Dart 源码
│   ├── main.dart                      # 入口 + 窗口配置
│   ├── app.dart                       # MaterialApp + Provider
│   ├── models/                        # 数据模型
│   ├── services/                      # 业务逻辑层
│   │   ├── app_state.dart             # 全局状态
│   │   ├── click_service.dart         # 点击引擎
│   │   ├── macro_service.dart         # 录制/回放引擎
│   │   ├── hotkey_service.dart        # 快捷键服务
│   │   └── platform/                  # 平台输入抽象层
│   ├── screens/                       # 页面
│   │   ├── home_screen.dart
│   │   ├── clicker/clicker_page.dart
│   │   ├── macro/macro_page.dart
│   │   └── settings/settings_page.dart
│   ├── widgets/                       # 通用组件
│   └── theme/                         # Material 3 主题
├── windows/                           # Windows 原生层 (C++/Win32)
│   ├── CMakeLists.txt
│   └── runner/
│       ├── input_simulator.h          # Win32 SendInput 封装
│       ├── input_plugin.cpp           # Flutter Channel 桥接
│       ├── main.cpp                   # Win32 入口
│       └── *.cpp / *.h                # Flutter 窗口框架
├── android/                           # Android 原生层 (Kotlin)
│   ├── settings.gradle
│   ├── app/build.gradle
│   └── app/src/main/
│       ├── AndroidManifest.xml
│       ├── res/xml/accessibility_service_config.xml
│       └── kotlin/.../MainActivity.kt # AccessibilityService
├── profiles/                          # 配置方案保存
└── macros/                            # 宏 JSON 保存
```

## 🔌 扩展开发

分层架构，易于扩展：

- **新增平台** → 实现 `PlatformInput` 抽象接口
- **新增功能** → 在 `services/` 添加服务，经 `AppState` 暴露
- **新增页面** → 在 `screens/` 创建，注册到 `HomeScreen`
- **快捷键** → 在 `HotkeyService` 注册新的按键映射

## 📄 许可

MIT License

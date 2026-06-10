# Clicker

#### 作者的话
明明是很简单的工具，但是很少见到功能够用的开源项目，所以自己写了一个简单的，欢迎提交Issue和PR。由于作者不是很熟悉flutter，很多地方用了AI开发，希望有专业的开发者帮忙一起完善。
~~最后，Dart是世界上最狗屎的语言~~

> 自用自动化工具 · 连点器 / 宏录制 / 图像识别 / 目标检测



基于 Flutter 的跨平台自动化工具(Android端暂时没完善)，集成 YOLO 目标检测、模板匹配和可扩展插件系统。

## 功能

### 核心功能
- **自动连点** — 单击/双击、左/右/中键、跟随鼠标或固定位置、10ms~10s 间隔
- **宏录制** — 录制鼠标+键盘事件序列，保存复用，速度调节、循环播放
- **全局快捷键** — F6 启停、F8 录制、Alt+F12 紧急停止（可自定义）

### 图像识别
- **模板匹配** — 截取区域模板，NCC 归一化互相关算法实时匹配
- **OCR 文字识别** — PaddleOCR 引擎，中英文识别，模糊/精确匹配
- **颜色检测** — 指定位置颜色匹配、颜色变化/消失检测
- **YOLO 目标检测** — YOLO11n 模型，COCO 80 类目标实时检测，追踪框可视化

### 条件触发系统
- 检测到目标后自动执行动作：点击、按键、启动/停止连点、运行宏
- 支持多种条件组合：颜色匹配、图像匹配、文字匹配、目标检测
- 可配置检测间隔和置信度阈值

### 插件系统
- **Dart 内置插件** — 编译时打包，按需加载，支持懒初始化
- **C/C++ 原生插件** — 通过 FFI 动态加载 .dll/.so/.dylib，支持模板匹配、OCR、自定义动作
- **插件 SDK** — 完整 C API 头文件 + 项目模板，快速开发原生插件
- 详见 [插件开发文档](docs/PLUGIN_DEV.md)

### 其他
- **悬浮窗** — 迷你控制面板，可拖拽，屏幕边缘自动收起/弹出
- **后台执行** — 向后台窗口发送点击指令（Windows）
- **暗色/亮色主题** — Fluent Design 双主题 + 主题色自定义
- **跨平台** — Windows + Android 同一套代码

## 构建

### 环境要求

- **Flutter SDK** >= 3.16
- **Windows**: Visual Studio 2022（勾选 "使用 C++ 的桌面开发"）
- **Android**: Android Studio + Android SDK 33+

### Windows 构建

```bash
flutter pub get
flutter build windows --release
```

输出在 `build/windows/x64/runner/Release/`

### Android 构建

```bash
flutter build apk --release

# 分 ABI 打包（体积更小）
flutter build apk --split-per-abi
```

输出在 `build/app/outputs/flutter-apk/`

> Android 使用须知：安装后需在 **设置 → 无障碍 → 已安装的服务** 中启用 "Clicker"。

### 目标检测依赖（可选）

如需使用 YOLO 目标检测，在应用内「高级模型」页面下载：
- ONNX Runtime (~200MB)
- YOLO11n 模型 (~6MB)

## 项目结构

```
lib/
├── main.dart                    # 入口
├── app.dart                     # FluentApp + Provider
├── models/                      # 数据模型
├── screens/
│   ├── clicker/                 # 连点器页面
│   ├── macro/                   # 宏录制页面
│   ├── settings/                # 设置页面
│   ├── sidebar/                 # 侧边栏页面
│   │   ├── image_recognition_page.dart  # 图像识别 + 条件触发
│   │   ├── hold_trigger_page.dart       # 按键触发
│   │   ├── plugin_page.dart             # 插件管理
│   │   └── theme_center_page.dart       # 主题中心
│   ├── floating_window.dart     # 悬浮窗
│   └── home_screen.dart         # 主界面
├── services/
│   ├── plugin_system.dart       # 插件框架（ClickerPlugin / NativeClickerPlugin）
│   ├── plugin_registry.dart     # 插件注册中心（安装/启用/持久化）
│   ├── plugin_store.dart        # 插件商店（远程索引/下载）
│   ├── native_plugin_loader.dart # FFI 原生插件加载器
│   ├── vision_plugin.dart       # 视觉插件接口（模板匹配/OCR/检测）
│   ├── vision_service.dart      # 图像识别服务
│   ├── screen_overlay_service.dart  # 屏幕覆盖层
│   ├── click_service.dart       # 点击引擎
│   ├── macro_service.dart       # 录制/回放引擎
│   ├── hotkey_service.dart      # 快捷键服务
│   ├── plugins/                 # 内置插件实现
│   └── platform/                # 平台输入抽象层
├── widgets/                     # 通用组件
sdk/
├── clicker_plugin.h             # 插件 SDK C API 头文件
└── template/                    # 插件项目模板
    ├── manifest.json
    └── src/
        ├── main.c              # 模板代码
        ├── build_windows.bat
        └── build_unix.sh
plugins/
├── plugin_index.json            # 插件商店索引
└── ai_tracker/                  # YOLO 目标检测插件 (C++/ONNX)
windows/
└── runner/
    └── flutter_window.cpp       # Windows 原生层 (截图/输入/覆盖层)
android/
└── app/src/main/
    └── kotlin/                  # Android 无障碍服务
```

## 许可

CC BY-NC 4.0 — 详见 [LICENSE](LICENSE) 文件。
本作品可自由使用和修改，但**禁止商用**。

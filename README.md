# Clicker Pro

> Windows 自动化工具 · 连点器 / 宏录制 / 图像识别 / 目标检测

基于 Flutter + Fluent Design 的桌面自动化工具，集成 YOLO 目标检测和模板匹配。

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

### 其他
- **悬浮窗** — 迷你控制面板，可拖拽，屏幕边缘自动收起/弹出
- **插件系统** — 可扩展的插件架构，支持第三方插件
- **暗色/亮色主题** — Fluent Design 双主题 + 主题色自定义

## 构建

### 环境要求

- **Flutter SDK** >= 3.16
- **Visual Studio 2022**（勾选 "使用 C++ 的桌面开发"）

### 构建 Release

```bash
flutter pub get
flutter build windows --release
```

输出在 `build/windows/x64/runner/Release/`

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
│   ├── app_state.dart           # 全局状态
│   ├── click_service.dart       # 点击引擎
│   ├── macro_service.dart       # 录制/回放引擎
│   ├── hotkey_service.dart      # 快捷键服务
│   ├── vision_service.dart      # 图像识别服务
│   ├── vision_plugin.dart       # 视觉插件接口
│   ├── screen_overlay_service.dart  # 屏幕覆盖层
│   ├── plugins/                 # 插件实现
│   └── platform/                # 平台输入抽象层
├── widgets/                     # 通用组件
plugins/
└── ai_tracker/                  # YOLO 目标检测插件 (C++/ONNX)
windows/
└── runner/
    └── flutter_window.cpp       # Windows 原生层 (截图/输入/覆盖层)
```

## 许可

CC BY-NC 4.0 — 详见 [LICENSE](LICENSE) 文件。
本作品可自由使用和修改，但**禁止商用**。

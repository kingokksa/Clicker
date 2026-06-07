# Clicker 插件开发文档

本文档介绍如何为 Clicker 开发插件。Clicker 支持两种插件类型：

- **Dart 内置插件** — 随应用编译打包，适合核心功能扩展
- **C/C++ 原生插件** — 动态加载 .dll/.so/.dylib，适合性能敏感场景和第三方分发

---

## 目录

- [架构概览](#架构概览)
- [Dart 内置插件](#dart-内置插件)
- [C/C++ 原生插件](#cc-原生插件)
  - [快速开始](#快速开始)
  - [插件包结构](#插件包结构)
  - [manifest.json](#manifestjson)
  - [C API 参考](#c-api-参考)
  - [构建与打包](#构建与打包)
- [视觉插件接口](#视觉插件接口)
- [插件生命周期](#插件生命周期)
- [安装与分发](#安装与分发)
- [插件商店](#插件商店)

---

## 架构概览

```
┌─────────────────────────────────────────────────┐
│                  Clicker App                     │
├─────────────────────────────────────────────────┤
│  PluginRegistry  ←──  PluginStore (远程索引)     │
│       │                                          │
│       ├── Dart 内置插件 (ClickerPlugin)          │
│       │     按需初始化，编译时打包                 │
│       │                                          │
│       └── 原生插件 (NativeClickerPlugin)         │
│             │                                    │
│             └── NativePluginLoader (dart:ffi)    │
│                   │                              │
│                   └── .dll / .so / .dylib        │
├─────────────────────────────────────────────────┤
│  VisionPluginManager ←── VisionPlugin 接口       │
│       (模板匹配 / OCR / 目标检测 / 颜色匹配)      │
└─────────────────────────────────────────────────┘
```

**关键类：**

| 类 | 文件 | 职责 |
|---|---|---|
| `ClickerPlugin` | `plugin_system.dart` | Dart 插件基类 |
| `NativeClickerPlugin` | `plugin_system.dart` | 原生插件包装 |
| `PluginRegistry` | `plugin_registry.dart` | 插件注册/安装/启用/持久化 |
| `PluginStore` | `plugin_store.dart` | 远程插件索引/下载 |
| `LoadedNativePlugin` | `native_plugin_loader.dart` | FFI 加载/调用原生库 |
| `VisionPlugin` | `vision_plugin.dart` | 视觉识别插件接口 |

---

## Dart 内置插件

Dart 插件继承 `ClickerPlugin`，编译时打包进应用，但默认不安装，用户从插件商店手动启用。

### 实现

```dart
import 'package:fluent_ui/fluent_ui.dart';
import 'package:clicker/services/plugin_system.dart';

class MyPlugin extends ClickerPlugin {
  @override
  late final ClickerPluginManifest manifest = ClickerPluginManifest(
    id: 'my_plugin',                    // 唯一 ID
    name: '我的插件',
    version: '1.0.0',
    author: '作者',
    description: '插件描述',
    icon: FluentIcons.puzzle,           // Fluent 图标
    category: PluginCategory.extension, // 分类
    source: PluginSource.builtin,       // 内置插件
    platforms: ['windows', 'linux', 'macos'],
  );

  @override
  Future<void> onInitialize() async {
    // 加载资源、初始化服务
  }

  @override
  Future<void> onDispose() async {
    // 释放资源
  }

  @override
  Widget onCreatePage(BuildContext context) {
    // 返回插件页面 Widget
    return ScaffoldPage.scrollable(
      children: [Text('我的插件页面')],
    );
  }

  @override
  Widget? buildSettings(BuildContext context) {
    // 可选：返回设置面板
    return null;
  }
}
```

### 注册

在应用启动时注册：

```dart
PluginRegistry.instance.registerPlugin(MyPlugin());
```

### 插件分类

| PluginCategory | label | 说明 |
|---|---|---|
| `core` | 核心 | 核心功能 |
| `click` | 点击增强 | 连点相关 |
| `vision` | 图像识别 | 图像/文字识别 |
| `automation` | 自动化 | 自动化任务 |
| `ui` | 界面 | 主题/界面 |
| `extension` | 扩展 | 其他 |

---

## C/C++ 原生插件

### 快速开始

1. 复制 SDK 模板：

```bash
cp -r sdk/template my_plugin
```

2. 编辑 `src/main.c`，实现插件逻辑

3. 编辑 `manifest.json`，填写插件信息

4. 构建：

```bash
# Windows
cd my_plugin/src
build_windows.bat my_plugin

# Linux / macOS
cd my_plugin/src
chmod +x build_unix.sh
./build_unix.sh my_plugin
```

5. 安装：将整个 `my_plugin/` 目录打包为 zip，在 Clicker 插件中心安装

### 插件包结构

```
my_plugin/
├── manifest.json              # 插件元数据（必须）
├── windows/
│   └── my_plugin.dll          # Windows 原生库
├── linux/
│   └── my_plugin.so           # Linux 原生库
├── darwin/
│   └── my_plugin.dylib        # macOS 原生库
└── src/                       # 源代码（可选，不打包进发布版）
    ├── clicker_plugin.h       # SDK 头文件
    ├── main.c                 # 插件实现
    ├── build_windows.bat
    └── build_unix.sh
```

### manifest.json

```json
{
  "id": "com.example.my_plugin",
  "name": "我的插件",
  "version": "1.0.0",
  "author": "作者名",
  "description": "插件描述",
  "category": "extension",
  "platforms": ["windows", "linux", "macos"],
  "entry": {
    "windows": "windows/my_plugin.dll",
    "linux": "linux/my_plugin.so",
    "darwin": "darwin/my_plugin.dylib"
  },
  "minAppVersion": 1
}
```

**字段说明：**

| 字段 | 类型 | 必须 | 说明 |
|---|---|---|---|
| `id` | string | 是 | 唯一标识，建议反向域名格式 |
| `name` | string | 是 | 显示名称 |
| `version` | string | 是 | 语义化版本号 |
| `author` | string | 否 | 作者 |
| `description` | string | 否 | 插件描述 |
| `category` | string | 否 | 分类：core/click/vision/automation/ui/extension |
| `platforms` | string[] | 否 | 支持的平台 |
| `entry` | object | 是 | 平台 → 原生库相对路径映射 |
| `minAppVersion` | int | 否 | 最低应用版本 |

### C API 参考

头文件：[sdk/clicker_plugin.h](../sdk/clicker_plugin.h)

#### 必须实现的函数

```c
// 返回插件元数据，指针在插件生命周期内必须有效
PLUGIN_EXPORT const PluginInfo* PLUGIN_CALL plugin_get_info(void);

// 初始化插件，返回 0 表示成功
PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_initialize(void);

// 释放资源，卸载前调用
PLUGIN_EXPORT void PLUGIN_CALL plugin_dispose(void);
```

**PluginInfo 结构体：**

```c
typedef struct {
    const char* id;           // 唯一 ID
    const char* name;         // 显示名称
    const char* version;      // 版本号
    const char* author;       // 作者
    const char* description;  // 描述
    int32_t     category;     // PluginCategory 枚举值
    uint32_t    capabilities; // PluginCapability 位掩码
} PluginInfo;
```

#### 可选能力函数

根据 `capabilities` 位掩码，实现对应函数：

```c
// PLUGIN_CAP_TEMPLATE_MATCH (1 << 0)
// 图像模板匹配
// region_data: 搜索区域 BGRA 像素数据 (region_w * region_h * 4 字节)
// tpl_data:    模板 BGRA 像素数据 (tpl_w * tpl_h * 4 字节)
// threshold:   匹配阈值 [0.5, 1.0]
// out_results: 预分配的结果数组
// 返回: 匹配数量
PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_template_match(
    const uint8_t* region_data, int32_t region_w, int32_t region_h,
    const uint8_t* tpl_data,    int32_t tpl_w,    int32_t tpl_h,
    double threshold,
    PluginMatchResult* out_results, int32_t max_results);

// PLUGIN_CAP_OCR (1 << 1)
// OCR 文字识别
// image_data: BGRA 像素数据 (w * h * 4 字节)
// language:   BCP-47 语言标签，如 "zh-Hans-CN"、"en-US"
// 返回: 0 成功，非 0 失败
PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_ocr(
    const uint8_t* image_data, int32_t w, int32_t h,
    const char* language,
    PluginOcrResult* out_result);

// PLUGIN_CAP_CUSTOM (1 << 8)
// 自定义动作
// action_id: 动作标识（插件自定义）
// params:    JSON 参数字符串
// out_buf:   输出缓冲区
// 返回: 0 成功，非 0 失败
PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_execute_action(
    const char* action_id,
    const char* params,
    char* out_buf, int32_t out_size);
```

#### 能力标志

| 标志 | 值 | 对应函数 |
|---|---|---|
| `PLUGIN_CAP_TEMPLATE_MATCH` | `1 << 0` | `plugin_template_match` |
| `PLUGIN_CAP_OCR` | `1 << 1` | `plugin_ocr` |
| `PLUGIN_CAP_OBJECT_DETECT` | `1 << 2` | （预留） |
| `PLUGIN_CAP_COLOR_MATCH` | `1 << 3` | （预留） |
| `PLUGIN_CAP_CUSTOM` | `1 << 8` | `plugin_execute_action` |

可组合使用：`capabilities = PLUGIN_CAP_TEMPLATE_MATCH | PLUGIN_CAP_OCR`

#### 结果结构体

```c
// 模板匹配结果
typedef struct {
    int32_t x;       // 匹配位置 X
    int32_t y;       // 匹配位置 Y
    int32_t width;   // 匹配宽度
    int32_t height;  // 匹配高度
    double  score;   // 匹配分数 [0, 1]
} PluginMatchResult;

// OCR 行结果
typedef struct {
    char    text[256]; // 识别文本
    int32_t x, y, width, height; // 位置
} PluginOcrLine;

// OCR 结果
typedef struct {
    PluginOcrLine lines[64]; // 最多 64 行
    int32_t       line_count;
    int32_t       total_x, total_y, total_width, total_height;
} PluginOcrResult;
```

### 构建与打包

#### Windows (MSVC)

```bash
cd src
build_windows.bat my_plugin
# 输出: ../windows/my_plugin.dll
```

需要安装 Visual Studio 并包含 C++ 桌面开发工具。

#### Linux / macOS

```bash
cd src
chmod +x build_unix.sh
./build_unix.sh my_plugin
# Linux 输出: ../linux/my_plugin.so
# macOS 输出: ../darwin/my_plugin.dylib
```

#### 手动编译

```bash
# Windows
cl /LD /O2 main.c /I. /Fe:../windows/my_plugin.dll

# Linux
gcc -shared -fPIC -O2 main.c -I. -o ../linux/my_plugin.so

# macOS
clang -shared -fPIC -O2 main.c -I. -o ../darwin/my_plugin.dylib
```

#### 打包发布

将插件目录打包为 zip（不包含 src/）：

```
my_plugin.zip
├── manifest.json
├── windows/my_plugin.dll
├── linux/my_plugin.so
└── darwin/my_plugin.dylib
```

---

## 视觉插件接口

视觉插件实现 `VisionPlugin` 抽象类（`lib/services/vision_plugin.dart`），用于图像识别场景。

### 能力类型

```dart
enum VisionCapability {
  templateMatch,  // 图像模板匹配
  ocr,            // OCR 文字识别
  objectDetect,   // 目标检测
  colorMatch,     // 颜色匹配
}
```

### 实现示例

```dart
class MyVisionPlugin extends VisionPlugin {
  @override
  late final VisionPluginInfo info = VisionPluginInfo(
    id: 'my_vision',
    name: '我的视觉插件',
    description: '自定义视觉识别',
    capabilities: [VisionCapability.templateMatch, VisionCapability.ocr],
    isBuiltin: false,
  );

  @override
  bool get isAvailable => _initialized;
  bool _initialized = false;

  @override
  Future<bool> initialize() async {
    // 加载模型等
    _initialized = true;
    return true;
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
  }

  @override
  Future<List<VisionMatchResult>> findTemplate({
    required int regionX, required int regionY,
    required int regionW, required int regionH,
    required Uint8List templatePixels,
    required int templateWidth, required int templateHeight,
    double threshold = 0.8, int maxResults = 1,
  }) async {
    // 实现模板匹配
    return [];
  }

  @override
  Future<VisionOcrResult> recognizeText({
    required int x, required int y,
    required int w, required int h,
    String language = 'zh-Hans-CN',
  }) async {
    // 实现 OCR
    return const VisionOcrResult(text: '');
  }
}
```

### 注册视觉插件

```dart
VisionPluginManager.instance.registerPlugin(MyVisionPlugin());
```

---

## 插件生命周期

```
注册 → 安装 → 启用(初始化) → 运行 → 禁用(释放) → 卸载
 │      │        │              │        │           │
 │      │        │              │        │           └─ onUninstall()
 │      │        │              │        └─ dispose() + 禁用
 │      │        └─ initialize()
 │      └─ installed = true
 └─ registerPlugin()
```

- **注册**：应用启动时注册到 `PluginRegistry`
- **安装**：用户从插件商店安装，状态持久化到 `plugin_state.json`
- **启用**：调用 `initialize()`，加载资源，页面出现在导航栏
- **禁用**：调用 `dispose()`，释放资源，从导航栏移除
- **卸载**：对原生插件，删除插件目录；对 Dart 插件，仅标记未安装

---

## 安装与分发

### 方式一：插件商店（推荐）

将插件 zip 上传，更新 `plugins/plugin_index.json`，用户在应用内一键安装。

### 方式二：手动安装 zip

1. 在 Clicker 插件中心点击「安装插件」
2. 选择 zip 文件
3. 插件自动解压到插件目录

### 方式三：直接放入插件目录

1. 在插件中心点击「插件目录」打开文件夹
2. 将插件目录放入其中
3. 重启应用，插件自动发现

---

## 插件商店

插件商店通过远程 JSON 索引分发插件。索引文件：`plugins/plugin_index.json`

### 索引格式

```json
{
  "version": 1,
  "updated": "2025-01-01",
  "plugins": [
    {
      "id": "com.example.my_plugin",
      "name": "我的插件",
      "version": "1.0.0",
      "author": "作者",
      "description": "插件描述",
      "category": "extension",
      "platforms": ["windows"],
      "type": "native",
      "size": 1048576,
      "downloadUrl": "https://example.com/my_plugin.zip",
      "minAppVersion": 1
    },
    {
      "id": "my_dart_plugin",
      "name": "Dart 插件",
      "version": "1.0.0",
      "type": "dart",
      "dartPluginId": "my_dart_plugin",
      "platforms": ["windows", "linux", "macos"]
    }
  ]
}
```

**type 字段：**
- `"dart"` — 内置 Dart 插件，`dartPluginId` 对应 `PluginRegistry` 中的 ID
- `"native"` — 原生插件，`downloadUrl` 为 zip 下载地址

### 自定义商店地址

可在应用设置中修改商店索引 URL，默认指向 GitHub 仓库。

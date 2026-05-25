# Clicker Plugin SDK

## 插件包格式

```
my_plugin/
├── manifest.json          # 插件元数据
├── windows/
│   └── my_plugin.dll      # Windows 原生库
├── linux/
│   └── my_plugin.so       # Linux 原生库
├── darwin/
│   └── my_plugin.dylib    # macOS 原生库
└── src/                   # 源代码（可选，不打包进发布版）
    ├── clicker_plugin.h   # SDK 头文件
    ├── main.c             # 插件实现
    ├── build_windows.bat  # Windows 构建脚本
    └── build_unix.sh      # Linux/macOS 构建脚本
```

## manifest.json 格式

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

## 分类 (category)

| 值 | 中文 | 说明 |
|---|---|---|
| core | 核心 | 核心功能 |
| click | 点击增强 | 连点相关增强 |
| vision | 图像识别 | 图像/文字识别 |
| automation | 自动化 | 自动化任务 |
| ui | 界面 | 界面主题等 |
| extension | 扩展 | 其他扩展 |

## 必须实现的函数

- `plugin_get_info()` — 返回插件元数据
- `plugin_initialize()` — 初始化插件
- `plugin_dispose()` — 释放资源

## 可选实现的函数

- `plugin_template_match()` — 图像模板匹配
- `plugin_ocr()` — OCR 文字识别
- `plugin_execute_action()` — 自定义动作

## 构建方法

### Windows (MSVC)
```bash
cd src
build_windows.bat my_plugin
```

### Linux / macOS
```bash
cd src
chmod +x build_unix.sh
./build_unix.sh my_plugin
```

## 安装插件

1. 将编译好的插件目录打包为 `.zip`
2. 在 Clicker 插件中心点击「安装插件」选择 zip 文件
3. 或直接将插件目录放入插件目录（在插件中心点击「插件目录」打开）

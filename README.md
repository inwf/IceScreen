# IceScreen

将任意 macOS 窗口或局部区域变成跨桌面空间的浮窗。SwiftUI 设置、AppKit 浮窗、ScreenCaptureKit 捕获、Metal 显示。macOS 26 使用原生 Liquid Glass，macOS 14–15 使用系统材质。

支持 macOS 14 Sonoma 及以上，Apple Silicon 和 Intel。GPL-3.0-or-later，全部功能免费，无账号、联网授权、使用时长限制和遥测。

## 构建与启动

需要 macOS 和 Xcode 26+，并选择对应工具链：

```bash
swift test
bash scripts/build.sh
open dist/IceScreen.app
```

构建同时生成 `dist/IceScreen.app` 和 `dist/IceScreen-macOS.dmg`。打开 DMG 后，将 IceScreen 拖到「Applications（应用程序）」安装。

本地交付目录中的 DMG 与 ZIP 包含交叉编译通用应用，使用 ad-hoc 签名，尚未完成 macOS 实机与 Apple 签名验证。可以在 Mac 上执行上述命令生成并验证本机应用包。

生成通用应用：

```bash
UNIVERSAL=1 bash scripts/build.sh
```

已有应用包可单独生成 DMG：

```bash
bash scripts/package-dmg.sh
```

构建脚本生成图标、应用包、本地签名和压缩 DMG，并执行映像校验。发布者可设置 `SIGN_IDENTITY` 使用自己的 Developer ID；公证需要发布者的 Apple 开发者凭据。CI 会编译、测试并保存通用应用 DMG 与 ZIP。

首次启动，在设置中允许「屏幕录制」和「辅助功能」，聚焦需要捕获的来源窗口，再按 `fn + P`。辅助功能用于全局按键和定位来源窗口；系统可能同时要求输入监控权限。授权后按 macOS 提示重新启动应用。正式使用时将应用放到 `/Applications`，保持路径稳定。

## 使用

菜单栏菜单提供捕获、浮窗操作、设置和退出。设置分为通用、浮窗、捕获、操作和关于。关闭设置后，应用继续在菜单栏运行。

| 操作 | 效果 |
| --- | --- |
| `fn + P`（默认，可自定义） | 捕获当前窗口 |
| `fn + Shift + P`（默认，可独立设置） | 框选当前窗口区域 |
| 按住触发修饰键并双击来源窗口 | 捕获鼠标附近的放大区域 |
| 拖动浮窗 | 移动位置 |
| 拖动浮窗边缘 | 保持内容比例调整尺寸 |
| 双击浮窗内容 | 聚焦来源窗口并关闭浮窗 |
| 单击浮窗内容（可开启） | 聚焦来源窗口并保留浮窗 |
| `⌘` + 拖动浮窗内容 | 框选并放大 |
| `⌘` + 双击 | 恢复完整画面 |
| 滚动 | 平移已放大的画面 |
| `⌘` + 滚动 | 以鼠标位置为中心缩放 |
| 触控板捏合 | 以鼠标位置为中心缩放 |
| 悬停后轻按 `Space` | 保持来源窗口预览；再次按下或按 Esc 关闭 |
| 悬停后长按 `Space` | 临时预览，松开关闭 |
| 悬停后按 `=` / `-` | 放大 / 缩小 |
| 悬停后按 `F` | 打开应用帧率菜单 |
| 悬停后按 `D`，或点击状态点 | 切换内容空闲检测 |
| 悬停后轻按触发修饰键 | 隐藏；再次轻按恢复最近隐藏的浮窗 |
| 悬停后双击触发修饰键 | 开关自动隐藏；透明时也有效 |
| 悬停后按 `Delete` | 关闭浮窗，透明时也有效 |

触发修饰键默认 `fn`，可在设置中改为 `⇧`、`⌃`、`⌥` 或 `⌘`。捕获快捷键支持这些修饰键组合，包括 `⌘⇧I`；自动区域快捷键会添加一个尚未使用的修饰键，例如 `⌥⇧⌘I`。重复组合会显示冲突提示。

手动隐藏会停止捕获，60 秒后关闭浮窗。自动隐藏在鼠标进入时淡出并穿透鼠标事件，鼠标离开后恢复。鼠标位于原浮窗位置时，双击触发修饰键关闭自动隐藏，即可恢复点击关闭按钮和操作菜单。菜单栏也可以管理每个浮窗。

`fn` / 地球键可以在系统设置 → 键盘中设为「不执行操作」，避免同时触发系统动作。部分系统保护内容、DRM 视频或已经最小化的窗口可能无法提供正常画面。

## 性能设置

- 帧率支持 1、5、10、15、24、30、60 FPS，按应用保存。日志和终端建议 1–5 FPS，视频建议 30–60 FPS。
- 默认 10 FPS；捕获分辨率跟随浮窗大小和显示器缩放比例，最长边上限为 4096 像素。
- 自动隐藏、手动隐藏、暂停和系统休眠时停止捕获。
- 使用一个最新帧槽位合并显示请求，GPU 最多允许两个未完成命令，限制积压。
- 空闲检测每秒最多分析 32 × 32 个亮度采样；关闭时停止采样。
- 图像增强使用 GPU 过滤器。需要最低功耗时，可以关闭图像增强和空闲检测。

性能设计与实测状态见 [验证记录](docs/validation.md)。

## 命令行

```bash
/Applications/IceScreen.app/Contents/MacOS/IceScreen --help
/Applications/IceScreen.app/Contents/MacOS/IceScreen --app Terminal
/Applications/IceScreen.app/Contents/MacOS/IceScreen --app Terminal --window "build" --zoom bottom-left:5x
/Applications/IceScreen.app/Contents/MacOS/IceScreen --window 12345 --region
```

| 参数 | 说明 |
| --- | --- |
| `--app NAME` | 应用名称子串或完整 bundle ID，不区分大小写 |
| `--window TITLE_OR_ID` | 标题子串或准确的数字窗口 ID |
| `--zoom POSITION:FACTOR` | 初始放大倍率 1–32，例如 `center:2x` |
| `--region` | 打开交互式区域选择 |
| `--help` | 输出参数说明 |

`POSITION` 支持 `top-left`、`top`、`top-right`、`left`、`center`、`right`、`bottom-left`、`bottom`、`bottom-right`。标题匹配多个窗口时，需要同时指定应用或改用数字窗口 ID。

应用已经运行时，命令传给现有实例；接收确认超时返回非零退出码。接收确认代表请求送达，捕获授权或窗口匹配错误通过设置窗口显示。

## 开发

```bash
swift test
CONFIGURATION=debug bash scripts/build.sh
```

`IceCore` 包含跨平台的坐标、命令行、偏好和空闲检测逻辑。Linux 可以运行 `swift test`；完整桌面应用的编译、签名和交互验证需要 macOS。

参见 [功能清单](docs/features.md)、[实现说明](docs/architecture.md)、[验证记录](docs/validation.md) 和 [贡献说明](CONTRIBUTING.md)。

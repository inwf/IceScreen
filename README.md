# IceScreen

将任意 macOS 窗口或局部区域变成跨桌面空间的浮窗。原生 Swift / AppKit 界面，ScreenCaptureKit 捕获，Metal 显示。

支持 macOS 14 Sonoma 及以上，Apple Silicon 和 Intel。GPL-3.0-or-later，全部功能免费，无账号、联网授权、使用时长限制和遥测。

## 构建与启动

需要 macOS 和 Xcode 15+ 或对应的 Command Line Tools：

```bash
swift test
bash scripts/build.sh
open dist/IceScreen.app
```

本地交付目录中的 `dist/IceScreen-macOS.zip` 为交叉编译通用应用包，使用 ad-hoc 签名，尚未完成 macOS 实机与 Apple 签名验证。可以在 Mac 上执行上述命令生成并验证本机应用包。

生成通用应用：

```bash
UNIVERSAL=1 bash scripts/build.sh
```

构建脚本生成图标、应用包和本地签名。发布者可设置 `SIGN_IDENTITY` 使用自己的 Developer ID；公证需要发布者的 Apple 开发者凭据。CI 会编译、测试并保存通用应用 ZIP。

首次启动，在控制中心允许「屏幕录制」和「辅助功能」，再选择一个窗口点击「悬浮」。辅助功能用于全局按键和定位来源窗口；系统可能同时要求输入监控权限。授权后按 macOS 提示重新启动应用。正式使用时将应用放到 `/Applications`，保持路径稳定。

## 使用

菜单栏图标打开控制中心；右键菜单提供快捷捕获、关闭全部浮窗和退出。关闭控制中心后，应用继续在菜单栏运行。

| 操作 | 效果 |
| --- | --- |
| `⌃⌥Space`（默认，可自定义） | 捕获当前窗口 |
| 在捕获快捷键中增加 `Shift` | 框选当前窗口区域 |
| 按住 `fn` 双击来源窗口 | 捕获鼠标附近的放大区域 |
| 拖动浮窗 | 移动位置 |
| 拖动浮窗边缘 | 保持内容比例调整尺寸 |
| 双击浮窗内容 | 聚焦来源窗口 |
| `⌘` + 拖动浮窗内容 | 框选并放大 |
| `⌘` + 双击 | 恢复完整画面 |
| 滚动 | 平移已放大的画面 |
| `⌘` + 滚动 | 以鼠标位置为中心缩放 |
| 悬停后按 `=` / `-` | 放大 / 缩小 |
| 悬停后按 `F` | 切换应用帧率 |
| 悬停后按 `D`，或点击状态点 | 切换内容空闲检测 |
| 悬停后轻按 `fn` | 隐藏；再次轻按恢复最近隐藏的浮窗 |
| 悬停后按 `Delete` | 关闭浮窗 |

手动隐藏会停止捕获，60 秒后关闭浮窗。自动隐藏在鼠标进入时淡出并穿透鼠标事件，鼠标离开后恢复。可通过控制中心关闭自动隐藏、恢复浮窗和调整每个浮窗的设置。

`fn` / 地球键可以在系统设置 → 键盘中设为「不执行操作」，避免同时触发系统动作。部分系统保护内容、DRM 视频或已经最小化的窗口可能无法提供正常画面。

## 性能设置

- 帧率支持 1、5、10、15、24、30、60 FPS，按应用保存。日志和终端建议 1–5 FPS，视频建议 30–60 FPS。
- 默认 15 FPS；捕获分辨率跟随浮窗大小和显示器缩放比例，最长边上限为 4096 像素。
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

`POSITION` 支持 `top-left`、`top`、`top-right`、`left`、`center`、`right`、`bottom-left`、`bottom`、`bottom-right`。标题匹配多个窗口时，需要同时指定应用或改用数字窗口 ID。窗口 ID 显示在控制中心中。

应用已经运行时，命令传给现有实例；接收确认超时返回非零退出码。接收确认代表请求送达，捕获授权或窗口匹配错误通过控制中心显示。

## 开发

```bash
swift test
CONFIGURATION=debug bash scripts/build.sh
```

`IceCore` 包含跨平台的坐标、命令行、偏好和空闲检测逻辑。Linux 可以运行 `swift test`；完整桌面应用的编译、签名和交互验证需要 macOS。

参见 [功能清单](docs/features.md)、[实现说明](docs/architecture.md)、[验证记录](docs/validation.md) 和 [贡献说明](CONTRIBUTING.md)。

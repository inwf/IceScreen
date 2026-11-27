# 参与开发

[English](CONTRIBUTING.md) · 简体中文

## 构建

IceScreen 使用 Swift Package Manager。`IceCore` 包含与平台无关的坐标、命令行、偏好设置和内容检测逻辑，`swift test` 可以在 Linux 上运行。完整应用的编译、签名和交互验证需要 macOS、Xcode 26 或更新版本、uv 和 Cairo（`brew install cairo`）。

| 命令 | 结果 |
| --- | --- |
| `swift test` | 运行核心逻辑测试 |
| `bash scripts/build.sh` | 生成当前架构的 `dist/IceScreen.app` 和 `dist/IceScreen-macOS.dmg` |
| `UNIVERSAL=1 bash scripts/build.sh` | 生成支持 Apple Silicon 和 Intel 的通用应用 |
| `CONFIGURATION=debug bash scripts/build.sh` | 生成调试版本 |
| `bash scripts/package-dmg.sh` | 从已有的 `dist/IceScreen.app` 生成 DMG |

构建默认使用 ad-hoc 签名。设置 `SIGN_IDENTITY` 后，应用和 DMG 使用指定的 Developer ID 签名；公证需要发布者自己的 Apple 开发者凭据。

## 检查

修改前阅读 [README](README.zh-CN.md)，运行 `swift test`。macOS 相关改动还需执行 `bash scripts/build.sh`。

输入与浮窗改动还需在 macOS 图形会话中运行 `bash scripts/check-panel-events.sh`。该检查以原生应用包启动，创建独立前台应用，验证后台浮窗的 WindowServer 命中、前后顺序、鼠标穿透、隐藏，以及 AppKit 分发点击后前台进程与非关键窗口状态保持原值；随后执行活动应用中的控件与渲染检查。任何断言失败或缺少完成记录都会返回失败。AppKit 队列中的受控事件不代表硬件输入、系统权限或来源定位已完成验收。

检测命令相关改动还需运行 `python3 scripts/check-detection-command.py .build/debug/IceScreen`，验证真实命令执行和子进程清理。

CI 检查核心逻辑、图标与安装背景、原生浮窗事件、检测命令、媒体辅助进程和安装包。屏幕录制权限、真实来源窗口定位、硬件手势、多显示器，以及 CPU、内存和功耗测量仍需在实际 Mac 上验证，CI 通过不包含这些检查。

性能相关改动应记录设备和来源内容，使用 Release 构建测量 CPU、内存和帧更新。捕获过程中避免每帧创建图片对象、无限增加回调或增加后台轮询。

## 图标

应用图标原图为 `assets/AppIcon.png`。`scripts/make-icon.swift` 从原图生成 16–1024 像素的标准及 Retina 图标，供 Finder、程序坞、「关于」页面和 DMG 卷图标共用。菜单栏图标由 `MenuBarIcon.swift` 绘制为模板图标，由系统适配深浅色。

图标相关改动还需执行 `uv run scripts/test-app-icon.py`。构建中的 `check-app-icon.py` 使用 ICNS 解码库检查全部十种普通与 Retina 表示，包括系统 ARGB、PNG 和旧版 RGB/掩码格式；缺少表示、像素变化、尺寸错误或文件损坏都返回失败。

## 安装窗口背景

安装窗口背景源文件为 `assets/dmg-background.svg`，字体为 `assets/fonts/NotoSansSC-Installation.ttf`。渲染需要 Python 3.11 或更新版本、uv 和 Cairo。脚本依赖由 uv 安装，字体由项目直接加载。

```bash
uv run scripts/test-dmg-background.py
uv run scripts/render-dmg-background.py
uv run scripts/render-dmg-background.py --check
```

Retina TIFF 生成到 `.build/dmg-background.tiff`，无需提交。检查会验证格式、尺寸、DPI、字符覆盖、文字边界和全部像素；生成与检查使用同一构建环境。`scripts/package-dmg.sh` 每次打包都会生成并严格检查背景，通过 Finder 设置布局，再重新挂载最终 DMG，验证背景内容、图标、别名和窗口布局。手动验证本次构建的挂载映像可执行 `uv run scripts/check-dmg-layout.py /Volumes/IceScreen`。

## 提交

提交应说明用户可观察的行为、验证方式和平台版本。图形捕获、权限、多屏和输入处理改动需要记录实际设备验证结果。请勿把模拟结果标记为实机结果。

修改用户可见的行为时，同步更新 `README.md` 和 `README.zh-CN.md`；修改开发流程时，同步更新本文件和 `CONTRIBUTING.md`。

开发中的变更记在 `CHANGELOG.md` 的 `Unreleased` 下。每个版本先写完整英文，用 `---` 分隔后写完整简体中文。两部分使用对应的分类和相同的条目顺序，只列有内容的分类，如 `### Added` 对应 `### 新增`、`### Fixed` 对应 `### 修复`。发版前可运行 `python3 scripts/release-notes.py --tag vX.Y.Z` 预览指定版本的 Release 正文。

## 排查 Actions

先看作业是否已分配 runner。若因容量不足一直未获分配，恢复后重跑原提交即可。若测试已执行，先用失败分组的日志、本地单测与构建定位。仅当疑点取决于 macOS 图形会话且本地无法复现时，再提供同一提交的离线实机检查包。包内验证签名，用与 CI 相同的脚本分组、分进程运行，记录系统版本、架构、每组日志和退出状态。窗口几何断言使用系统布局后的实际窗口尺寸。一次回传完整报告，按失败分组复查。

## 发布流程

- `main` 分支的 push 执行测试，构建通用应用，校验 DMG 和 ZIP，并在 Actions 中保留构建产物十四天。其他分支的 push 不触发工作流。
- Pull Request 只执行同样的检查，不发布版本。
- 推送 `vX.Y.Z` 标签后，工作流查找同一提交上成功且未过期的 `main` 构建产物；找到后直接复用，找不到则重新测试和构建。检查通过后创建 GitHub Release，上传通用 DMG、ZIP 和 `SHA256SUMS`。
- Release 正文取自 `CHANGELOG.md` 中与标签对应的版本。标签必须与 `Info.plist` 中的 `CFBundleShortVersionString` 一致。
- 在 Actions 页面手动运行时填写已有的 `vX.Y.Z` 标签，按相同规则复用或重新构建产物并更新该 Release；留空则只执行检查。

发布新版本时，先更新 `Sources/IceScreen/Resources/Info.plist` 和 `CHANGELOG.md`，推送到 `main` 并确认检查通过，再创建并推送对应标签：

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

## 许可证

代码和文档采用 GPL-3.0-or-later。提交即表示你有权按这一许可证贡献相应内容。

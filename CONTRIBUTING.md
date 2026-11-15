# 参与开发

IceScreen 使用 Swift Package Manager。修改前阅读 README，运行 `swift test`。macOS 相关改动还需执行 `bash scripts/build.sh`。输入与浮窗改动还需在 macOS 图形会话中运行 `bash scripts/check-panel-events.sh`。

检测命令相关改动还需运行 `python3 scripts/check-detection-command.py .build/debug/IceScreen`，验证真实命令执行和子进程清理。

安装窗口背景源文件为 `assets/dmg-background.svg`，字体为 `assets/fonts/NotoSansSC-Installation.ttf`。渲染需要 Python 3.11 或更新版本、uv 和 Cairo（macOS 可执行 `brew install cairo`）。脚本依赖由 uv 安装，字体由项目直接加载。

```bash
uv run scripts/test-dmg-background.py
uv run scripts/render-dmg-background.py
uv run scripts/render-dmg-background.py --check
```

Retina TIFF 生成到 `.build/dmg-background.tiff`，无需提交。检查会验证格式、尺寸、DPI、字符覆盖、文字边界和全部像素；生成与检查使用同一构建环境。`scripts/package-dmg.sh` 每次打包都会生成并严格检查背景，通过 Finder 设置布局，再重新挂载最终 DMG，验证背景内容、图标、别名和窗口布局。手动验证本次构建的挂载映像可执行 `uv run scripts/check-dmg-layout.py /Volumes/IceScreen`。

提交应说明用户可观察的行为、验证方式和平台版本。图形捕获、权限、多屏和输入处理改动需要记录实际设备验证结果。请勿把模拟结果标记为实机结果。

性能相关改动应记录设备和来源内容，使用 Release 构建测量 CPU、内存和帧更新。捕获过程中避免每帧创建图片对象、无限增加回调或增加后台轮询。

代码和文档采用 GPL-3.0-or-later。提交即表示你有权按这一许可证贡献相应内容。

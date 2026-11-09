# 参与开发

IceScreen 使用 Swift Package Manager。修改前阅读 [实现说明](docs/architecture.md)，运行 `swift test`。macOS 相关改动还需执行 `bash scripts/build.sh`。输入与浮窗改动还需在 macOS 图形会话中运行 `bash scripts/check-panel-events.sh`。

检测命令相关改动还需运行 `python3 scripts/check-detection-command.py .build/debug/IceScreen`，验证真实命令执行和子进程清理。macOS 手动检查步骤见 [检查清单](docs/macos-checklist.md)。

提交应说明用户可观察的行为、验证方式和平台版本。图形捕获、权限、多屏和输入处理改动需要记录实际设备验证结果。请勿把模拟结果标记为实机结果。

性能相关改动应记录设备和来源内容，使用 Release 构建测量 CPU、内存和帧更新。捕获过程中避免每帧创建图片对象、无限增加回调或增加后台轮询。

代码和文档采用 GPL-3.0-or-later。提交即表示你有权按这一许可证贡献相应内容。

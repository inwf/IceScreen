# Changelog

## 1.2.5 — 2026-11-14

### Fixed

- 应用包、DMG 卷图标和 ZIP 中的图标统一使用新的 IceScreen logo。
- 应用启动时更新当前包的 Launch Services 注册信息，减少系统录屏提示继续显示旧图标的情况。
- 构建过程重新创建应用包，避免旧资源残留。

### Build and release

- 构建流程检查原图 SHA256、唯一 ICNS 资源、全部标准及 Retina 尺寸和图像像素。
- GitHub Release 自动附带通用 macOS DMG、ZIP、SHA256 校验文件和本节 changelog。

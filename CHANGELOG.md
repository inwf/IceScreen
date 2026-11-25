# Changelog

## Unreleased

### Fixed

- Preserve each panel's detection wait times when resizing panels or changing unrelated settings. Updating a global wait time changes only the matching detection threshold.

---

### 修复

- 调整浮窗尺寸或修改其他设置时，保留各浮窗单独设置的检测等待时间。修改全局等待时间时，仅更新对应的检测阈值。

## 1.2.14 — 2026-11-23

### Fixed

- Refresh Launch Services registration when the application icon changes without a version or installation path change.

---

### 修复

- 应用版本号和安装路径未变化时，图标内容变化也会刷新 Launch Services 注册信息。

## 1.2.13 — 2026-11-22

### Added

- Hover over a panel to see its source app name, without the window title or region number.

### Fixed

- Pressing the region shortcut again cancels a pending or visible selection without starting another one.

---

### 新增

- 悬停浮窗时显示来源应用名称，不附加窗口标题或区域编号。

### 修复

- 区域选择准备中或选框已显示时，再按一次区域快捷键只取消，不会重新打开选框。

## 1.2.12 — 2026-11-20

### Changed

- Hover playback buttons grow with the panel and stop at a comfortable size. Play/pause is larger than the track buttons on roomier panels.
- Appearance previews the normal, hidden, or hover state while you adjust its transparency or edge shading, including keyboard adjustments and resets. The preview returns to pointer control after one second.

### Removed

- Removed manual temporary hiding, its restore action, and its 60-second auto-close timer. Auto-hide on hover is unchanged.

### Fixed

- Returning to a closed source window now reports that it has closed when macOS retains its offscreen record on the active desktop.

---

### 变更

- 悬停时的媒体按钮随浮窗平滑放大，到达上限后保持不变。空间充足时，播放／暂停键比上一首和下一首更大。
- 在外观页调整普通透明度、隐藏时透明度或边缘阴影时，预览会显示对应状态。键盘微调和恢复默认值也会触发预览，结束一秒后恢复鼠标控制。

### 移除

- 移除浮窗的手动「暂时隐藏」、恢复入口和 60 秒后自动关闭的逻辑。鼠标移入时自动隐藏不变。

### 修复

- 来源窗口关闭后，即使 macOS 在当前桌面保留了它的离屏记录，尝试返回时也会提示窗口已关闭。

## 1.2.11 — 2026-11-19

### Added

- With multiple panels enabled, selecting or quick-capturing regions of the same window creates independent, numbered panels. The window capture shortcut toggles only the whole-window panel.

### Changed

- On macOS 26 and later, the Settings sidebar uses the system backdrop. Floating-panel hints and status messages use clear Liquid Glass, with a solid background when Reduce Transparency or Increase Contrast is enabled.
- Double-tapping the trigger modifier over a panel, choosing auto-hide from its menu, and changing the Appearance switch now update the same saved setting for all panels.
- A single modifier tap no longer hides or restores a panel. The menu still offers temporary hiding.
- Space previews expand from the floating panel, briefly travel past the center in the same direction, then settle back. Cropped panels reveal the full image; closing returns to the panel. Reduce Motion keeps a short fade.

### Fixed

- Hints such as “Auto-hide disabled” move with their floating panel during a drag instead of catching up afterward.

---

### 新增

- 开启多窗口模式后，可在同一窗口反复框选或快速捕获区域，生成独立编号的浮窗。整窗捕获快捷键只切换整窗浮窗。

### 变更

- 在 macOS 26 及以上版本，设置侧栏使用系统背景，浮窗提示和状态消息采用清透的液态玻璃。开启系统「减少透明度」或「增强对比度」后，提示改用实色背景。
- 在浮窗上双击触发修饰键、使用右键菜单或更改外观设置，现在切换的是同一个自动隐藏开关，对所有浮窗生效，并在重启后保留。
- 单击修饰键不再隐藏或恢复浮窗；仍可从菜单手动暂时隐藏浮窗。
- 空格预览从浮窗所在位置展开，沿来路轻微越过中心再回落。裁剪区域会逐渐展开为完整画面，关闭时收回浮窗。开启「减少动态效果」时仅淡入淡出。

### 修复

- 拖动浮窗时，「自动隐藏已关闭」等提示随浮窗一起移动，不再滞后。

## 1.2.10 — 2026-11-19

### Changed

- Both transparency sliders in Appearance now run from 0% (fully opaque) to 100% (fully transparent). The normal panel defaults to 0% and auto-hide to 100%. Upgrading preserves the appearance of existing panels.

### Fixed

- Switching languages now updates all seven settings sidebar labels immediately and keeps the current page selected. Picker options and the quick capture gesture label also follow the selected language.
- The About page displays “happy • 好朋友” in both languages.

### Build and release

- Release notes now group changes by category, with the complete English notes followed by Simplified Chinese.
- The native focus check waits for temporary foreground interruptions to clear and reports the observed process and window IDs on failure.

---

### 变更

- 外观页的两个透明度滑块均从 0%（完全不透明）调到 100%（完全透明）。普通浮窗默认 0%，自动隐藏默认 100%。升级后保留已有浮窗的显示效果。

### 修复

- 切换语言后，设置侧栏的七个页面名称会立即更新，并保留当前选中的页面。选项菜单和快速捕获手势的文字也会随语言切换。
- 关于页在两种语言下都显示「happy • 好朋友」。

### 构建与发布

- 发布说明按变更类型分组，先列出完整英文，再列出对应的完整简体中文。
- 原生焦点检查会等待短暂的前台干扰结束，失败时记录实际观察到的进程和窗口 ID。

## 1.2.9 — 2026-11-18

### Added

- Added a language setting under General with Simplified Chinese and English. Changes apply immediately and persist across launches.
- Localized settings, menus, floating-panel controls and hints, notifications, and app error messages. Existing settings retain Chinese by default.
- Exposed hint and status text and the return-to-source button to macOS accessibility with their on-screen bounds.
- Click a floating panel to focus its source window, then click the same panel again to return to the window you were using. This also works between two windows of the same app. Double-click to focus the source and close the panel.
- Added a link to the project’s GitHub repository in Settings → About.

### Changed

- The settings window and its preview caches are released three minutes after closing, or sooner under memory pressure. Preferences, shortcuts, the selected page, window position, and preview selection are preserved when reopening.

### Fixed

- Centered transient hints over their panel and kept them aligned during movement and resizing. Constrained long messages and separated status text from the return-to-source button in compact panels.
- Pressing the floating panel’s resize handle now sends the drag directly to the handle and keeps the top-left corner anchored.
- The Appearance preview redraws its cached image when reopening the settings window or returning to the tab.

---

### 新增

- 通用设置增加界面语言选项，支持简体中文和英文，切换后立即生效并在下次启动时保留。
- 设置页面、菜单、浮窗控件与操作提示、通知及应用错误信息支持双语。已有配置默认保持中文。
- macOS 辅助功能现在可以读取浮窗提示、状态文字及返回来源按钮，并获取它们在屏幕上的位置。
- 单击浮窗聚焦来源窗口，再单击同一浮窗即可回到刚才使用的窗口。同一应用的两个窗口也能切换。双击会聚焦来源并关闭浮窗。
- 在「设置 → 关于」中加入项目的 GitHub 仓库链接。

### 变更

- 设置关闭三分钟后释放窗口和预览缓存，内存压力升高时提前清理。重新打开会取消清理，保留配置、快捷键、选中的页面、窗口位置及预览选择。

### 修复

- 临时提示在所属浮窗内居中显示，并跟随浮窗移动和缩放；限制长提示的显示范围，避免紧凑浮窗的状态文案与返回来源按钮重叠。
- 按住浮窗右下角的缩放手柄时，由手柄直接接收拖动，调整大小时保持左上角固定。
- 重新打开设置窗口或切回「外观」页时，预览会重绘缓存的画面。

## 1.2.8 — 2026-11-17

### Added

- Added an auto-hide opacity slider in Appearance settings, including for panels toggled by double-tapping the trigger modifier. Visible panels continue updating while allowing clicks through; leaving restores normal opacity.

### Fixed

- Fixed reversed content zoom direction when holding Command and scrolling over a floating panel.

### Build and release

- Added native checks for pixel and line scroll events, covering zoom direction, ordinary panning, panel geometry, and foreground focus.
- Updated checkout, artifact upload/download, and uv setup actions to versions using Node.js 24.

---

### 新增

- 外观设置增加自动隐藏透明度调节，也适用于双击触发修饰键开启自动隐藏的浮窗。保留可见画面时继续更新并允许鼠标穿透，移出后恢复正常透明度。

### 修复

- 修复按住 Command 并在浮窗上滚动时，内容缩放方向相反的问题。

### 构建与发布

- 增加像素滚动和行滚动事件的原生检查，覆盖缩放方向、普通平移、浮窗尺寸与位置以及前台焦点。
- 更新代码检出、构建产物上传与下载及 uv 安装 Action，使用 Node.js 24 运行时。

## 1.2.7 — 2026-11-17

### Fixed

- Clicking a floating panel activates its source app before focusing the captured window on another desktop.
- If Terminal omits its window from the accessibility window list, IceScreen checks the focused window against the captured window ID.
- IceScreen restores a hidden app or minimized window before checking keyboard focus and the active desktop.
- Closing the source window is reported even if macOS temporarily retains an offscreen window record.

### Build and release

- Native checks distinguish window preparation, click delivery, focus completion and the final window state, and record accessibility errors at the failing stage.
- Regression checks cover recorded desktop switches, multiple windows in the same app, window geometry and Space membership. A failed check stops packaging.

---

### 修复

- 点击浮窗返回其他桌面的来源窗口时，先激活来源应用，再定位捕获的具体窗口。
- 终端窗口未出现在辅助功能窗口列表时，从焦点窗口属性中查找并核对原窗口身份。
- 来源应用隐藏或窗口最小化时，先恢复显示，再确认原窗口的键盘焦点和所在桌面。
- 来源窗口关闭后，即使系统暂时保留离屏记录，也能报告已关闭，避免误提示桌面切换超时。

### 构建与发布

- 原生测试分别检查窗口准备、点击送达、焦点操作完成及最终窗口状态，并记录失败阶段和辅助功能错误。
- 增加实际桌面切换记录的回归检查，保留多窗口身份、窗口位置和桌面归属断言；测试失败继续阻止打包发布。

## 1.2.6 — 2026-11-16

### Fixed

- Capture sessions retain the source window’s identity and accessibility object so that clicking its panel from a full-screen Space can return to it.
- When the current desktop omits the source window, IceScreen requests a switch using its verified window ID and confirms that it receives focus.
- IceScreen reports a closed source window or restarted app. Returning to a valid source preserves its position and size.

### Build and release

- macOS CI checks Terminal, full-screen Space switches, background panel clicks and the identity of the focused window. A failed check stops packaging.

---

### 修复

- 捕获会话保留来源窗口身份和辅助功能对象，支持从全屏内容所在桌面点击浮窗返回来源窗口。
- 当前桌面暂时无法枚举来源窗口时，使用已验证的窗口 ID 请求切换，并确认原窗口真正获得焦点。
- 来源窗口关闭或应用重新启动后明确报告失效，返回窗口时保持来源位置和大小。

### 构建与发布

- macOS CI 增加真实终端、全屏桌面切换、后台浮窗点击及来源窗口身份检查；检查失败阻止打包。

## 1.2.5 — 2026-11-14

### Fixed

- The app, DMG volume and ZIP now use the same IceScreen icon.
- At launch, IceScreen refreshes its Launch Services registration after an upgrade or move so macOS can use the current icon in screen recording prompts.
- The build recreates the app bundle to clear stale resources.

### Build and release

- The build verifies the source image’s SHA-256, the single ICNS resource, every standard and Retina size, and the icon pixels.
- GitHub Releases include a universal macOS DMG, a ZIP, SHA-256 checksums and the changelog for that version.

---

### 修复

- 应用包、DMG 卷图标和 ZIP 中的图标统一使用新的 IceScreen logo。
- 应用启动时更新当前包的 Launch Services 注册信息，减少系统录屏提示继续显示旧图标的情况。
- 构建过程重新创建应用包，避免旧资源残留。

### 构建与发布

- 构建流程检查原图 SHA256、唯一 ICNS 资源、全部标准及 Retina 尺寸和图像像素。
- GitHub Release 自动附带通用 macOS DMG、ZIP、SHA256 校验文件和本节 changelog。

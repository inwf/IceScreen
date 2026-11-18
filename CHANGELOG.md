# Changelog

## 1.2.9 — 2026-11-18

### English

- Added a language setting under General with Simplified Chinese and English. Changes apply immediately and persist across launches.
- Localized settings, menus, floating-panel controls and hints, notifications, and app error messages. Existing settings retain Chinese by default.
- Centered transient hints over their panel and kept them aligned during movement and resizing. Constrained long messages and separated status text from the return-to-source button in compact panels.
- Exposed hint and status text and the return-to-source button to macOS accessibility with their on-screen bounds.
- Pressing the floating panel’s resize handle now sends the drag directly to the handle and keeps the top-left corner anchored.
- The settings window and its preview caches are released three minutes after closing, or sooner under memory pressure. Preferences, shortcuts, the selected page, window position, and preview selection are preserved when reopening.
- Click a floating panel to focus its source window, then click the same panel again to return to the window you were using. This also works between two windows of the same app. Double-click to focus the source and close the panel.
- The Appearance preview redraws its cached image when reopening the settings window or returning to the tab.
- Added a link to the project’s GitHub repository in Settings → About.

### 中文

- 通用设置增加界面语言选项，支持简体中文和英文，切换后立即生效并在下次启动时保留。
- 设置页面、菜单、浮窗控件与操作提示、通知及应用错误信息支持双语。已有配置默认保持中文。
- 临时提示在所属浮窗内居中显示，并跟随浮窗移动和缩放；限制长提示的显示范围，避免紧凑浮窗的状态文案与返回来源按钮重叠。
- macOS 辅助功能现在可以读取浮窗提示、状态文字及返回来源按钮，并获取它们在屏幕上的位置。
- 按住浮窗右下角的缩放手柄时，由手柄直接接收拖动，调整大小时保持左上角固定。
- 设置关闭三分钟后释放窗口和预览缓存，内存压力升高时提前清理。重新打开会取消清理，保留配置、快捷键、选中的页面、窗口位置及预览选择。
- 单击浮窗聚焦来源窗口，再单击同一浮窗即可回到刚才使用的窗口。同一应用的两个窗口也能切换。双击会聚焦来源并关闭浮窗。
- 重新打开设置窗口或切回「外观」页时，预览会重绘缓存的画面。
- 在「设置 → 关于」中加入项目的 GitHub 仓库链接。

## 1.2.8 — 2026-11-17

### English

- Added an auto-hide opacity slider in Appearance settings, including for panels toggled by double-tapping the trigger modifier. Visible panels continue updating while allowing clicks through; leaving restores normal opacity.
- Fixed reversed content zoom direction when holding Command and scrolling over a floating panel.
- Added native checks for pixel and line scroll events, covering zoom direction, ordinary panning, panel geometry, and foreground focus.
- Updated checkout, artifact upload/download, and uv setup actions to versions using Node.js 24.

### 中文

- 外观设置增加自动隐藏透明度调节，也适用于双击触发修饰键开启自动隐藏的浮窗。保留可见画面时继续更新并允许鼠标穿透，移出后恢复正常透明度。
- 修复按住 Command 并在浮窗上滚动时，内容缩放方向相反的问题。
- 增加像素滚动和行滚动事件的原生检查，覆盖缩放方向、普通平移、浮窗尺寸与位置以及前台焦点。
- 更新代码检出、构建产物上传与下载及 uv 安装 Action，使用 Node.js 24 运行时。

## 1.2.7 — 2026-11-17

### Fixed

- 点击浮窗返回其他桌面的来源窗口时，先激活来源应用，再定位捕获的具体窗口。
- 终端窗口未出现在辅助功能窗口列表时，从焦点窗口属性中查找并核对原窗口身份。
- 来源应用隐藏或窗口最小化时，先恢复显示，再确认原窗口的键盘焦点和所在桌面。
- 来源窗口关闭后，即使系统暂时保留离屏记录，也能报告已关闭，避免误提示桌面切换超时。

### Build and release

- 原生测试分别检查窗口准备、点击送达、焦点操作完成及最终窗口状态，并记录失败阶段和辅助功能错误。
- 增加实际桌面切换记录的回归检查，保留多窗口身份、窗口位置和桌面归属断言；测试失败继续阻止打包发布。

## 1.2.6 — 2026-11-16

### Fixed

- 捕获会话保留来源窗口身份和辅助功能对象，支持从全屏内容所在桌面点击浮窗返回来源窗口。
- 当前桌面暂时无法枚举来源窗口时，使用已验证的窗口 ID 请求切换，并确认原窗口真正获得焦点。
- 来源窗口关闭或应用重新启动后明确报告失效，返回窗口时保持来源位置和大小。

### Build and release

- macOS CI 增加真实终端、全屏桌面切换、后台浮窗点击及来源窗口身份检查；检查失败阻止打包。

## 1.2.5 — 2026-11-14

### Fixed

- 应用包、DMG 卷图标和 ZIP 中的图标统一使用新的 IceScreen logo。
- 应用启动时更新当前包的 Launch Services 注册信息，减少系统录屏提示继续显示旧图标的情况。
- 构建过程重新创建应用包，避免旧资源残留。

### Build and release

- 构建流程检查原图 SHA256、唯一 ICNS 资源、全部标准及 Retina 尺寸和图像像素。
- GitHub Release 自动附带通用 macOS DMG、ZIP、SHA256 校验文件和本节 changelog。

<div align="center">
  <img src="assets/AppIcon.png" alt="IceScreen icon" width="96" height="96" />
  <h1>IceScreen</h1>
  <p><strong>Keep the windows you care about in view.</strong></p>
  <p>Turn any macOS window, or part of one, into a floating panel that stays on top across Spaces.<br />Watch builds, logs, video, and progress bars while you work in another app.</p>
  <p>
    <a href="#quick-start"><strong>Quick start</strong></a> ·
    <a href="#shortcuts-and-gestures">Shortcuts</a> ·
    <a href="#content-detection">Detection</a> ·
    <a href="#command-line">Command line</a> ·
    <a href="#troubleshooting">Troubleshooting</a> ·
    <a href="README.zh-CN.md">简体中文</a>
  </p>
  <p>
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0--or--later-3b7c57?style=flat-square" alt="GPL-3.0-or-later" /></a>
    <a href="#1-install"><img src="https://img.shields.io/badge/macOS-14%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 14 or later" /></a>
    <a href="#1-install"><img src="https://img.shields.io/badge/Apple%20Silicon%20%7C%20Intel-Universal-555555?style=flat-square" alt="Universal app for Apple Silicon and Intel" /></a>
    <a href="https://github.com/inwf/IceScreen/releases/latest"><img src="https://img.shields.io/github/v/release/inwf/IceScreen?style=flat-square" alt="Latest release" /></a>
  </p>
</div>


## Built for windows you need to keep an eye on

Click a window and press `fn + P`. IceScreen shows it in a small floating panel that stays above other windows, appears on every Space, and keeps updating live. Click the panel to jump to the source window, then click it again to go back to what you were doing.

IceScreen lives in the menu bar and is built with SwiftUI, AppKit, and ScreenCaptureKit. Every feature is free, with no account, online activation, time limit, or telemetry.

<table>
  <tr>
    <td width="33%" valign="top">
      <h3>Window or region</h3>
      Capture a whole window, drag to select part of it, or hold <code>fn</code> and double-click an image, video, table, or text area to capture just that element.
    </td>
    <td width="33%" valign="top">
      <h3>Always in view</h3>
      Panels float above other windows on every Space, including full-screen apps. Hold <code>Space</code> over a panel to preview the full source window.
    </td>
    <td width="33%" valign="top">
      <h3>Zoom into details</h3>
      Pinch, <code>⌘</code>-scroll, or <code>⌘</code>-drag to zoom into one log line or progress bar. Scroll to pan, and press <code>0</code> to see the whole window again.
    </td>
  </tr>
  <tr>
    <td valign="top">
      <h3>Know when it's done</h3>
      Get a notification when content stops changing, or when it changes again after a quiet period. Run your own shell command on either event.
    </td>
    <td valign="top">
      <h3>Media controls</h3>
      Play, pause, skip tracks, and seek from the panel. Tap <code>Space</code> to play or pause, and press <code>←</code> / <code>→</code> to jump 5 seconds.
    </td>
    <td valign="top">
      <h3>Out of your way</h3>
      Auto-hide fades panels when the pointer moves over them and lets clicks reach the window underneath. Each app keeps its own frame rate.
    </td>
  </tr>
</table>

## Quick start

### 1. Install

Requires **macOS 14 Sonoma or later** on **Apple Silicon** or **Intel**.

1. Download **[IceScreen-macOS.dmg](https://github.com/inwf/IceScreen/releases/latest/download/IceScreen-macOS.dmg)** from the [latest release](https://github.com/inwf/IceScreen/releases/latest).
2. Open the DMG and drag IceScreen to **Applications**.
3. Open IceScreen from Applications.

Each release also includes a ZIP of the app and a `SHA256SUMS` file for checking the download.

> [!NOTE]
> IceScreen isn't signed with a paid Apple Developer account. If macOS blocks it, click **Open Anyway** in **System Settings → Privacy & Security**.

### 2. Allow permissions

On first launch, IceScreen opens its settings at **General → System permissions**. Click **Allow…** next to each item and turn IceScreen on in the System Settings page that opens. Restart IceScreen if macOS asks you to.

| Permission | Why IceScreen needs it |
| --- | --- |
| Screen Recording | Shows window contents in panels |
| Accessibility | Global shortcuts, quick capture, and focusing source windows |
| Input Monitoring | Global shortcuts; settings shows a warning if this is missing |
| Notifications | Detection alerts; requested when you first turn on detection |
| Automation | Seeking in Music, TV, Spotify, Swinsian, and VLC; requested the first time you seek |

### 3. Capture your first window

1. Click the window you want to watch, such as a terminal running a build.
2. Press **`fn + P`**. The window appears in a floating panel at the bottom right of the screen.
3. Move the pointer over the panel to show its controls. Press `fn + P` again with the same window in front to close the panel.

> [!TIP]
> IceScreen starts in Simplified Chinese. To switch, open settings from the menu bar icon, choose **通用** (General), and set **界面语言** (App language) to **English**. The change applies immediately.

If pressing `fn` also opens the emoji picker or dictation, set **System Settings → Keyboard → Press 🌐 key to** to **Do Nothing**, or choose another modifier under **Settings → Shortcuts**.

## Ways to capture

| Method | Default | What you get |
| --- | --- | --- |
| Capture window | `fn + P` | A panel showing the whole front window |
| Capture region | `fn + Shift + P` | Drag over the front window to choose an area. `Esc`, a right-click, or the shortcut again cancels. |
| Quick region capture | Hold `fn` and double-click | The image, video, table, or text area under the pointer, with symmetric black or white bars trimmed off |
| Menu bar | IceScreen icon | **Capture current window** and **Capture region** |

Quick region capture combines the element under the pointer with rectangle detection on a single screenshot. With **Detect content boundaries during quick capture** turned off under **Settings → Panels**, it zooms into the area around the pointer instead. While you hold the quick capture modifiers, a single click reaches the app after the system double-click interval and drags pass through immediately.

By default each new capture replaces the current panel. Turn on **Allow multiple panels** under **Settings → Panels** to keep several panels open. Region panels from the same window are then numbered Region 1, Region 2, and so on, and each one zooms, pauses, and closes on its own.

A panel closes by itself when its source window closes or its app quits.


## Using a panel

Move the pointer over a panel to show its controls:

- **Top left:** close button, the app's frame rate, and the detection wait time when detection is on.
- **Top:** the source app's name.
- **Top right:** detection status dot. Green means idle detection, blue means change detection, and the dot pulses once content is idle.
- **Bottom right:** resize handle.
- **Bottom left:** hints for the most common actions.
- **Bottom:** play, pause, track buttons, and a progress bar when the source is playing media.

Right-click a panel for **Focus source window**, **Preview source window**, **Pause capture**, **Restore full view**, the app frame rate, auto-hide, detection modes, and contrast enhancement. The same menu is available for each panel from the menu bar icon, together with **Close all panels**.

Small panels show fewer controls. Make a panel larger to see the frame rate and wait time buttons.

### Switching to the source and back

Click a panel to bring its source window to the front, even when it is on another Space, hidden, or minimized. Click the same panel again to return to the window you were using before. Double-click to focus the source and close the panel.

Click switching can be turned off under **Settings → Panels**. The same page lets you choose what a panel does while its source window is in front: keep showing, pause capture, or close.

### Previewing the full window

Hold `Space` over a panel to see the whole source window at a larger size in the middle of the screen. Release `Space` to close the preview. A quick tap keeps the preview open until you press `Space` again or click anywhere. On panels showing media, a tap plays or pauses instead, and holding longer than 0.25 seconds opens the preview.

### Zooming

| Action | Result |
| --- | --- |
| `⌘` + drag | Zoom into the selected area |
| `⌘` + scroll, or pinch | Zoom around the pointer |
| Hover and press `=` / `-` | Zoom in / out |
| Scroll | Pan a zoomed panel |
| `⌘` + double-click, or hover and press `0` | Show the whole window again |

Zoom goes up to 32×. Pinching works as soon as the pointer is over a panel; you don't need to click it first.

### Auto-hide

Double-tap `fn` over a panel to turn auto-hide on for all panels. A panel then fades out when the pointer moves over it, and clicks go to the window underneath. It reappears when the pointer leaves. To use a hidden panel's controls again, move the pointer to where the panel is and double-tap `fn` to turn auto-hide off. `Delete` still closes a hidden panel.

**Settings → Appearance → Hidden transparency** sets how far panels fade. At 100% a hidden panel is fully transparent and stops capturing until the pointer leaves.

### Media controls

When the source app shares what it is playing with macOS, the panel shows play/pause, previous, and next buttons. Media with a known length also gets a progress bar you can drag. Press `←` / `→` while hovering to jump back or forward 5 seconds.

Live streams, media that can't seek, and apps that don't share playback information show fewer or no controls. Music, TV, Spotify, Swinsian, and VLC seek through app automation, so macOS asks for permission the first time. Media options are under **Settings → Media**.

### Stage Manager

When a source window is in another Stage Manager group, its panel pauses and shows **Return to source**. Click it to switch to that group; capture resumes automatically.


## Shortcuts and gestures

All of these work while the pointer is over a panel, without clicking it first.

| Action | Result |
| --- | --- |
| Drag | Move the panel |
| Drag an edge or the bottom-right handle | Resize, keeping the content's proportions |
| Click / double-click | Switch to the source and back / focus the source and close the panel |
| `Space` | Preview the source window, or play and pause media |
| `←` / `→` | Seek media back / forward 5 seconds |
| `=` / `-` / `0` | Zoom in / zoom out / show the whole window |
| `F` | Choose the frame rate for this app |
| `D` / `C` / `S` | Toggle idle / change / subtle change detection |
| Double-tap `fn` | Toggle auto-hide for all panels |
| `Delete` | Close the panel |

**Settings → Shortcuts** lets you change the capture shortcuts, the quick capture modifiers, and the modifier you double-tap (`fn`, `⇧`, `⌃`, `⌥`, or `⌘`). The region shortcut follows the window shortcut with one more modifier unless you set it separately; for example `⌘⇧I` gives `⌥⇧⌘I`. You can also turn on a shortcut that closes all panels, `⌘⇧P` by default. Conflicting shortcuts are rejected.

## Content detection

IceScreen can watch a panel and tell you when something happens. Turn modes on for all new panels under **Settings → Detection & Automation**, or for one panel with `D`, `C`, `S`, its right-click menu, or the status dot.

| Mode | Notifies you when | Wait time |
| --- | --- | --- |
| Idle | Content stops changing, such as a build or download finishing | 5–120 seconds, default 20 |
| Change | Content changes again after staying still, such as a new log line or chat message | 1–120 seconds, default 10 |
| Subtle changes | Adds finer sampling to either mode, for spinners and thin progress bars | — |

Click the wait time at the top of a panel to set it for that panel only. Detection pauses while a panel is paused, fully hidden, or the Mac is asleep, and starts timing again afterwards. Clicking a notification brings the source window to the front.

### Run a command

Under **Detection & Automation → Run a shell command**, enter a command to run through `/bin/sh` whenever a panel detects idle or changed content. It receives these environment variables:

| Variable | Value |
| --- | --- |
| `ICESCREEN_EVENT` | `idle` or `change` |
| `ICESCREEN_APP` | Source app name |
| `ICESCREEN_BUNDLE_ID` | Source app bundle ID |
| `ICESCREEN_WINDOW_ID` | Source window ID |
| `ICESCREEN_WINDOW_TITLE` | Source window title |

For example, to have your Mac speak when a build goes quiet:

```bash
[ "$ICESCREEN_EVENT" = idle ] && say "$ICESCREEN_APP has finished"
```

Each panel runs one command at a time and skips new events while it runs. A command is stopped after its timeout (5–300 seconds, default 15), when its panel closes, or when IceScreen quits. Output is discarded; a non-zero exit status is shown as an error. Leave the field empty to turn commands off.


## Appearance and performance

**Settings → Appearance** has a live preview at the top. Use the built-in sample or **Choose image…** to try settings on your own picture; **Compare original** shows the image without enhancement.

| Setting | Default |
| --- | --- |
| Corner radius, 0–30 pt | 14 pt |
| Normal transparency | 0% (opaque) |
| Enhance contrast and sharpness, with separate strengths | Off, 50% each |
| Hidden transparency for auto-hide | 100% (fully transparent) |
| Dim around controls on hover, with edge shading strength | On, 100% |
| Show control hints | On |

Click the dot under a slider to restore its default.

Frame rate is chosen per app: 1, 5, 10, 15, 24, 30, or 60 FPS, with 10 FPS as the default. Lower rates use less power; 1–5 FPS is enough for terminals and logs, while video looks best at 30–60 FPS. Press `F` over a panel to change it for that app. **Settings → Panels** sets the default and resets per-app choices. Capture resolution follows the panel's size on screen, up to 4096 pixels on the longest side. Paused panels, fully hidden panels, and panels on a sleeping Mac stop capturing.

**Settings → Panels** also sets where new panels appear on screen and whether they show over full-screen apps. **Settings → General** turns on launch at login and can hide the menu bar icon; open IceScreen again from Applications to get back to settings.


## Command line

The app binary accepts arguments for scripts and launchers:

```bash
ICESCREEN=/Applications/IceScreen.app/Contents/MacOS/IceScreen
"$ICESCREEN" --app Terminal
"$ICESCREEN" --app Terminal --window build --zoom bottom-left:4x
"$ICESCREEN" --window 12345 --region
```

| Option | Meaning |
| --- | --- |
| `--app NAME` | Part of the app name, or its full bundle ID; not case-sensitive |
| `--window TITLE_OR_ID` | Part of the window title, or its numeric window ID |
| `--zoom POSITION:FACTOR` | Start zoomed into `top-left`, `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom`, or `bottom-right`, from 1× to 32× |
| `--region` | Select a region of the matched window |
| `--help` | Show usage |

Without `--app` or `--window`, IceScreen captures the front window. If several windows match a title, add `--app` or use the window ID. When IceScreen is already running, the request goes to the running app and the command exits as soon as it is received, or with an error if there is no reply within 3 seconds. Problems such as a missing window appear in the settings window. With no arguments, the command opens settings in the running app.


## Troubleshooting

**`fn + P` does nothing.** Check that Accessibility is allowed under **Settings → General**. If settings warns that global shortcuts are unavailable, also allow IceScreen under **System Settings → Privacy & Security → Input Monitoring**, then click **Check permissions again**.

**The panel is black or doesn't update.** Allow Screen Recording and restart IceScreen. Some protected content, such as DRM video, can't be captured, and minimized windows don't update until restored.

**Permissions keep resetting after an update.** macOS remembers permissions by app location. Keep IceScreen in Applications, quit it fully before replacing it, then open the new copy.

**The screen recording prompt shows an old icon.** macOS caches that icon for the login session. Log out and back in to refresh it.

**Media controls don't appear.** The source app must share playback information with macOS. Check that **Show source media controls** is on under **Settings → Media**.


## Build from source

Requires macOS, Xcode 26 or later, [uv](https://docs.astral.sh/uv/), and Cairo (`brew install cairo`) for the DMG background.

```bash
git clone https://github.com/inwf/IceScreen.git
cd IceScreen
bash scripts/build.sh
open dist/IceScreen.app
```

This builds `dist/IceScreen.app` and `dist/IceScreen-macOS.dmg` for your Mac. Set `UNIVERSAL=1` to build for both Apple Silicon and Intel. See [CONTRIBUTING.md](CONTRIBUTING.md) for tests and development checks, and [CHANGELOG.md](CHANGELOG.md) for what changed in each release.


## License

IceScreen is free software under the [GNU General Public License v3.0 or later](LICENSE). See [NOTICE](NOTICE).

<p align="center"><sub>If IceScreen keeps an eye on things for you, a <a href="https://github.com/inwf/IceScreen">GitHub star</a> helps others find it.</sub></p>

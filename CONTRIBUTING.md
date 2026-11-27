# Contributing

English · [简体中文](CONTRIBUTING.zh-CN.md)

## Building

IceScreen uses Swift Package Manager. `IceCore` holds the platform-independent logic for geometry, the command line, preferences, and content detection, and `swift test` runs on Linux. Building, signing, and interactively checking the full app requires macOS, Xcode 26 or later, uv, and Cairo (`brew install cairo`).

| Command | Result |
| --- | --- |
| `swift test` | Run the core logic tests |
| `bash scripts/build.sh` | Build `dist/IceScreen.app` and `dist/IceScreen-macOS.dmg` for the current architecture |
| `UNIVERSAL=1 bash scripts/build.sh` | Build a universal app for Apple Silicon and Intel |
| `CONFIGURATION=debug bash scripts/build.sh` | Build a debug version |
| `bash scripts/package-dmg.sh` | Package an existing `dist/IceScreen.app` as a DMG |

Builds are ad-hoc signed by default. Set `SIGN_IDENTITY` to sign the app and DMG with a Developer ID; notarization requires the publisher's own Apple Developer credentials.

## Checks

Read the [README](README.md) before making changes and run `swift test`. Changes that affect macOS behavior also need `bash scripts/build.sh`.

Changes to input handling or panels also need `bash scripts/check-panel-events.sh` in a macOS graphical session. This check launches the native app bundle and a separate foreground app. It verifies WindowServer hit testing, window ordering, pointer pass-through, and hiding for background panels, and checks that clicks dispatched through AppKit leave the foreground process and non-key window state unchanged. It then checks controls and rendering in the active app. Any failed assertion or missing completion record fails the check. Controlled events in the AppKit queue don't count as acceptance of hardware input, system permissions, or source window focusing.

Changes to detection commands also need `python3 scripts/check-detection-command.py .build/debug/IceScreen`, which runs real commands and verifies that child processes are cleaned up.

CI checks the core logic, the icon and installer background, native panel events, detection commands, the media helper, and the packages. Screen Recording permission, real source window focusing, hardware gestures, multiple displays, and CPU, memory, and power measurements still have to be verified on a real Mac; a passing CI run doesn't cover them.

For performance changes, record the device and source content, and measure CPU, memory, and frame updates with a release build. Avoid creating image objects for every frame, adding callbacks without bound, or adding background polling during capture.

## Icons

The source icon is `assets/AppIcon.png`. `scripts/make-icon.swift` generates the standard and Retina sizes from 16 to 1024 pixels, shared by Finder, the Dock, the About page, and the DMG volume icon. The menu bar icon is drawn by `MenuBarIcon.swift` as a template image that adapts to light and dark mode.

Changes to icons also need `uv run scripts/test-app-icon.py`. During the build, `check-app-icon.py` uses an ICNS decoder to check all ten standard and Retina representations, including system ARGB, PNG, and legacy RGB/mask formats. A missing representation, changed pixels, a wrong size, or a damaged file fails the check.

## Installer background

The installer window background comes from `assets/dmg-background.svg` and uses the font `assets/fonts/NotoSansSC-Installation.ttf`. Rendering requires Python 3.11 or later, uv, and Cairo. uv installs the script dependencies, and the font is loaded directly from the project.

```bash
uv run scripts/test-dmg-background.py
uv run scripts/render-dmg-background.py
uv run scripts/render-dmg-background.py --check
```

The Retina TIFF is written to `.build/dmg-background.tiff` and is not committed. The check verifies the format, size, DPI, character coverage, text bounds, and every pixel; rendering and checking use the same build environment. Each run of `scripts/package-dmg.sh` renders and strictly checks the background, sets the layout through Finder, then mounts the final DMG again to verify the background, icons, alias, and window layout. To check a mounted image from your own build, run `uv run scripts/check-dmg-layout.py /Volumes/IceScreen`.

## Submitting changes

Describe the behavior users will see, how you verified it, and the platform versions. Changes to graphics capture, permissions, multiple displays, and input handling need results from a real device. Don't present simulated results as results from a real device.

When you change user-visible behavior, update both `README.md` and `README.zh-CN.md`. When you change the development process, update both this file and `CONTRIBUTING.zh-CN.md`.

Record changes under `Unreleased` in `CHANGELOG.md`. Each version has the full English text first, then `---`, then the full Simplified Chinese text. Both parts use matching categories with entries in the same order, and list only categories that have entries, such as `### Added` with `### 新增` and `### Fixed` with `### 修复`. Before a release, run `python3 scripts/release-notes.py --tag vX.Y.Z` to preview the release notes for a version.

## Troubleshooting Actions

First check whether the job was assigned a runner. If it stayed unassigned because of capacity, rerun the same commit once runners are available. If the tests ran, start from the logs of the failed group, local unit tests, and a local build. Only when the problem depends on a macOS graphical session and can't be reproduced locally, provide an offline check package for the same commit to run on a Mac. The package verifies its signature and runs the same scripts as CI, in groups and separate processes, recording the system version, architecture, each group's log, and its exit status. Window geometry assertions use the actual window size after the system has laid it out. Send back the complete report at once, and review it by failed group.

## Releases

- Pushing to `main` runs the tests, builds the universal app, verifies the DMG and ZIP, and keeps the build artifacts in Actions for 14 days. Pushes to other branches don't trigger the workflow.
- Pull requests run the same checks without publishing.
- Pushing a `vX.Y.Z` tag looks for a successful, unexpired `main` build of the same commit and reuses it, or tests and builds again if none exists. After the checks pass, the workflow creates the GitHub Release with the universal DMG, ZIP, and `SHA256SUMS`.
- The release notes come from the matching version in `CHANGELOG.md`. The tag must match `CFBundleShortVersionString` in `Info.plist`.
- Running the workflow manually from the Actions page with an existing `vX.Y.Z` tag reuses or rebuilds its artifacts by the same rules and updates that release. Leaving the tag empty runs the checks only.

To publish a version, update `Sources/IceScreen/Resources/Info.plist` and `CHANGELOG.md`, push to `main`, wait for the checks to pass, then create and push the tag:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

## License

Code and documentation are licensed under GPL-3.0-or-later. By submitting a contribution, you confirm that you have the right to contribute it under this license.

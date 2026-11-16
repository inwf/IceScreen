# /// script
# requires-python = ">=3.11"
# dependencies = ["ds-store==1.3.3", "mac-alias==2.2.3", "pillow==12.0.0", "pyobjc-framework-Cocoa==13.0; sys_platform == 'darwin'"]
# ///
import hashlib
import sys
from pathlib import Path

from ds_store import DSStore
from ds_store.store import codecs
from mac_alias import Alias
from PIL import Image

if sys.platform == "darwin":
    from AppKit import NSScreen
    from Foundation import NSMakeRect, NSMaxY, NSRectFromString

volume = Path(sys.argv[1])
root = Path(__file__).resolve().parent.parent
# pBBk 不参与安装布局校验，保留其原始数据，避免自动调用书签解码器。
codecs.pop(b"pBBk")
with DSStore.open(str(volume / ".DS_Store"), "r") as store:
    window = store["."]["bwsp"]
    icons = store["."]["icvp"]
    if sys.platform == "darwin":
        # AppleScript 从屏幕左上角定位窗口，Finder 保存屏幕左下角坐标。
        screen = NSScreen.screens()[0].frame()
        expected = NSMakeRect(100, NSMaxY(screen) - 522, 660, 422)
        actual = NSRectFromString(window["WindowBounds"])
        assert actual == expected, f"Finder 窗口布局不正确：实际 {actual!r}，预期 {expected!r}，屏幕 {screen!r}"
    else:
        assert window["WindowBounds"] == "{{100, 100}, {660, 422}}", f"Finder 窗口布局不正确：{window!r}"
    assert not window["ShowToolbar"] and not window["ShowStatusBar"]
    assert icons["iconSize"] == 128 and icons["arrangeBy"] == "none"
    assert store["IceScreen.app"]["Iloc"] == (180, 205), f"应用图标位置不正确：{store['IceScreen.app']['Iloc']!r}"
    assert store["Applications"]["Iloc"] == (480, 205), f"Applications 图标位置不正确：{store['Applications']['Iloc']!r}"
    alias = Alias.from_bytes(icons["backgroundImageAlias"])
    assert alias.volume.name == "IceScreen"
    assert alias.target.posix_path == "/.background/dmg-background.tiff"
    assert alias.target.folder_cnid > 2 and alias.target.cnid > 2
background = volume / ".background/dmg-background.tiff"
assert hashlib.sha256(background.read_bytes()).digest() == hashlib.sha256((root / ".build/dmg-background.tiff").read_bytes()).digest()
assert (volume / ".VolumeIcon.icns").read_bytes() == (volume / "IceScreen.app/Contents/Resources/AppIcon.icns").read_bytes()
with Image.open(background) as image:
    assert image.size == (1320, 800)
    assert image.info["dpi"] == (144, 144)
print("DMG 布局检查通过：窗口尺寸、图标位置、Retina 背景、背景别名和卷图标。")

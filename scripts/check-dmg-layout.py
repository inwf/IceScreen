# /// script
# requires-python = ">=3.11"
# dependencies = ["ds-store==1.3.3", "mac-alias==2.2.3", "pillow==12.0.0"]
# ///
import hashlib
import sys
from pathlib import Path

from ds_store import DSStore
from mac_alias import Alias
from PIL import Image

volume = Path(sys.argv[1])
root = Path(__file__).resolve().parent.parent
with DSStore.open(str(volume / ".DS_Store"), "r") as store:
    window = store["."]["bwsp"]
    icons = store["."]["icvp"]
    assert window["WindowBounds"] == "{{100, 100}, {660, 422}}"
    assert not window["ShowToolbar"] and not window["ShowStatusBar"]
    assert icons["iconSize"] == 128 and icons["arrangeBy"] == "none"
    assert store["IceScreen.app"]["Iloc"] == (180, 205)
    assert store["Applications"]["Iloc"] == (480, 205)
    alias = Alias.from_bytes(icons["backgroundImageAlias"])
    assert alias.volume.name == "IceScreen"
    assert alias.target.posix_path == "/.background/dmg-background.tiff"
    assert alias.target.folder_cnid > 2 and alias.target.cnid > 2
background = volume / ".background/dmg-background.tiff"
assert hashlib.sha256(background.read_bytes()).digest() == hashlib.sha256((root / "assets/dmg-background.tiff").read_bytes()).digest()
assert (volume / ".VolumeIcon.icns").read_bytes() == (volume / "IceScreen.app/Contents/Resources/AppIcon.icns").read_bytes()
with Image.open(background) as image:
    assert image.size == (1320, 800)
    assert image.info["dpi"] == (144, 144)
print("DMG 布局检查通过：窗口尺寸、图标位置、Retina 背景、背景别名和卷图标。")

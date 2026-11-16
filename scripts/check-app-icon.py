# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow==12.0.0"]
# ///
import argparse
import hashlib
import plistlib
from pathlib import Path

from PIL import Image

parser = argparse.ArgumentParser(description="检查应用声明、全部图标尺寸和构建原图。")
parser.add_argument("app", type=Path)
parser.add_argument("--iconset", type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
with (args.app / "Contents/Info.plist").open("rb") as file:
    info = plistlib.load(file)
assert info["CFBundleIdentifier"] == "org.icescreen.app"
assert info["CFBundleIconFile"] == "AppIcon"
assert not {"CFBundleIconName", "CFBundleIcons", "CFBundleIconFiles"} & info.keys()
icon_path = args.app / "Contents/Resources/AppIcon.icns"
assert set(args.app.rglob("*.icns")) == {icon_path}, "应用包包含多余的图标资源"
source_hash = hashlib.sha256((root / "assets/AppIcon.png").read_bytes()).hexdigest()
assert (args.iconset.parent / "AppIcon.source.sha256").read_text().strip() == source_hash, "iconset 与原图版本不一致"
expected_sizes = {(points, points, scale) for points in (16, 32, 128, 256, 512) for scale in (1, 2)}
with Image.open(icon_path) as icon:
    available_sizes = set(icon.info["sizes"])
    expected_points = {(points, points) for points in (16, 32, 128, 256, 512)}
    available_points = {(width, height) for width, height, _ in available_sizes}
    missing_points = expected_points - available_points
    assert not missing_points, f"图标缺少逻辑尺寸：{sorted(missing_points)}，ICNS 尺寸：{sorted(available_sizes)}"
    for width, height, scale in expected_sizes & available_sizes:
        suffix = "@2x" if scale == 2 else ""
        with Image.open(args.iconset / f"icon_{width}x{height}{suffix}.png") as expected:
            actual = icon.icns.getimage((width, height, scale)).convert("RGBA")
            assert actual.size == expected.size == (width * scale, height * scale)
            assert actual.tobytes() == expected.convert("RGBA").tobytes(), f"图标内容不一致：{width}x{height}{suffix}"
print("应用图标检查通过：Info.plist、唯一图标资源、原图 SHA256、全部十个图标尺寸及像素。")

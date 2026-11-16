# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow==12.0.0", "icnsutil==1.1.0"]
# ///
import argparse
import hashlib
import io
import plistlib
from pathlib import Path

from icnsutil import ArgbImage, IcnsFile, IcnsType
from PIL import Image

REPRESENTATIONS = {
    (16, 1): ("ic04", "icp4", "is32"),
    (16, 2): ("ic11",),
    (32, 1): ("ic05", "icp5", "il32"),
    (32, 2): ("ic12",),
    (128, 1): ("ic07", "it32"),
    (128, 2): ("ic13",),
    (256, 1): ("ic08",),
    (256, 2): ("ic14",),
    (512, 1): ("ic09",),
    (512, 2): ("ic10",),
}
MASKS = {"is32": "s8mk", "il32": "l8mk", "it32": "t8mk"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def decode(media, key):
    kind = IcnsType.get(key)
    raw = media[key]
    if kind.is_type("argb") or key in MASKS:
        mask = media[MASKS[key]] if key in MASKS else None
        channels = ArgbImage(data=raw, mask=mask)
        return Image.merge("RGBA", tuple(
            Image.frombytes("L", channels.size, bytes(channel))
            for channel in (channels.r, channels.g, channels.b, channels.a)
        ))
    with Image.open(io.BytesIO(raw)) as image:
        return image.convert("RGBA")


def check_icon(icon_path, iconset, source):
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    require((iconset.parent / "AppIcon.source.sha256").read_text().strip() == source_hash,
            "iconset 与原图版本不一致")
    errors = list(IcnsFile.verify(str(icon_path)))
    require(not errors, f"ICNS 结构不正确：{errors}")
    media = IcnsFile(str(icon_path)).media
    checked = []
    for (points, scale), keys in REPRESENTATIONS.items():
        suffix = "@2x" if scale == 2 else ""
        name = f"icon_{points}x{points}{suffix}.png"
        present = [key for key in keys if key in media]
        require(present, f"图标缺少表示：{points}x{points}{suffix}")
        with Image.open(iconset / name) as expected_image:
            expected = expected_image.convert("RGBA")
        size = (points * scale, points * scale)
        require(expected.size == size, f"iconset 尺寸不正确：{name}")
        for key in present:
            with decode(media, key) as actual:
                require(actual.size == size, f"ICNS 尺寸不正确：{key}，预期 {size}，实际 {actual.size}")
                require(actual.tobytes() == expected.tobytes(), f"图标内容不一致：{name} ({key})")
        checked.append(name)
    return checked


def main():
    parser = argparse.ArgumentParser(description="检查应用声明、全部图标尺寸和构建原图。")
    parser.add_argument("app", type=Path)
    parser.add_argument("--iconset", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    with (args.app / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    require(info["CFBundleIdentifier"] == "org.icescreen.app", "应用标识不正确")
    require(info["CFBundleIconFile"] == "AppIcon", "应用图标声明不正确")
    require(not {"CFBundleIconName", "CFBundleIcons", "CFBundleIconFiles"} & info.keys(), "应用包含多余图标声明")
    icon_path = args.app / "Contents/Resources/AppIcon.icns"
    require(set(args.app.rglob("*.icns")) == {icon_path}, "应用包包含多余的图标资源")
    checked = check_icon(icon_path, args.iconset, root / "assets/AppIcon.png")
    print(f"应用图标检查通过：Info.plist、唯一图标资源、原图 SHA256、{len(checked)} 种表示及全部像素。")


if __name__ == "__main__":
    main()

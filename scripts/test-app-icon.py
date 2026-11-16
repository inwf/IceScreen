# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow==12.0.0", "icnsutil==1.1.0"]
# ///
import hashlib
import io
from pathlib import Path
import runpy
import tempfile
import unittest

from icnsutil import ArgbImage, IcnsFile
from PIL import Image


ROOT = Path(__file__).resolve().parent.parent
CHECKER = runpy.run_path(str(ROOT / "scripts/check-app-icon.py"))
check_icon = CHECKER["check_icon"]
REPRESENTATIONS = CHECKER["REPRESENTATIONS"]


class IconTests(unittest.TestCase):
    def setUp(self):
        (ROOT / ".build").mkdir(exist_ok=True)
        directory = tempfile.TemporaryDirectory(prefix="icon-test-", dir=ROOT / ".build")
        self.addCleanup(directory.cleanup)
        self.directory = Path(directory.name)
        self.iconset = self.directory / "AppIcon.iconset"
        self.iconset.mkdir()
        self.source = ROOT / "assets/AppIcon.png"
        (self.directory / "AppIcon.source.sha256").write_text(hashlib.sha256(self.source.read_bytes()).hexdigest())
        self.icon = self.directory / "AppIcon.icns"
        self.media = {}
        with Image.open(self.source) as source:
            for (points, scale), keys in REPRESENTATIONS.items():
                suffix = "@2x" if scale == 2 else ""
                with source.convert("RGBA").resize((points * scale, points * scale), Image.Resampling.LANCZOS) as image:
                    image.save(self.iconset / f"icon_{points}x{points}{suffix}.png")
                    self.media[keys[0]] = self.encode(image, keys[0])

    def encode(self, image, key):
        if key in ("ic04", "ic05"):
            return ArgbImage(image=image).argb_data()
        output = io.BytesIO()
        image.save(output, "PNG")
        return output.getvalue()

    def write(self, media=None):
        icon = IcnsFile()
        for key, raw in (self.media if media is None else media).items():
            icon.add_media(key, data=raw)
        icon.write(str(self.icon))

    def check(self):
        return check_icon(self.icon, self.iconset, self.source)

    def test_all_ten_representations(self):
        self.write()
        self.assertEqual(len(self.check()), 10)

    def test_each_missing_representation_is_rejected(self):
        for keys in REPRESENTATIONS.values():
            with self.subTest(key=keys[0]):
                media = dict(self.media)
                del media[keys[0]]
                self.write(media)
                with self.assertRaisesRegex(ValueError, "图标缺少表示"):
                    self.check()

    def test_each_changed_representation_is_rejected(self):
        for (points, scale), keys in REPRESENTATIONS.items():
            with self.subTest(key=keys[0]):
                suffix = "@2x" if scale == 2 else ""
                with Image.open(self.iconset / f"icon_{points}x{points}{suffix}.png") as image:
                    changed = image.convert("RGBA")
                pixel = list(changed.getpixel((0, 0)))
                pixel[0] ^= 1
                changed.putpixel((0, 0), tuple(pixel))
                media = dict(self.media)
                media[keys[0]] = self.encode(changed, keys[0])
                self.write(media)
                with self.assertRaisesRegex(ValueError, "图标内容不一致"):
                    self.check()

    def test_png_small_representations(self):
        media = dict(self.media)
        for old, new, size in [("ic04", "icp4", 16), ("ic05", "icp5", 32)]:
            del media[old]
            with Image.open(self.iconset / f"icon_{size}x{size}.png") as image:
                media[new] = self.encode(image, new)
        self.write(media)
        self.assertEqual(len(self.check()), 10)

    def test_legacy_rgb_with_masks(self):
        media = dict(self.media)
        for old, new, mask, size in [("ic04", "is32", "s8mk", 16), ("ic05", "il32", "l8mk", 32),
                                     ("ic07", "it32", "t8mk", 128)]:
            del media[old]
            with Image.open(self.iconset / f"icon_{size}x{size}.png") as image:
                channels = ArgbImage(image=image)
            media[new] = (b"\0\0\0\0" if new == "it32" else b"") + channels.rgb_data()
            media[mask] = channels.mask_data()
        self.write(media)
        self.assertEqual(len(self.check()), 10)

    def test_missing_mask_is_rejected(self):
        media = dict(self.media)
        del media["ic04"]
        with Image.open(self.iconset / "icon_16x16.png") as image:
            media["is32"] = ArgbImage(image=image).rgb_data()
        self.write(media)
        with self.assertRaisesRegex(ValueError, "ICNS 结构不正确"):
            self.check()

    def test_wrong_encoded_dimensions(self):
        media = dict(self.media)
        with Image.new("RGBA", (16, 16)) as image:
            media["ic10"] = self.encode(image, "ic10")
        self.write(media)
        with self.assertRaisesRegex(ValueError, "ICNS 尺寸不正确"):
            self.check()

    def test_wrong_iconset_dimensions(self):
        self.write()
        with Image.new("RGBA", (17, 17)) as image:
            image.save(self.iconset / "icon_16x16.png")
        with self.assertRaisesRegex(ValueError, "iconset 尺寸不正确"):
            self.check()

    def test_stale_source_hash(self):
        self.write()
        (self.directory / "AppIcon.source.sha256").write_text("0" * 64)
        with self.assertRaisesRegex(ValueError, "iconset 与原图版本不一致"):
            self.check()

    def test_missing_iconset_file(self):
        self.write()
        (self.iconset / "icon_16x16.png").unlink()
        with self.assertRaises(FileNotFoundError):
            self.check()

    def test_truncated_container(self):
        self.write()
        self.icon.write_bytes(self.icon.read_bytes()[:-1])
        with self.assertRaisesRegex(ValueError, "ICNS 结构不正确"):
            self.check()

    def test_empty_container(self):
        self.write({})
        with self.assertRaisesRegex(ValueError, "图标缺少表示"):
            self.check()


if __name__ == "__main__":
    unittest.main(verbosity=2)

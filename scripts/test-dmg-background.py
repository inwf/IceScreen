# /// script
# requires-python = ">=3.11"
# dependencies = ["cairosvg==2.8.2", "pillow==12.0.0", "fonttools==4.60.1"]
# ///
import io
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from xml.etree import ElementTree

import cairosvg
from PIL import Image, ImageChops

root = Path(__file__).resolve().parent.parent
script = root / "scripts/render-dmg-background.py"
renderer = runpy.run_path(str(script))
render_background = renderer["render_background"]
check_background = renderer["check_background"]
svg_path = root / "assets/dmg-background.svg"
font_path = root / "assets/fonts/NotoSansSC-Installation.ttf"
text_tag = "{http://www.w3.org/2000/svg}text"


class BackgroundTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expected = render_background(svg_path, font_path)
        (root / ".build").mkdir(exist_ok=True)

    @classmethod
    def tearDownClass(cls):
        cls.expected.close()

    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="background-test-", dir=root / ".build")
        self.addCleanup(directory.cleanup)
        self.directory = Path(directory.name)
        self.output = self.directory / "background.tiff"

    def run_cli(self, *args):
        return subprocess.run(
            [sys.executable, str(script), *map(str, args)],
            cwd=self.directory, capture_output=True, text=True, timeout=30,
        )

    def write_svg(self, svg):
        path = self.directory / "background.svg"
        svg.write(path, encoding="utf-8", xml_declaration=True)
        return path

    def test_round_trip(self):
        self.expected.save(self.output, compression="tiff_lzw", dpi=(144, 144))
        check_background(self.output, self.expected)
        with Image.open(self.output) as saved:
            self.assertEqual(saved.size, (1320, 800))
            self.assertEqual(saved.mode, "RGB")
            self.assertEqual(saved.n_frames, 1)
            self.assertEqual(saved.info["dpi"], (144, 144))
            self.assertEqual(saved.info["compression"], "tiff_lzw")

    def test_repeated_render_is_identical(self):
        with render_background(svg_path, font_path) as repeated:
            self.assertIsNone(ImageChops.difference(self.expected, repeated).getbbox())

    def test_each_instruction_is_drawn(self):
        svg = ElementTree.parse(svg_path)
        lines = list(svg.iter(text_tag))
        self.assertEqual(len(lines), 3)
        for parent in svg.iter():
            for element in list(parent):
                if element.tag == text_tag:
                    parent.remove(element)
        pixels = cairosvg.svg2png(
            bytestring=ElementTree.tostring(svg.getroot()), output_width=1320, output_height=800,
        )
        with Image.open(io.BytesIO(pixels)) as background:
            difference = ImageChops.difference(self.expected, background.convert("RGB"))
        for element in lines:
            with self.subTest(text=element.text):
                baseline = round(float(element.attrib["y"]) * 2)
                height = round(float(element.attrib["font-size"]) * 2)
                self.assertIsNotNone(difference.crop((0, baseline - height, 1320, baseline)).getbbox())

    def test_wrong_format(self):
        self.expected.save(self.output, format="PNG", dpi=(144, 144))
        with self.assertRaisesRegex(ValueError, "单帧 RGB TIFF"):
            check_background(self.output, self.expected)

    def test_wrong_mode(self):
        for mode in ("L", "RGBA"):
            with self.subTest(mode=mode):
                with self.expected.convert(mode) as converted:
                    converted.save(self.output, dpi=(144, 144))
                with self.assertRaisesRegex(ValueError, "单帧 RGB TIFF"):
                    check_background(self.output, self.expected)

    def test_multiple_frames(self):
        self.expected.save(self.output, save_all=True, append_images=[self.expected], dpi=(144, 144))
        with self.assertRaisesRegex(ValueError, "单帧 RGB TIFF"):
            check_background(self.output, self.expected)

    def test_wrong_dimensions(self):
        with self.expected.resize((660, 400)) as resized:
            resized.save(self.output, dpi=(144, 144))
        with self.assertRaisesRegex(ValueError, "尺寸或 DPI"):
            check_background(self.output, self.expected)

    def test_wrong_dpi(self):
        for dpi in ((72, 72), (144, 72)):
            with self.subTest(dpi=dpi):
                self.expected.save(self.output, dpi=dpi)
                with self.assertRaisesRegex(ValueError, "尺寸或 DPI"):
                    check_background(self.output, self.expected)

    def test_missing_dpi(self):
        self.expected.save(self.output)
        with self.assertRaisesRegex(ValueError, "尺寸或 DPI"):
            check_background(self.output, self.expected)

    def test_single_channel_pixel_changes(self):
        for channel in range(3):
            with self.subTest(channel=channel), self.expected.copy() as changed:
                pixel = list(changed.getpixel((0, 0)))
                pixel[channel] ^= 1
                changed.putpixel((0, 0), tuple(pixel))
                changed.save(self.output, dpi=(144, 144))
                with self.assertRaisesRegex(ValueError, "渲染结果不一致"):
                    check_background(self.output, self.expected)

    def test_missing_glyph(self):
        svg = ElementTree.parse(svg_path)
        next(svg.iter(text_tag)).text = "\U0001f9ca"
        with self.assertRaisesRegex(ValueError, "缺少字形"):
            render_background(self.write_svg(svg), font_path)

    def test_missing_text(self):
        svg = ElementTree.parse(svg_path)
        for parent in svg.iter():
            for element in list(parent):
                if element.tag == text_tag:
                    parent.remove(element)
        with self.assertRaisesRegex(ValueError, "缺少提示文字"):
            render_background(self.write_svg(svg), font_path)

    def test_blank_text(self):
        for text in ("", "   "):
            with self.subTest(text=text):
                svg = ElementTree.parse(svg_path)
                next(svg.iter(text_tag)).text = text
                with self.assertRaisesRegex(ValueError, "空白提示文字"):
                    render_background(self.write_svg(svg), font_path)

    def test_text_outside_each_edge(self):
        for attribute, value in (("x", "-100"), ("x", "760"), ("y", "-100"), ("y", "500")):
            with self.subTest(attribute=attribute, value=value):
                svg = ElementTree.parse(svg_path)
                next(svg.iter(text_tag)).set(attribute, value)
                with self.assertRaisesRegex(ValueError, "超出背景边界"):
                    render_background(self.write_svg(svg), font_path)

    def test_cli_generation_and_read_only_check(self):
        output = self.directory / "nested directory/background.tiff"
        result = self.run_cli("--output", output)
        self.assertEqual(result.returncode, 0, result.stderr)
        check_background(output, self.expected)
        content, mtime = output.read_bytes(), output.stat().st_mtime_ns
        result = self.run_cli("--check", "--output", output)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output.read_bytes(), content)
        self.assertEqual(output.stat().st_mtime_ns, mtime)

    def test_cli_missing_output_is_not_created(self):
        result = self.run_cli("--check", "--output", self.output)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FileNotFoundError", result.stderr)
        self.assertFalse(self.output.exists())

    def test_cli_rejects_changed_pixels_without_rewriting(self):
        with self.expected.copy() as changed:
            pixel = list(changed.getpixel((100, 100)))
            pixel[0] ^= 1
            changed.putpixel((100, 100), tuple(pixel))
            changed.save(self.output, compression="tiff_lzw", dpi=(144, 144))
        content, mtime = self.output.read_bytes(), self.output.stat().st_mtime_ns
        result = self.run_cli("--check", "--output", self.output)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("渲染结果不一致", result.stderr)
        self.assertEqual(self.output.read_bytes(), content)
        self.assertEqual(self.output.stat().st_mtime_ns, mtime)


if __name__ == "__main__":
    unittest.main(verbosity=2)

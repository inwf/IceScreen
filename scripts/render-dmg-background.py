# /// script
# requires-python = ">=3.11"
# dependencies = ["cairosvg==2.8.2", "pillow==12.0.0", "fonttools==4.60.1"]
# ///
import argparse
import io
from pathlib import Path
from xml.etree import ElementTree

import cairosvg
from fontTools.ttLib import TTFont
from PIL import Image, ImageChops, ImageDraw, ImageFont

root = Path(__file__).resolve().parent.parent


def render_background(svg_path: Path, font_path: Path) -> Image.Image:
    svg = ElementTree.parse(svg_path)
    with TTFont(font_path) as font:
        cmap = font.getBestCmap()
        lines = []
        for parent in svg.iter():
            for element in list(parent):
                if element.tag != "{http://www.w3.org/2000/svg}text":
                    continue
                text = "".join(element.itertext())
                if not text.strip():
                    raise ValueError("安装背景包含空白提示文字")
                missing = [char for char in text if cmap.get(ord(char), ".notdef") == ".notdef"]
                if missing:
                    raise ValueError(f"安装字体缺少字形：{''.join(missing)}")
                lines.append((element, text))
                parent.remove(element)
    if not lines:
        raise ValueError("安装背景缺少提示文字")
    pixels = cairosvg.svg2png(bytestring=ElementTree.tostring(svg.getroot()), output_width=1320, output_height=800)
    with Image.open(io.BytesIO(pixels)) as rendered:
        image = rendered.convert("RGB")
    draw = ImageDraw.Draw(image)
    for element, text in lines:
        # 显式加载随项目分发的字体，所有文字在打包前完成栅格化。
        font = ImageFont.truetype(str(font_path), round(float(element.attrib["font-size"]) * 2))
        font.set_variation_by_axes([float(element.get("font-weight", "400"))])
        position = (float(element.attrib["x"]) * 2, float(element.attrib["y"]) * 2)
        box = draw.textbbox(position, text, font=font, anchor="ms")
        if box[0] < 0 or box[1] < 0 or box[2] > image.width or box[3] > image.height:
            raise ValueError(f"安装提示超出背景边界：{text}")
        draw.text(position, text, font=font, fill=element.attrib["fill"], anchor="ms")
    return image


def check_background(output: Path, image: Image.Image) -> None:
    with Image.open(output) as saved:
        if saved.format != "TIFF" or saved.mode != "RGB" or saved.n_frames != 1:
            raise ValueError("安装背景必须为单帧 RGB TIFF")
        if saved.size != image.size or saved.info.get("dpi") != (144, 144):
            raise ValueError("安装背景尺寸或 DPI 不正确")
        if ImageChops.difference(saved, image).getbbox() is not None:
            raise ValueError("安装背景与当前构建环境的渲染结果不一致")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="只读检查背景格式、尺寸、DPI、字形、边界和全部像素")
    parser.add_argument("--output", type=Path, default=root / ".build/dmg-background.tiff", help="生成或检查的 TIFF 路径")
    args = parser.parse_args()
    image = render_background(root / "assets/dmg-background.svg", root / "assets/fonts/NotoSansSC-Installation.ttf")
    if args.check:
        check_background(args.output, image)
        print("安装背景检查通过：格式、尺寸、DPI、全部文字字形、边界和像素一致。")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        image.save(args.output, compression="tiff_lzw", dpi=(144, 144))
        check_background(args.output, image)
        print(f"已生成并校验 Retina 安装背景：{args.output}（1320 × 800 像素，660 × 400 点）。")


if __name__ == "__main__":
    main()

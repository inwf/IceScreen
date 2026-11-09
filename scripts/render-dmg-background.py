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
parser = argparse.ArgumentParser()
parser.add_argument("--check", action="store_true", help="检查提交的背景图片与字体渲染结果是否一致")
args = parser.parse_args()
svg = ElementTree.parse(root / "assets/dmg-background.svg")
font_path = root / "assets/fonts/NotoSansSC-Installation.ttf"
with TTFont(font_path) as font:
    cmap = font.getBestCmap()
    lines = []
    for parent in svg.iter():
        for element in list(parent):
            if element.tag != "{http://www.w3.org/2000/svg}text":
                continue
            text = "".join(element.itertext())
            missing = [char for char in text if cmap.get(ord(char), ".notdef") == ".notdef"]
            if missing:
                raise ValueError(f"安装字体缺少字形：{''.join(missing)}")
            lines.append((element, text))
            parent.remove(element)
pixels = cairosvg.svg2png(bytestring=ElementTree.tostring(svg.getroot()), output_width=1320, output_height=800)
image = Image.open(io.BytesIO(pixels)).convert("RGB")
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
output = root / "assets/dmg-background.tiff"
if args.check:
    with Image.open(output) as saved:
        if saved.size != image.size or saved.info.get("dpi") != (144, 144):
            raise ValueError("安装背景尺寸或 DPI 不正确")
        if ImageChops.difference(saved.convert("RGB"), image).getbbox() is not None:
            raise ValueError("安装背景需要重新生成")
    print("安装背景检查通过：全部文字字形齐全、位置有效、提交图片与渲染结果一致。")
else:
    image.save(output, compression="tiff_lzw", dpi=(144, 144))
    print("已生成 Retina 安装背景：1320 × 800 像素，显示尺寸 660 × 400 点。")

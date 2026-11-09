# /// script
# requires-python = ">=3.11"
# dependencies = ["cairosvg==2.8.2", "pillow==12.0.0"]
# ///
import io
from pathlib import Path

import cairosvg
from PIL import Image

root = Path(__file__).resolve().parent.parent
pixels = cairosvg.svg2png(url=str(root / "assets/dmg-background.svg"), output_width=1320, output_height=800)
image = Image.open(io.BytesIO(pixels)).convert("RGB")
image.save(root / "assets/dmg-background.tiff", compression="tiff_lzw", dpi=(144, 144))
print("已生成 Retina 安装背景：1320 × 800 像素，显示尺寸 660 × 400 点。")

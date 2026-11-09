# 安装背景字体

`NotoSansSC-Installation.ttf` 是 Noto Sans SC 的可变字体子集，仅包含安装背景使用的字符，遵循同目录的 SIL Open Font License。

背景由 `uv run scripts/render-dmg-background.py` 生成。脚本直接加载此字体并检查每个字符，中文和英文均在生成 TIFF 时绘制。安装后的 Finder 使用已生成的图片，无需安装字体。

运行 `uv run scripts/render-dmg-background.py --check` 检查字符覆盖、文字边界和提交的图片。修改提示文案时，需要同步扩充字体子集。

字体来源：Google Fonts 的 `ofl/notosanssc` 目录。子集可以使用以下命令从完整字体生成：

```bash
uv run --with fonttools==4.60.1 pyftsubset NotoSansSC.ttf \
  --text='IceScreen拖入「应用程序」即可安装安装完成后，可以推出此磁盘映像' \
  --output-file=assets/fonts/NotoSansSC-Installation.ttf \
  --name-IDs='*' --name-legacy --name-languages='*'
```

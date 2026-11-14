# /// script
# requires-python = ">=3.11"
# ///
import argparse
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--tag", required=True)
args = parser.parse_args()

if not re.fullmatch(r"v[0-9]+(?:\.[0-9]+){2}(?:[-+][0-9A-Za-z.-]+)?", args.tag):
    raise ValueError("版本标签必须使用 vX.Y.Z 格式")
version = args.tag[1:]
lines = (Path(__file__).resolve().parent.parent / "CHANGELOG.md").read_text(encoding="utf-8").splitlines()
heading = f"## {version} —"
start = next((index for index, line in enumerate(lines) if line.startswith(heading)), None)
if start is None:
    raise ValueError(f"CHANGELOG.md 缺少版本 {version} 的章节")
end = next((index for index in range(start + 1, len(lines)) if lines[index].startswith("## ")), len(lines))
notes = "\n".join(lines[start:end]).strip()
if not notes:
    raise ValueError(f"CHANGELOG.md 的版本 {version} 章节为空")
print(notes)

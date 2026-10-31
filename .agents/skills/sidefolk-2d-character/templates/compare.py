# The rig at rest beside its target, at the same size: the first look after every change to outlines or paintings.
#   swift run sidefolk-render <out> --only <companion's 2d folder or id>     (from the checkout)
#   python3 compare.py <out>/companion-<id>.png <name>-target-canvas.webp <out>/idle-vs-target.png
# The idle cell's place in sidefolk-render's states sheet (200 pt cells drawn at 2x, the title above).
import sys
from PIL import Image

sheet, target, out = sys.argv[1:4]
idle = Image.open(sheet).convert("RGB").crop((60, 110, 380, 470)).resize((640, 720))
canvas = Image.open(target).convert("RGB").crop((100, 60, 700, 760)).resize((617, 720))
both = Image.new("RGB", (1270, 720), "white")
both.paste(idle, (0, 0))
both.paste(canvas, (650, 0))
both.save(out)

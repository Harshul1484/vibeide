"""Write the Android adaptive launcher icon (vector foreground + monochrome + white background) from the master.

Adaptive icons are a 108×108 dp canvas; launchers mask it to shapes that always contain the central 66 dp circle.
The mark is scaled so its farthest point sits 30 dp from the centre (inside the 33 dp safe radius).
"""
import math
import os
import sys

import master

RES = sys.argv[1]

WIDTH, ARM = 36, 48                      # the small-size cut (same as vibeide-symbol-small.svg)
d = master.symbol_path(width=WIDTH, arm=ARM)

# Farthest extent from the canvas centre, measured on the scaled geometry (chevron points + capsule radius).
chev = master.chevrons(arm=ARM)
pts = [p for c in chev for p in c]
xs, ys = [p[0] for p in pts], [p[1] for p in pts]
cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
span = max(max(xs) - min(xs), max(ys) - min(ys)) + WIDTH
s = min(1.0, 216 / span)
far = max(math.hypot((x - cx) * s, (y - cy) * s) for x, y in pts) + WIDTH * s / 2

scale = 30 / far                          # 256-unit canvas → dp
tx = 54 - 128 * scale

VECTOR = f'''<?xml version="1.0" encoding="utf-8"?>
<!-- VibeIDE mark (docs/brand/logo/vibeide-symbol-small.svg) as an adaptive-icon foreground layer.
     108dp canvas; the mark's farthest point is 30dp from the centre, inside the 33dp safe zone. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <group
        android:translateX="{master.fmt(tx)}"
        android:translateY="{master.fmt(tx)}"
        android:scaleX="{master.fmt(scale)}"
        android:scaleY="{master.fmt(scale)}">
        <path
            android:fillColor="{{color}}"
            android:pathData="{d}" />
    </group>
</vector>
'''

ADAPTIVE = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
'''

COLORS = '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#FFFFFF</color>
</resources>
'''

os.makedirs(os.path.join(RES, "drawable"), exist_ok=True)
os.makedirs(os.path.join(RES, "mipmap-anydpi-v26"), exist_ok=True)
with open(os.path.join(RES, "drawable", "ic_launcher_foreground.xml"), "w", encoding="utf-8", newline="\n") as fh:
    fh.write(VECTOR.replace("{color}", master.BLUE))
# Monochrome layer (Android 13 themed icons): the system tints it, so the colour is irrelevant.
with open(os.path.join(RES, "drawable", "ic_launcher_monochrome.xml"), "w", encoding="utf-8", newline="\n") as fh:
    fh.write(VECTOR.replace("{color}", "#FFFFFFFF").replace("adaptive-icon foreground layer", "monochrome (themed icon) layer"))
with open(os.path.join(RES, "mipmap-anydpi-v26", "ic_launcher.xml"), "w", encoding="utf-8", newline="\n") as fh:
    fh.write(ADAPTIVE)
with open(os.path.join(RES, "values", "ic_launcher_background.xml"), "w", encoding="utf-8", newline="\n") as fh:
    fh.write(COLORS)
print(f"far={far:.1f} units, scale={scale:.4f} dp/unit, translate={tx:.2f}dp")

"""Outline the VibeIDE wordmark (Inter, OFL) and build the lockups — no live text in any output.

Shaping (kerning) by HarfBuzz, outlines by fontTools, variable font instanced at wght 700 / opsz 32; feature cv08 = serifed capital I so "IDE" never reads as "lDE".
Lockup rules (all derived from the symbol's visual height H, i.e. the mark's bounding box):
  horizontal: cap height = 0.46 H, gap symbol→word = 0.30 H, word vertically centred on the mark
  stacked:    cap height = 0.30 H, gap = 0.22 H, word centred under the mark
"""
import io
import uharfbuzz as hb
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen

import master

TEXT = "VibeIDE"
INK = "#1E1E1E"       # wordmark colour (app background tone); symbol stays #0078D4
TRACK = -0.012        # tracking, fraction of the em (tight display setting)

var = TTFont("Inter-var.ttf")
font = instantiateVariableFont(var, {"wght": 700, "opsz": 32}, inplace=False)
buf_io = io.BytesIO()
font.save(buf_io)
data = buf_io.getvalue()
upem = font["head"].unitsPerEm
cap = font["OS/2"].sCapHeight
glyphset = font.getGlyphSet()

hbfont = hb.Font(hb.Face(data))
buf = hb.Buffer()
buf.add_str(TEXT)
buf.guess_segment_properties()
hb.shape(hbfont, buf, {"kern": True, "liga": False, "cv08": True})
names = [font.getGlyphName(i.codepoint) for i in buf.glyph_infos]
advs = [p.x_advance for p in buf.glyph_positions]


def word_path(cap_px, x0, baseline):
    """SVG path for the word with cap height cap_px, starting at x0, baseline at y=baseline. Returns (d, width)."""
    s = cap_px / cap
    pen = SVGPathPen(glyphset, ntos=lambda v: master.fmt(v))
    x = 0.0
    for name, adv in zip(names, advs):
        tp = TransformPen(pen, (s, 0, 0, -s, x0 + x * s, baseline))
        glyphset[name].draw(tp)
        x += adv + TRACK * upem
    return pen.getCommands(), (x - TRACK * upem) * s


def ink_bounds(cap_px):
    bp = BoundsPen(glyphset)
    x = 0.0
    xmin = xmax = None
    for name, adv in zip(names, advs):
        bp.bounds = None
        glyphset[name].draw(bp)
        if bp.bounds:
            a, _, b, _ = bp.bounds
            xmin = a + x if xmin is None else min(xmin, a + x)
            xmax = b + x if xmax is None else max(xmax, b + x)
        x += adv + TRACK * upem
    s = cap_px / cap
    return xmin * s, xmax * s


# Symbol visual box inside its 256 canvas (from the audit: margins L31.1 R31.1 T42 B42.2).
SYM_L, SYM_T, SYM_W, SYM_H = 31.1, 42.0, 256 - 62.2, 256 - 84.2
sym_d = master.symbol_path()


def symbol_group(x, y, scale):
    return (f'  <g id="symbol" transform="translate({master.fmt(x)} {master.fmt(y)}) scale({master.fmt(scale)})">\n'
            f'    <path fill="{master.BLUE}" d="{sym_d}"/>\n  </g>\n')


def write(name, w, h, body, title="VibeIDE logo"):
    open(name, "w", encoding="utf-8").write(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {master.fmt(w)} {master.fmt(h)}" '
        f'width="{master.fmt(w)}" height="{master.fmt(h)}" role="img" aria-labelledby="t"><title id="t">{title}</title>\n'
        + body + "</svg>\n")


PAD = 16
# --- Horizontal: canvas height 256; the mark's visual box is scaled to height 256-2*PAD.
H = 256 - 2 * PAD
s = H / SYM_H
sym_x, sym_y = PAD - SYM_L * s, PAD - SYM_T * s
cap_h = 0.46 * H
gap = 0.30 * H
ix0, ix1 = ink_bounds(cap_h)
word_x = PAD + SYM_W * s + gap - ix0
d, _ = word_path(cap_h, word_x, 128 + cap_h / 2)
width = word_x + ix1 + PAD
write("vibeide-horizontal.svg", width, 256,
      symbol_group(sym_x, sym_y, s) + f'  <path id="wordmark" fill="{INK}" d="{d}"/>\n')

# --- Stacked: mark 160 tall, word centred below.
H2 = 160
s2 = H2 / SYM_H
cap2 = 0.30 * H2
gap2 = 0.22 * H2
ix0, ix1 = ink_bounds(cap2)
word_w = ix1 - ix0
total_w = max(SYM_W * s2, word_w) + 2 * PAD
sx = (total_w - SYM_W * s2) / 2 - SYM_L * s2
sy = PAD - SYM_T * s2
base = PAD + H2 + gap2 + cap2
d2, _ = word_path(cap2, (total_w - word_w) / 2 - ix0, base)
write("vibeide-stacked.svg", total_w, base + PAD,
      symbol_group(sx, sy, s2) + f'  <path id="wordmark" fill="{INK}" d="{d2}"/>\n')

# --- Wordmark only: cap height 110, canvas height 256.
cap3 = 110
ix0, ix1 = ink_bounds(cap3)
d3, _ = word_path(cap3, PAD - ix0, 128 + cap3 / 2)
write("vibeide-wordmark.svg", ix1 - ix0 + 2 * PAD, 256, f'  <path id="wordmark" fill="{INK}" d="{d3}"/>\n')
print("wrote vibeide-horizontal.svg vibeide-stacked.svg vibeide-wordmark.svg")

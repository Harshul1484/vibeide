"""VibeIDE master symbol: the w-chase Flock mark as filled outlines (no strokes).

Geometry (from flock.py 'w-chase'): three chevrons, apex on an r44 orbit at -90°/30°/150°, heading = tangent + 30°,
arms 52 long at ±60°, 28 wide with round caps/joins; centred on the canvas and scaled so the mark spans 216 of 256.
Each arm is written as a stadium (capsule) outline; the two arms of a chevron overlap at the apex, so with the
default nonzero fill rule the union renders seamlessly and the round join is exactly the stroked result.
"""
import math

BLUE = "#0078D4"


def fmt(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s == "-0" else s


def chevrons(orbit=44, arm=52, spread=60, tilt=30, rot0=-90):
    out = []
    for k in range(3):
        ang = math.radians(rot0 + 120 * k)
        ax, ay = 128 + orbit * math.cos(ang), 128 + orbit * math.sin(ang)
        h = ang + math.radians(90 + tilt)
        ends = [(ax + arm * math.cos(h + math.pi + math.radians(s)),
                 ay + arm * math.sin(h + math.pi + math.radians(s))) for s in (-spread, spread)]
        out.append((ends[0], (ax, ay), ends[1]))
    return out


def stadium(p, q, r):
    """Closed capsule around segment p→q with radius r, clockwise on screen."""
    dx, dy = q[0] - p[0], q[1] - p[1]
    n = math.hypot(dx, dy)
    ox, oy = -dy / n * r, dx / n * r              # left normal × r
    a1 = (p[0] + ox, p[1] + oy)
    a2 = (q[0] + ox, q[1] + oy)
    b2 = (q[0] - ox, q[1] - oy)
    b1 = (p[0] - ox, p[1] - oy)
    R = fmt(r)
    return (f"M{fmt(a1[0])} {fmt(a1[1])} L{fmt(a2[0])} {fmt(a2[1])} "
            f"A{R} {R} 0 0 0 {fmt(b2[0])} {fmt(b2[1])} L{fmt(b1[0])} {fmt(b1[1])} "
            f"A{R} {R} 0 0 0 {fmt(a1[0])} {fmt(a1[1])} Z")


def symbol_path(width=28, span_target=216, **geo):
    chev = chevrons(**geo)
    pts = [p for c in chev for p in c]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    span = max(max(xs) - min(xs), max(ys) - min(ys)) + width
    s = min(1.0, span_target / span)
    t = lambda p: (128 + (p[0] - cx) * s, 128 + (p[1] - cy) * s)  # noqa: E731
    r = width * s / 2
    parts = []
    for a, apex, b in chev:
        parts.append(stadium(t(a), t(apex), r))
        parts.append(stadium(t(apex), t(b), r))
    return " ".join(parts)


def svg(d, title, fill=BLUE):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256" '
            f'role="img" aria-labelledby="t"><title id="t">{title}</title>\n'
            f'  <path id="symbol" fill="{fill}" d="{d}"/>\n</svg>\n')


if __name__ == "__main__":
    open("vibeide-symbol.svg", "w", encoding="utf-8").write(svg(symbol_path(), "VibeIDE logo"))
    # Small-size cut: heavier arms (34) and slightly shorter reach so the gaps stay open at 16–32 px.
    open("vibeide-symbol-small.svg", "w", encoding="utf-8").write(
        svg(symbol_path(width=36, arm=48), "VibeIDE logo (small sizes)"))
    print("wrote vibeide-symbol.svg vibeide-symbol-small.svg")

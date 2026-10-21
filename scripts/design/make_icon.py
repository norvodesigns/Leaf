#!/usr/bin/env python3
"""Leaf's app icon, "Leaf, open": an open book whose two pages curve into one leaf, the spine as its midrib.
Two cream glass panes on deep forest green. Writes the iPhone (light, dark, tinted) and Watch masters at 1024 px
and previews to docs/design/icon/. Needs Pillow. Run from the repo root: python3 scripts/design/make_icon.py"""
import math
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 4096          # supersampled canvas
OUT = 1024


def hexrgb(h, a=255):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255, a)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def radial(size, inner, outer, center=(0.5, 0.35), reach=0.85):
    w, h = size
    img = Image.new("RGBA", size)
    px = img.load()
    cx, cy = center[0] * w, center[1] * h
    r = reach * max(w, h)
    for y in range(0, h, 4):
        for x in range(0, w, 4):
            t = min(1, math.hypot(x - cx, y - cy) / r)
            t = t * t * (3 - 2 * t)
            c = lerp(inner, outer, t)
            for dy in range(4):
                for dx in range(4):
                    if x + dx < w and y + dy < h:
                        px[x + dx, y + dy] = c
    return img


def vertical(size, top, bottom):
    w, h = size
    img = Image.new("RGBA", size)
    d = ImageDraw.Draw(img)
    for y in range(h):
        d.line([(0, y), (w, y)], fill=lerp(top, bottom, y / max(1, h - 1)))
    return img


def leaf_halves(cx, cy, height, width, tilt_deg, gap):
    """Two page-halves of a leaf: lists of points, left and right, rotated by tilt."""
    top = cy - height / 2
    n = 160
    left, right = [], []
    for i in range(n + 1):
        t = i / n
        y = top + height * t
        # A leaf: fuller below the middle, a fine tip on top.
        bulge = math.sin(math.pi * t) ** 0.9 * (0.55 + 0.45 * t) ** 0.6
        half = width / 2 * bulge
        inner = gap * math.sin(math.pi * t)
        left.append(((cx - half, y), (cx - inner, y)))
        right.append(((cx + half, y), (cx + inner, y)))
    a = math.radians(tilt_deg)

    def rot(p):
        x, y = p[0] - cx, p[1] - cy
        return (cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a))

    lpoly = [rot(o) for o, _ in left] + [rot(i) for _, i in reversed(left)]
    rpoly = [rot(o) for o, _ in right] + [rot(i) for _, i in reversed(right)]
    return lpoly, rpoly, rot, top


def mask_from(poly):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).polygon(poly, fill=255)
    return m


def render(background, pane_left, pane_right, rim_alpha, vein_color, shadow_alpha, stem_color):
    cx, cy = S * 0.515, S * 0.50
    height, width = S * 0.60, S * 0.44
    lpoly, rpoly, rot, top = leaf_halves(cx, cy, height, width, -14, S * 0.012)
    img = background.copy()

    # Soft shadow under the panes.
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    off = S * 0.018
    sd.polygon([(x, y + off) for x, y in lpoly], fill=(0, 0, 0, shadow_alpha))
    sd.polygon([(x, y + off) for x, y in rpoly], fill=(0, 0, 0, shadow_alpha))
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.02))
    img = Image.alpha_composite(img, shadow)

    # The stem: a short curve from the bottom tip.
    stem = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    st = ImageDraw.Draw(stem)
    pts = []
    for i in range(40):
        t = i / 39
        pts.append(rot((cx + S * 0.03 * math.sin(t * 1.6), cy + height / 2 - S * 0.01 + S * 0.10 * t)))
    st.line(pts, fill=stem_color, width=int(S * 0.016), joint="curve")
    img = Image.alpha_composite(img, stem)

    for poly, (top_c, bottom_c), lit in ((lpoly, pane_left, False), (rpoly, pane_right, True)):
        m = mask_from(poly)
        fill = vertical((S, S), top_c, bottom_c)
        layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        layer.paste(fill, (0, 0), m)
        img = Image.alpha_composite(img, layer)

        # Page edges as veins: fine curves from the spine outward.
        veins = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        vd = ImageDraw.Draw(veins)
        side = 1 if lit else -1
        for k, t0 in enumerate((0.30, 0.48, 0.66)):
            line = []
            for i in range(30):
                u = i / 29
                y = top + height * (t0 + 0.16 * u)
                x = cx + side * (S * 0.02 + width * 0.33 * u * (1 - 0.15 * k))
                line.append(rot((x, y - height * (0.15 if lit else 0.06) * u)))
            vd.line(line, fill=vein_color, width=int(S * 0.006), joint="curve")
        vm = ImageChops.multiply(veins.split()[3], m)
        veins.putalpha(vm)
        img = Image.alpha_composite(img, veins)

        # Glass rim: a bright edge that fades, stronger on the lit pane.
        edge = Image.new("L", (S, S), 0)
        ImageDraw.Draw(edge).polygon(poly, outline=255, width=int(S * 0.008))
        edge = edge.filter(ImageFilter.GaussianBlur(S * 0.002))
        rim = Image.new("RGBA", (S, S), (255, 255, 255, 0))
        rim.putalpha(edge.point(lambda v: int(v * (rim_alpha if lit else rim_alpha * 0.55) / 255)))
        img = Image.alpha_composite(img, rim)

        # Specular sheen on the upper part of each pane.
        sheen = Image.new("RGBA", (S, S), (255, 255, 255, 0))
        sm = Image.new("L", (S, S), 0)
        sx = cx + (S * 0.06 if lit else -S * 0.12)
        ImageDraw.Draw(sm).ellipse([sx - S * 0.09, cy - height * 0.36, sx + S * 0.09, cy - height * 0.06], fill=int(rim_alpha * 0.35))
        sm = sm.filter(ImageFilter.GaussianBlur(S * 0.04))
        sheen.putalpha(ImageChops.multiply(sm, m))
        img = Image.alpha_composite(img, sheen)

    return img.resize((OUT, OUT), Image.LANCZOS).convert("RGB")


def main():
    forest_bg = radial((S, S), hexrgb(0x2F6B4C), hexrgb(0x0F2C1E))
    cream_l = (hexrgb(0xEEE9DE), hexrgb(0xDAD2C2))
    cream_r = (hexrgb(0xFCFAF4), hexrgb(0xEBE5D7))
    light = render(forest_bg, cream_l, cream_r, 230, hexrgb(0x1F4D36, 70), 120, hexrgb(0xE9DEC7))

    night_bg = radial((S, S), hexrgb(0x15281E), hexrgb(0x050A07))
    green_l = (hexrgb(0x6FAF87), hexrgb(0x3E7A57))
    green_r = (hexrgb(0x9BD3AE), hexrgb(0x5E9E77))
    dark = render(night_bg, green_l, green_r, 200, hexrgb(0x0E1813, 90), 160, hexrgb(0x5E9E77))

    grey_bg = radial((S, S), hexrgb(0x2A2A2A), hexrgb(0x000000))
    grey_l = (hexrgb(0xC9C9C9), hexrgb(0x9E9E9E))
    grey_r = (hexrgb(0xF2F2F2), hexrgb(0xCFCFCF))
    tinted = render(grey_bg, grey_l, grey_r, 200, hexrgb(0x000000, 70), 140, hexrgb(0xBDBDBD)).convert("L").convert("RGB")

    ios = "Leaf/Resources/Assets.xcassets/AppIcon.appiconset/"
    light.save(ios + "AppIcon.png")
    dark.save(ios + "AppIcon-Dark.png")
    tinted.save(ios + "AppIcon-Tinted.png")
    light.save("LeafWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

    # Previews: the three variants side by side, and the mark at small sizes.
    sheet = Image.new("RGB", (OUT * 3 + 160, OUT + 80), (245, 241, 232))
    for i, im in enumerate((light, dark, tinted)):
        m = Image.new("L", (OUT, OUT), 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, OUT - 1, OUT - 1], radius=int(OUT * 0.2237), fill=255)
        sheet.paste(im, (40 + i * (OUT + 40), 40), m)
    sheet.resize((sheet.width // 2, sheet.height // 2), Image.LANCZOS).save("docs/design/icon/variants.png")
    small = Image.new("RGB", (40 + sum(s + 30 for s in (180, 120, 87, 60, 40)), 240), (245, 241, 232))
    x = 30
    for size in (180, 120, 87, 60, 40):
        im = light.resize((size, size), Image.LANCZOS)
        m = Image.new("L", (size, size), 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.2237), fill=255)
        small.paste(im, (x, 30), m)
        x += size + 30
    small.save("docs/design/icon/sizes.png")
    w = light.resize((400, 400), Image.LANCZOS)
    m = Image.new("L", (400, 400), 0)
    ImageDraw.Draw(m).ellipse([0, 0, 399, 399], fill=255)
    watch = Image.new("RGB", (440, 440), (0, 0, 0))
    watch.paste(w, (20, 20), m)
    watch.save("docs/design/icon/watch.png")


if __name__ == "__main__":
    main()

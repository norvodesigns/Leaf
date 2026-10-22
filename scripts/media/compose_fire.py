"""Loop the steadied fireplace region (crossfade its last second into its first) and set it at the foot of a
portrait frame, the wall above it dark with a little firelight.

Usage: compose_fire.py region.rgb RW RH frames fade outW outH out.rgb [bottomMargin]
"""
import sys
import numpy as np

src = sys.argv[1]; RW, RH, N, F, OW, OH = map(int, sys.argv[2:8]); outp = sys.argv[8]
bottom = int(sys.argv[9]) if len(sys.argv) > 9 else 0
region = np.memmap(src, dtype=np.uint8, mode="r", shape=(N, RH, RW, 3))
L = N - F
y0 = OH - RH - bottom

# The wall above the fire: near black, warmed by the firelight just above the opening.
ys, xs = np.mgrid[0:OH, 0:OW].astype(np.float32)
dark = np.array([14, 9, 7], np.float32)
glow = np.array([70, 34, 16], np.float32)
r = np.hypot((xs - OW / 2) / (OW * 0.75), (ys - (y0 + RH * 0.25)) / (OH * 0.42))
g = np.clip(1 - r, 0, 1) ** 2
wall = dark + (glow - dark) * g[..., None]

# The region fades in over its top 30 % and darkens a little at the sides.
ry = np.arange(RH, dtype=np.float32) / (RH * 0.30)
alpha = np.clip(ry, 0, 1); alpha = alpha * alpha * (3 - 2 * alpha)
# ...and into shadow over its bottom 12 %, where the hearth floor meets the dark.
by = np.clip((RH - 1 - np.arange(RH, dtype=np.float32)) / (RH * 0.12), 0, 1) if bottom else np.ones(RH, np.float32)
alpha = alpha * (by * by * (3 - 2 * by))
rx = (np.arange(RW, dtype=np.float32) / RW - 0.5) / 0.5
side = 1 - 0.38 * rx ** 4
mask = (alpha[:, None] * side[None, :])[..., None]

out = open(outp, "wb")
for i in range(L):
    if i < F:
        w = (i + 0.5) / F
        frame = region[i].astype(np.float32) * w + region[L + i].astype(np.float32) * (1 - w)
    else:
        frame = region[i].astype(np.float32)
    canvas = wall.copy()
    canvas[y0:y0 + RH] = wall[y0:y0 + RH] * (1 - mask) + frame * mask
    out.write(np.clip(canvas + 0.5, 0, 255).astype(np.uint8).tobytes())
out.close()
print("loop frames", L)

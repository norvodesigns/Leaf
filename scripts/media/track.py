"""Estimate per-frame scale + translation of a slowly moving camera relative to a reference frame.

Usage: track.py frames.rgb W H ref_index out.json
Works on small frames; masks out very bright pixels (flames) and compares gradient images by phase correlation
over a range of scales.
"""
import json, sys
import numpy as np

path, W, H, ref, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
frames = np.fromfile(path, dtype=np.uint8).reshape(-1, H, W, 3).astype(np.float32)
gray = frames.mean(axis=3)


def edges(g):
    gx = np.zeros_like(g); gy = np.zeros_like(g)
    gx[:, 1:-1] = g[:, 2:] - g[:, :-2]
    gy[1:-1, :] = g[2:, :] - g[:-2, :]
    m = np.hypot(gx, gy)
    m[g > 200] = 0  # flames move on their own
    return m


def resample(img, s, cx, cy):
    """Zoom img by s about (cx, cy): out(x) = img(cx + (x - cx) / s)."""
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    sx = cx + (xs - cx) / s
    sy = cy + (ys - cy) / s
    x0 = np.clip(np.floor(sx).astype(int), 0, W - 2); y0 = np.clip(np.floor(sy).astype(int), 0, H - 2)
    fx = np.clip(sx - x0, 0, 1); fy = np.clip(sy - y0, 0, 1)
    a = img[y0, x0] * (1 - fx) + img[y0, x0 + 1] * fx
    b = img[y0 + 1, x0] * (1 - fx) + img[y0 + 1, x0 + 1] * fx
    v = a * (1 - fy) + b * fy
    valid = (sx >= 0) & (sx <= W - 1) & (sy >= 0) & (sy <= H - 1)
    return v * valid


win = np.outer(np.hanning(H), np.hanning(W)).astype(np.float32)
refE = edges(gray[ref]) * win
F_ref = np.fft.fft2(refE)


def phase(img):
    F = np.fft.fft2(img * win)
    R = F_ref * np.conj(F)
    R /= np.abs(R) + 1e-6
    r = np.real(np.fft.ifft2(R))
    i = np.unravel_index(np.argmax(r), r.shape)
    peak = r[i]
    dy, dx = i
    if dy > H // 2: dy -= H
    if dx > W // 2: dx -= W
    return peak, dx, dy


cx, cy = W / 2, H / 2
results = []
prev_s = 1.0
order = sorted(set(list(range(0, len(gray), 3)) + [len(gray) - 1, ref]), key=lambda k: abs(k - ref))
for k in order:
    e = edges(gray[k])
    best = None
    for s in np.arange(prev_s - 0.04, prev_s + 0.0401, 0.004):
        p, dx, dy = phase(resample(e, s, cx, cy))
        if best is None or p > best[0]:
            best = (p, float(s), dx, dy)
    prev_s = best[1]
    results.append({"frame": int(k), "scale": best[1], "dx": int(best[2]), "dy": int(best[3]), "peak": float(best[0])})
    print(k, round(best[1], 3), best[2], best[3], round(best[0], 3), flush=True)
json.dump({"W": W, "H": H, "ref": ref, "track": sorted(results, key=lambda r: r["frame"])}, open(out, "w"))

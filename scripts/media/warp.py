"""Hold a slowly moving shot still: warp every frame onto the reference frame with the fitted scale + shift.

Usage: warp.py src.mp4 track.json srcW srcH outW outH x0 y0 cropW cropH out.rgb
(x0, y0, cropW, cropH) is the output window in reference-frame coordinates at the source's resolution.
Writes raw rgb24 frames to out.rgb (pipe it to ffmpeg).
"""
import json, subprocess, sys
import numpy as np

src, trk = sys.argv[1], json.load(open(sys.argv[2]))
SW, SH, OW, OH = map(int, sys.argv[3:7])
X0, Y0, CW, CH = map(float, sys.argv[7:11])
outp = sys.argv[11]
sign = float(sys.argv[12]) if len(sys.argv) > 12 else 1.0

t = trk["track"]; k = np.array([r["frame"] for r in t], float)
unit = SW / trk["W"]
fit = {key: np.polyfit(k, np.array([r[key] for r in t], float), 2) for key in ("scale", "dx", "dy")}

dec = subprocess.Popen(["ffmpeg", "-v", "error", "-i", src, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
out = open(outp, "wb")
us, vs = np.meshgrid(np.linspace(X0, X0 + CW, OW, endpoint=False) + CW / OW / 2,
                     np.linspace(Y0, Y0 + CH, OH, endpoint=False) + CH / OH / 2)
cx, cy = SW / 2, SH / 2
frame = 0
size = SW * SH * 3
while True:
    buf = dec.stdout.read(size)
    if len(buf) < size:
        break
    img = np.frombuffer(buf, np.uint8).reshape(SH, SW, 3).astype(np.float32)
    s = np.polyval(fit["scale"], frame); dx = np.polyval(fit["dx"], frame) * unit; dy = np.polyval(fit["dy"], frame) * unit
    # ref(x) = zoomed_k(x - sign*d); zoomed_k(x) = img_k(c + (x - c) / s)
    xz = us - sign * dx; yz = vs - sign * dy
    sx = cx + (xz - cx) / s; sy = cy + (yz - cy) / s
    x0 = np.clip(np.floor(sx).astype(int), 0, SW - 2); y0 = np.clip(np.floor(sy).astype(int), 0, SH - 2)
    fx = np.clip(sx - x0, 0, 1)[..., None]; fy = np.clip(sy - y0, 0, 1)[..., None]
    a = img[y0, x0] * (1 - fx) + img[y0, x0 + 1] * fx
    b = img[y0 + 1, x0] * (1 - fx) + img[y0 + 1, x0 + 1] * fx
    v = a * (1 - fy) + b * fy
    out.write(np.clip(v + 0.5, 0, 255).astype(np.uint8).tobytes())
    frame += 1
out.close()
print("frames", frame, "scale range", np.polyval(fit["scale"], 0), np.polyval(fit["scale"], frame - 1))

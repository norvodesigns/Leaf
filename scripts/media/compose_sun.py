"""A still-camera-feeling loop from a slow drone glide: play the segment forward and back with the turns eased (the
glide slows to a stop and drifts back), set it at the foot of a portrait frame and carry the sky up above it.

Usage: compose_sun.py region.rgb RW RH frames seconds outW outH out.rgb [drop]

drop: rows cut from the region's foot, so the land and the sun sit lower in the frame (220 since the session's ring
went back to full size and took the top half of the screen).
"""
import sys
import numpy as np

src = sys.argv[1]; RW, RH, N = map(int, sys.argv[2:5]); T = float(sys.argv[5]); OW, OH = map(int, sys.argv[6:8]); outp = sys.argv[8]
fps = 24000 / 1001
drop = int(sys.argv[9]) if len(sys.argv) > 9 else 0
region = np.memmap(src, dtype=np.uint8, mode="r", shape=(N, RH, RW, 3))
y0 = OH - RH + drop
frames = int(round(T * fps))

# Warm the grade a touch: lift reds in the light, keep the shadows deep.
def grade(img):
    x = img / 255.0
    lum = x.mean(axis=2, keepdims=True)
    warm = np.array([1.06, 1.0, 0.9], np.float32)
    x = x * (1 + (warm - 1) * np.clip(lum * 1.6, 0, 1))
    sat = 1.18
    x = lum + (x - lum) * sat
    return np.clip(x * 255.0, 0, 255)

feather = 160
blend = np.clip(np.arange(feather, dtype=np.float32) / feather, 0, 1)
blend = (blend * blend * (3 - 2 * blend))[:, None, None]
ys = np.arange(y0 + feather, dtype=np.float32)[:, None, None] / (y0 + feather)

out = open(outp, "wb")
for i in range(frames):
    phase = i / frames
    t = (N - 1) * (1 - np.cos(2 * np.pi * phase)) / 2
    a = int(np.floor(t)); b = min(a + 1, N - 1); f = t - a
    img = region[a, :RH - drop].astype(np.float32) * (1 - f) + region[b, :RH - drop].astype(np.float32) * f
    img = grade(img)
    # The sky above: the region's top rows, smoothed across, deepening toward the top of the screen.
    top = img[:6].mean(axis=0)
    k = 301
    pad = np.pad(top, ((k // 2, k // 2), (0, 0)), mode="edge")
    kernel = np.ones(k, np.float32) / k
    top = np.stack([np.convolve(pad[:, c], kernel, mode="valid") for c in range(3)], axis=1)
    zenith = top.mean(axis=0) * np.array([0.52, 0.55, 0.66], np.float32)
    sky = zenith[None, None, :] * (1 - ys) + top[None, :, :] * ys
    canvas = np.empty((OH, OW, 3), np.float32)
    canvas[:y0 + feather] = sky
    canvas[y0:y0 + feather] = sky[y0:] * (1 - blend) + img[:feather] * blend
    canvas[y0 + feather:] = img[feather:]
    out.write(np.clip(canvas + 0.5, 0, 255).astype(np.uint8).tobytes())
out.close()
print("frames", frames)

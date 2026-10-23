"""A still-camera-feeling portrait loop from a landscape clip, for the nook's landscape scenes.

The segment plays forward and back with the turns eased (the drift slows to a stop and comes back), so the loop has no
seam and no visible reversal. The region is set at the foot of the portrait frame; when it is shorter than the frame,
its own sky is carried up above it (the top rows, smoothed across, deepening toward the top of the screen). A light
grade evens the look. Writes raw rgb24 frames to `out` ("-" for stdout, to pipe into the encoder).

Usage: compose_land.py region.rgb RW RH frames seconds outW outH out [options]
  --zenith r,g,b      the sky's colour at the top of the screen, as factors of the region's top rows (0.52,0.55,0.66)
  --feather px        rows over which the region fades into the carried-up sky (160)
  --grade e,w,s       exposure, warmth (+ warmer, - cooler) and saturation (1,0,1)
  --drop px           rows cut from the region's foot, so it sits lower (0)
  --steady 1          hold every frame at the segment's mean brightness, for a time-lapse whose light drifts
"""
import sys
import numpy as np

args, opts = [], {}
rest = iter(sys.argv[1:])
for arg in rest:
    if arg.startswith("--"):
        opts[arg[2:]] = next(rest)
    else:
        args.append(arg)
src = args[0]; RW, RH, N = map(int, args[1:4]); T = float(args[4]); OW, OH = map(int, args[5:7]); outp = args[7]
zenith = np.array([float(v) for v in opts.get("zenith", "0.52,0.55,0.66").split(",")], np.float32)
feather = int(opts.get("feather", 160))
exposure, warmth, saturation = (float(v) for v in opts.get("grade", "1,0,1").split(","))
drop = int(opts.get("drop", 0))
steady = opts.get("steady", "0") == "1"

fps = 24000 / 1001
region = np.memmap(src, dtype=np.uint8, mode="r", shape=(N, RH, RW, 3))
shown = RH - drop
y0 = OH - shown
frames = int(round(T * fps))
# Each source frame's brightness, from a sparse sample, for --steady.
means = np.array([region[i, ::8, ::8].mean() for i in range(N)], np.float32)


def grade(img):
    x = img / 255.0 * exposure
    lum = x.mean(axis=2, keepdims=True)
    tint = np.array([1 + 0.06 * warmth, 1.0, 1 - 0.1 * warmth], np.float32)
    x = x * (1 + (tint - 1) * np.clip(lum * 1.6, 0, 1))
    x = lum + (x - lum) * saturation
    return np.clip(x * 255.0, 0, 255)


if y0 > 0:
    blend = np.clip(np.arange(feather, dtype=np.float32) / feather, 0, 1)
    blend = (blend * blend * (3 - 2 * blend))[:, None, None]
    ys = np.arange(y0 + feather, dtype=np.float32)[:, None, None] / (y0 + feather)

out = sys.stdout.buffer if outp == "-" else open(outp, "wb")
for i in range(frames):
    phase = i / frames
    t = (N - 1) * (1 - np.cos(2 * np.pi * phase)) / 2
    a = int(np.floor(t)); b = min(a + 1, N - 1); f = t - a
    img = region[a, :shown].astype(np.float32) * (1 - f) + region[b, :shown].astype(np.float32) * f
    if steady:
        img *= means.mean() / (means[a] * (1 - f) + means[b] * f)
    img = grade(img)
    if y0 > 0:
        top = img[:6].mean(axis=0)
        k = 301
        pad = np.pad(top, ((k // 2, k // 2), (0, 0)), mode="edge")
        kernel = np.ones(k, np.float32) / k
        top = np.stack([np.convolve(pad[:, c], kernel, mode="valid") for c in range(3)], axis=1)
        sky = (top.mean(axis=0) * zenith)[None, None, :] * (1 - ys) + top[None, :, :] * ys
        canvas = np.empty((OH, OW, 3), np.float32)
        canvas[:y0 + feather] = sky
        canvas[y0:y0 + feather] = sky[y0:] * (1 - blend) + img[:feather] * blend
        canvas[y0 + feather:] = img[feather:]
    else:
        canvas = img[-OH:]
    out.write(np.clip(canvas + 0.5, 0, 255).astype(np.uint8).tobytes())
out.flush()
print("frames", frames, file=sys.stderr)

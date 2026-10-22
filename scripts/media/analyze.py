"""Second-by-second level and spectrum of a recording, to find steady stretches without outliers.

Usage: analyze.py file [start end]
"""
import subprocess, sys
import numpy as np

path = sys.argv[1]
args = ['ffmpeg', '-v', 'error', '-i', path]
if len(sys.argv) > 3:
    args = ['ffmpeg', '-v', 'error', '-ss', sys.argv[2], '-to', sys.argv[3], '-i', path]
raw = subprocess.run(args + ['-ac', '1', '-ar', '48000', '-f', 'f32le', '-'], capture_output=True).stdout
x = np.frombuffer(raw, np.float32)
sr = 48000
secs = len(x) // sr
rows = []
for s in range(secs):
    seg = x[s * sr:(s + 1) * sr]
    rms = 20 * np.log10(np.sqrt(np.mean(seg ** 2)) + 1e-9)
    peak = 20 * np.log10(np.max(np.abs(seg)) + 1e-9)
    spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg)))) ** 2
    f = np.fft.rfftfreq(len(seg), 1 / sr)
    tot = spec.sum() + 1e-12
    bands = [spec[(f >= lo) & (f < hi)].sum() / tot for lo, hi in ((0, 200), (200, 2000), (2000, 8000), (8000, 24000))]
    cent = (spec * f).sum() / tot
    rows.append((s, rms, peak, cent, *bands))
a = np.array(rows)
print(f"{path}: {secs}s  rms median {np.median(a[:,1]):.1f} dB  spread(p10-p90) {np.percentile(a[:,1],10):.1f}..{np.percentile(a[:,1],90):.1f}  peak max {a[:,2].max():.1f}")
print(f"  centroid median {np.median(a[:,3]):.0f} Hz  bands low/mid/high/air {np.median(a[:,4]):.2f}/{np.median(a[:,5]):.2f}/{np.median(a[:,6]):.2f}/{np.median(a[:,7]):.3f}")
# 10-second windows: level and how steady
for w in range(0, secs - 9, 10):
    blk = a[w:w + 10]
    print(f"  {w:4d}-{w+10:<4d} rms {blk[:,1].mean():6.1f}  sd {blk[:,1].std():4.1f}  peak {blk[:,2].max():6.1f}  cent {blk[:,3].mean():6.0f}")

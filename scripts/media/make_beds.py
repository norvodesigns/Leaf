"""Cut, clean, level and encode the recorded ambience beds.

Each bed is a stretch of a CC0 recording with 2 s to spare at the end: the app crossfades that tail into the start
when it loads the file (AudioLoop.seamless), so the encoder's priming and padding never reach the join.

Usage: make_beds.py srcdir outdir (scripts/media/build_media.sh fetches the sources)
"""
import json, os, subprocess, sys
import numpy as np

SRC, OUT = sys.argv[1], sys.argv[2]
SR = 44100
os.makedirs(OUT, exist_ok=True)


def load(name, start=None, end=None, filters=None, channels=2):
    cmd = ["ffmpeg", "-v", "error"]
    if start is not None: cmd += ["-ss", str(start)]
    if end is not None: cmd += ["-to", str(end)]
    cmd += ["-i", os.path.join(SRC, name)]
    af = []
    if filters: af.append(filters)
    af.append(f"aresample={SR}:resampler=soxr")
    cmd += ["-af", ",".join(af), "-ac", str(channels), "-f", "f32le", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, channels).copy()


def lufs(x):
    p = subprocess.run(["ffmpeg", "-nostats", "-f", "f32le", "-ar", str(SR), "-ac", str(x.shape[1]), "-i", "-",
                        "-af", "ebur128", "-f", "null", "-"], input=x.astype(np.float32).tobytes(), capture_output=True)
    for line in reversed(p.stderr.decode().splitlines()):
        line = line.strip()
        if line.startswith("I:"):
            return float(line.split()[1])
    raise RuntimeError("no loudness")


def limit(x, ceiling_db, release=0.060):
    """Lookahead peak limiter: 1.5 ms attack, 60 ms release, so crackles and drops lose their spikes, not their bite.
    A sparse crackle wants a release of a few milliseconds instead, or the bed under it ducks after every pop."""
    ceiling = 10 ** (ceiling_db / 20)
    mag = np.abs(x).max(axis=1)
    need = np.minimum(1.0, ceiling / np.maximum(mag, 1e-9))
    look = int(0.0015 * SR)
    # The gain must already be down when the peak arrives: take the minimum over the lookahead window.
    pad = np.concatenate([need, np.ones(look)])
    win = np.lib.stride_tricks.sliding_window_view(pad, look + 1).min(axis=1)
    rel = np.exp(-1 / (release * SR))
    gain = np.empty_like(win)
    g = 1.0
    for i, w in enumerate(win):
        g = w if w < g else w + (g - w) * rel
        gain[i] = g
    # Smooth the attack edge so the gain never steps.
    k = np.hanning(look * 2 + 1); k /= k.sum()
    gain = np.minimum(gain, np.convolve(gain, k, mode="same"))
    return x * gain[:, None]


def level(x, target, ceiling_db=-4.5, release=0.060):
    for _ in range(3):
        x = x * 10 ** ((target - lufs(x)) / 20)
        x = limit(x, ceiling_db, release)
    return x


def stft(x, n=2048, hop=512):
    pad = np.concatenate([np.zeros(n), x, np.zeros(n)])
    frames = np.lib.stride_tricks.sliding_window_view(pad, n)[::hop] * np.hanning(n)
    return np.fft.rfft(frames, axis=1)


def istft(X, length, n=2048, hop=512):
    w = np.hanning(n)
    frames = np.fft.irfft(X, n=n, axis=1) * w
    out = np.zeros(hop * (len(frames) - 1) + n)
    norm = np.zeros_like(out)
    for i, frame in enumerate(frames):
        out[i * hop:i * hop + n] += frame
        norm[i * hop:i * hop + n] += w * w
    return (out / np.maximum(norm, 1e-8))[n:n + length]


def quiet_hiss(x, beta=2.0, floor_lo_db=-4.0, floor_hi_db=-16.0, n=2048, hop=512):
    """Turns down a recording's steady bed (preamp hiss, the air of the room) and leaves what stands out of it.

    Spectral subtraction: each bin is lowered by how close it sits to its own quiet level (its 20th percentile over
    time), never below a floor that is gentle under 250 Hz (a fire's warmth) and 16 dB deep above 1 kHz (the hiss).
    Crackles stand far above the floor and pass. The gains are smoothed across 5 bins and released over 60 ms so the
    bed never warbles, and the same gains go to both channels so the image holds."""
    M = stft(x.mean(axis=1), n, hop)
    mag = np.abs(M)
    quiet = np.percentile(mag, 20, axis=0)
    f = np.fft.rfftfreq(n, 1 / SR)
    t = np.clip(np.log2(np.maximum(f, 1) / 250) / 2, 0, 1)
    gmin = 10 ** ((floor_lo_db + (floor_hi_db - floor_lo_db) * t) / 20)
    g = np.maximum(1 - beta * (quiet[None, :] / np.maximum(mag, 1e-12)) ** 2, gmin[None, :])
    g = np.apply_along_axis(lambda row: np.convolve(row, np.ones(5) / 5, mode="same"), 1, g)
    rel = np.exp(-hop / (0.06 * SR))
    for i in range(1, len(g)):
        g[i] = np.maximum(g[i], g[i - 1] * rel + g[i] * (1 - rel))
    g = np.maximum(g, gmin[None, :])
    return np.stack([istft(stft(x[:, c], n, hop) * g, len(x), n, hop) for c in range(2)], axis=1).astype(np.float32)


def encode(x, name):
    path = os.path.join(OUT, name + ".m4a")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", path],
                   input=x.astype(np.float32).tobytes(), check=True)
    return path


report = {}


def finish(name, x, target, notes, release=0.060, ceiling_db=-4.5):
    x = level(x, target, ceiling_db, release)
    peak = 20 * np.log10(np.abs(x).max())
    path = encode(x, name)
    report[name] = {"seconds": round(len(x) / SR, 2), "lufs": round(lufs(x), 2), "peak_dbfs": round(float(peak), 2),
                    "bytes": os.path.getsize(path), "notes": notes}
    print(name, report[name], flush=True)


SHARED = -18.0

# Fireplace: soft, gentle and relaxing, "the perfect balance of crackles and white noise, not too much of anything"
# (the owner, 2026-10-23, after a first bed that was mostly noise and a second that was mostly crackle). A log fire
# burning steadily (#2856): its top rounded off (6 dB down above 5 kHz, nothing over 9 kHz) and its steady hiss
# lowered 10 dB, so what's left is the fire's warm rush with its crackles in it. Levelled to -20 LUFS, a little under
# the others, with peaks held at -8 dBFS and a 25 ms release: the sharpest pops are rounded, none is flattened into
# the bed, and the bed never pumps.
fire = quiet_hiss(load("bsb-2856.flac", 3, 73, "highpass=f=35,treble=g=-6:f=5000,lowpass=f=9000"),
                  floor_lo_db=-2, floor_hi_db=-10)
finish("ambience-fireplace", fire, SHARED - 2, "BigSoundBank #2856, 3-73 s, top rounded, hiss lowered",
       release=0.025, ceiling_db=-8)

# Rain: steady medium rain on canvas, no thunder in this stretch (#0820), softened a little at the top.
rain = load("bsb-0820.wav", 80, 142, "highpass=f=70,treble=g=-3:f=7000")
finish("ambience-rain", rain, SHARED, "BigSoundBank #0820, 80-142 s")

# Café: the interior terrace of a café in Brest (#2561), a stretch without a loud clink or laugh.
cafe = load("bsb-2561.flac", 160, 222, "highpass=f=60")
finish("ambience-cafe", cafe, SHARED, "BigSoundBank #2561, 160-222 s")

# Kettle: an electric kettle at its rolling simmer (#0660), heard from the next room: the top rolled off and a
# little of the house's own room tone (#2458) around it.
kettle = load("bsb-0660.wav", 84, 116, "highpass=f=80,lowpass=f=2600,lowpass=f=3800", channels=2)
house = load("bsb-2458.flac", 10, 42, "highpass=f=40")
n = min(len(kettle), len(house))
kettle = kettle[:n] + house[:n] * 0.25
finish("ambience-kettle", kettle, SHARED, "BigSoundBank #0660 84-116 s, with #2458 room tone")

# Library: the hush of a quiet house (#2458) with pages turned across the room (#2210-2216, #0362, #0363, #0164) and
# a book closed once (#1411), each softened by distance and a little room.
rng = np.random.default_rng(0x11B)
room = load("bsb-2458.flac", 4, 96, "highpass=f=40")
length = len(room)
tail = int(2.5 * SR)


def distant(clip, gain_db, pan):
    mono = clip.mean(axis=1)
    # A one-pole low-pass near 4.5 kHz: across a room the paper's top end is gone.
    a = np.exp(-2 * np.pi * 4500 / SR)
    y = np.empty_like(mono); s = 0.0
    for i, v in enumerate(mono):
        s = v + (s - v) * a
        y[i] = s
    # A short, dark room tail.
    t = np.arange(int(0.45 * SR)) / SR
    ir = rng.standard_normal(len(t)) * np.exp(-t / 0.12)
    ir = np.convolve(ir, np.ones(40) / 40, mode="same")
    ir /= np.sqrt((ir ** 2).sum())
    wet = np.concatenate([np.convolve(y, ir), [0.0]])[: len(y) + len(t)]
    dry = np.concatenate([y, np.zeros(len(t))])
    out = dry * 0.8 + wet * 0.35
    g = 10 ** (gain_db / 20)
    angle = (pan + 1) * np.pi / 4
    return np.stack([out * np.cos(angle) * g, out * np.sin(angle) * g], axis=1)


pages = [load(f"bsb-{i}.flac") for i in ("2210", "2211", "2212", "2213", "2214", "2215", "2216")]
pages += [load("bsb-0362.wav"), load("bsb-0363.wav"), load("bsb-0164.wav")]
lib = room.copy()
t = 3.0
while t < length / SR - 2.5 - 2.0:
    clip = pages[rng.integers(len(pages))]
    ev = distant(clip, rng.uniform(-9, -3), rng.uniform(-0.7, 0.7))
    i = int(t * SR)
    j = min(length - tail, i + len(ev))
    lib[i:j] += ev[: j - i]
    t += rng.uniform(6.5, 13.0)
book = distant(load("bsb-1411.flac"), -8, 0.45)
i = int(47.3 * SR)
lib[i:i + len(book)] += book
finish("ambience-library", lib, SHARED - 8, "BigSoundBank #2458 room tone, page turns and a book, composed")

json.dump(report, open(os.path.join(OUT, "beds.json"), "w"), indent=1)

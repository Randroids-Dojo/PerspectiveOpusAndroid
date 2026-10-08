# Measures a Movie Maker capture of src/audio/dev/audio_test.tscn (what Godot mixed).
#
#   ffmpeg -i /tmp/tour.avi -vn -acodec pcm_f32le /tmp/tour.wav
#   uv run --no-project --with soundfile --with numpy --with scipy python tools/audio/analyze_capture.py /tmp/tour.wav audio_test.json
#
# Reports sample and true peak, clipping, integrated and short-term loudness (BS.1770
# K-weighting, gated), silences inside songs, loudness dips across perspective switches,
# and how far each effect rises over the music. With a steady capture (--steady=<song>)
# it prints the loudness of the score and stage halves for comparison with the web
# build's own renders (scripts/audio-render.ts --levels in ../PerspectiveOpus).

import json
import sys

import numpy as np
import soundfile as sf
from scipy.signal import lfilter, resample_poly


def kweight(x, sr):
    # BS.1770 pre-filter (high shelf) and RLB high pass, from the standard's analog prototypes.
    f0, G, Q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    K = np.tan(np.pi * f0 / sr)
    Vh, Vb = 10 ** (G / 20), (10 ** (G / 20)) ** 0.4996667741545416
    a0 = 1 + K / Q + K * K
    b1 = [(Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0]
    a1 = [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    f0, Q = 38.13547087602444, 0.5003270373238773
    K = np.tan(np.pi * f0 / sr)
    a0 = 1 + K / Q + K * K
    b2 = [1, -2, 1]
    a2 = [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    return lfilter(b2, a2, lfilter(b1, a1, x, axis=0), axis=0)


def blocks(y, sr, win, hop):
    n = max(0, (len(y) - win) // hop + 1)
    e = np.array([np.sum(np.mean(y[i * hop : i * hop + win] ** 2, axis=0)) for i in range(n)])
    return -0.691 + 10 * np.log10(np.maximum(e, 1e-12))


def lufs(x, sr):
    y = kweight(x, sr)
    m = blocks(y, sr, int(0.4 * sr), int(0.1 * sr))
    if len(m) == 0:
        return -70.0
    g = m[m > -70]
    if len(g) == 0:
        return -70.0
    rel = 10 * np.log10(np.mean(10 ** (g / 10))) - 10
    g2 = g[g > rel]
    return float(10 * np.log10(np.mean(10 ** (g2 / 10))))


def db(v):
    return float(20 * np.log10(max(float(v), 1e-10)))


def check_loop(x, sr, info, start):
    """The pass after the loop wrap against the same music one pass earlier."""
    from scipy.signal import correlate

    fsr = info["sr"]
    body = info["bodyFrames"] / fsr
    wrap = info["frames"] / fsr
    # Where the song starts in the capture: the first sound after its mark.
    i0 = int(start["t"] * sr)
    env = np.max(np.abs(x[i0 : i0 + 2 * sr]), axis=1)
    t0 = start["t"] + np.argmax(env > 1e-3) / sr
    print(f"\nloop: file {wrap:.3f} s, loop of {body:.3f} s from {info['loopStart'] / fsr:.3f} s; song heard from {t0:.3f} s")
    mono = np.sum(x, 1)
    win = int(0.5 * sr)
    worst = -200.0
    for off in [-3.0, -1.0, -0.25, 0.0, 0.25, 1.0, 3.0]:
        a = int((t0 + wrap + off) * sr)
        b = int((t0 + wrap + off - body) * sr)
        # The two passes drift by Godot's resampler rounding (about 15 ppm): align within 200 frames.
        y = mono[a - win // 2 : a + win // 2]
        r = mono[b - win // 2 - 200 : b + win // 2 + 200]
        c = correlate(r, y, "valid", method="fft")
        k = int(np.argmax(c))
        rr = r[k : k + len(y)]
        res = 10 * np.log10(np.sum((y - rr) ** 2) / max(np.sum(rr**2), 1e-12))
        worst = max(worst, res)
        print(f"  {off:+5.2f} s from the wrap: lag {k - 200:+4d} frames, difference from one pass earlier {res:6.1f} dB")
    # A click at the wrap would stand out in the sample-to-sample steps.
    a = int((t0 + wrap) * sr)
    d = np.abs(np.diff(mono[a - sr : a + sr]))
    dd = np.abs(np.diff(mono[int((t0 + wrap - body) * sr) - sr : int((t0 + wrap - body) * sr) + sr]))
    print(f"  largest step within 1 s of the wrap {np.max(d):.4f}, same place one pass earlier {np.max(dd):.4f}")
    print(f"  worst difference {worst:.1f} dB")


def main():
    x, sr = sf.read(sys.argv[1], dtype="float64", always_2d=True)
    marks = json.load(open(sys.argv[2]))["marks"]
    peak = np.max(np.abs(x))
    tp = np.max(np.abs(resample_poly(x, 4, 1, axis=0)))
    clipped = int(np.sum(np.abs(x) >= 0.999))
    print(f"capture {len(x) / sr:.1f} s at {sr} Hz")
    print(f"sample peak {db(peak):.2f} dBFS, true peak {db(tp):.2f} dBTP, clipped samples {clipped}")
    print(f"integrated loudness {lufs(x, sr):.1f} LUFS")
    st = blocks(kweight(x, sr), sr, int(3 * sr), int(1 * sr))
    print(f"short-term loudness {np.min(st[st > -70]):.1f} .. {np.max(st):.1f} LUFS")

    loop = [m for m in marks if m["kind"] == "loop"]
    if loop:
        check_loop(x, sr, loop[0], [m for m in marks if m["kind"] == "song"][0])
        return
    songs = [m for m in marks if m["kind"] in ("song", "stop")]
    steady = not any(m["kind"] == "event" for m in marks)
    win = int(0.1 * sr)
    rms = np.sqrt(np.mean(x[: len(x) // win * win].reshape(-1, win, 2) ** 2, axis=(1, 2)))
    rms_db = 20 * np.log10(np.maximum(rms, 1e-9))
    print("\nper song")
    for a, b in zip(songs, songs[1:]):
        if a["kind"] != "song":
            continue
        s0, s1 = a["t"] + 0.5, b["t"]
        seg = x[int(s0 * sr) : int(s1 * sr)]
        r = rms_db[int(s0 * 10) : int(s1 * 10)]
        quiet = r < -60
        run = best = 0
        for q in quiet:
            run = run + 1 if q else 0
            best = max(best, run)
        cond = f"{'score' if a['blend'] < 0.5 else 'stage'} L{a['restored']}"
        # Steady runs start at the song's start, like the web build's renders (first 24 s).
        if steady:
            seg = x[int(a["t"] * sr) : int((a["t"] + min(24.0, s1 - a["t"])) * sr)]
        line = f"  {a['id']:9} {cond:9} {lufs(seg, sr):6.1f} LUFS  peak {db(np.max(np.abs(seg))):6.1f}  longest silence {best / 10:.1f} s"
        print(line)
    if steady:
        return

    print("\nswitches (momentary loudness, 400 ms: the second before, the turn, the second after; the score breathes, so rests show here too)")
    mom = blocks(kweight(x, sr), sr, int(0.4 * sr), int(0.05 * sr))
    worst = 0.0
    for m in marks:
        if m["kind"] != "switch":
            continue
        i0 = int((m["t"] - 1.0) / 0.05)
        before = np.mean(mom[i0 : i0 + 16])
        after = np.mean(mom[i0 + 40 : i0 + 60])
        during = mom[i0 + 22 : i0 + 38]
        # Against the quieter side: an equal-power crossfade should not fall below either world.
        dip = float(np.min(during) - min(before, after))
        worst = min(worst, dip)
        print(f"  {m['t']:7.2f} s to {m['to']}: before {before:6.1f}, during {np.min(during):6.1f} .. {np.max(during):6.1f}, after {after:6.1f} LUFS (dip {dip:+.1f} dB)")
    print(f"  deepest dip {worst:+.1f} dB")

    print("\neffects (peak in the 0.6 s after, against the 0.6 s before)")
    rises = {}
    for m in marks:
        if m["kind"] not in ("event", "ui"):
            continue
        what = m.get("what", "ui " + m.get("name", ""))
        if m["kind"] == "event":
            what = f"{what} ({'page' if m['mode'] == '2d' else 'stage'})"
        i = int(m["t"] * sr)
        pre = np.max(np.abs(x[max(0, i - int(0.6 * sr)) : i]))
        post = np.max(np.abs(x[i : i + int(0.6 * sr)]))
        rises.setdefault(what.split(" (")[0] if what.startswith("note") else what, []).append(db(post) - db(pre))
    for k in sorted(rises):
        v = rises[k]
        print(f"  {k:28} {np.mean(v):+5.1f} dB (min {np.min(v):+5.1f}, n={len(v)})")


main()

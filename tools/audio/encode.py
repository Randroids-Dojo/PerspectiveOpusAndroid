# Encodes the raw float32 renders from tools/render_audio.ts to Ogg Vorbis with
# libvorbis (through libsndfile; Homebrew's ffmpeg only has the experimental native
# encoder), then decodes every file again to check its length and, for loops, the
# seam the native engine will play across.
#
# Renders arrive at 48 kHz and are downsampled to the files' rate with a polyphase
# filter given real context on both sides: the render's lead-in before, and after the
# end the loop's own continuation (circular for ambience loops), so seams stay clean.
#
#   uv run --no-project --with soundfile --with numpy --with scipy python tools/audio/encode.py jobs.json out.json

import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor

from math import gcd

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly


def db(x):
    return float(20 * np.log10(max(float(x), 1e-10)))


def encode(job):
    meta = json.load(open(job["raw"] + ".json"))
    ch = meta["channels"]
    x = np.fromfile(job["raw"] + ".f32", dtype="<f4").reshape(-1, ch)
    mb = int(meta.get("marginBefore", 0))
    src = int(meta["sr"])
    assert x.shape[0] == meta["frames"] + mb, f'{job["raw"]}: {x.shape[0]} frames, expected {meta["frames"] + mb}'
    core = x[mb:]
    ls = int(meta.get("loopStart", 0))
    sr_out = int(job["sr"])
    g = gcd(src, sr_out)
    up, down = sr_out // g, src // g
    if src != sr_out:
        assert meta["frames"] % down == 0 and ls % down == 0 and mb % down == 0, f'{job["raw"]}: lengths not whole multiples of {down}'
        m = 4800 - 4800 % down
        if meta.get("loop"):
            before = x[:mb] if mb else core[-m:]
            after = core[ls : ls + m]
        else:
            before = x[:mb] if mb else np.zeros((m, ch), np.float32)
            after = np.zeros((m, ch), np.float32)
        y = resample_poly(np.concatenate([before, core, after]), up, down, axis=0)
        start = len(before) * up // down
        core = y[start : start + meta["frames"] * up // down].astype(np.float32)
        ls = ls * up // down
    x = core if ch > 1 else core[:, 0]
    x = x * float(job.get("gain", 1.0))
    frames = x.shape[0]
    peak = float(np.max(np.abs(x))) if frames else 0.0
    if peak > 0.999:
        # Never let a stem clip in the file; the native mix restores the level.
        raise SystemExit(f'{job["raw"]}: peak {peak:.3f} would clip')
    os.makedirs(os.path.dirname(job["out"]), exist_ok=True)
    # Written in blocks: one large write crashes libsndfile's Vorbis writer.
    with sf.SoundFile(job["out"], "w", sr_out, ch, format="OGG", subtype="VORBIS", compression_level=job["q"]) as f:
        for i in range(0, frames, 32768):
            f.write(np.ascontiguousarray(x[i : i + 32768]))
    y, sr = sf.read(job["out"], dtype="float32", always_2d=True)
    res = {
        "out": os.path.relpath(job["out"]),
        "bytes": os.path.getsize(job["out"]),
        "seconds": frames / sr_out,
        "frames": frames,
        "channels": ch,
        "peakDb": db(peak),
        "framesOk": y.shape[0] == frames,
    }
    xr = x.reshape(-1, ch)
    err = y - xr
    res["codecSnrDb"] = db(np.sqrt(np.mean(xr**2)) / max(np.sqrt(np.mean(err**2)), 1e-12))
    if meta.get("loop"):
        d = np.abs(np.diff(y, axis=0)).max(axis=1)
        # The step across the wrap (last frame to the loop start) against ordinary steps.
        wrap = float(np.max(np.abs(y[ls] - y[-1])))
        p999 = float(np.percentile(d, 99.9))
        w = int(0.1 * sr)
        before = np.sqrt(np.mean(y[-w:] ** 2))
        after = np.sqrt(np.mean(y[ls : ls + w] ** 2))
        res["seam"] = {
            "wrapStep": wrap,
            "p999Step": p999,
            "ratio": wrap / max(p999, 1e-9),
            "levelJumpDb": db(after) - db(before) if before > 1e-6 and after > 1e-6 else 0.0,
        }
    return res


def main():
    jobs = json.load(open(sys.argv[1]))
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
        out = list(pool.map(encode, jobs))
    bad = [r for r in out if not r["framesOk"]]
    for r in bad:
        print("LENGTH MISMATCH", r["out"])
    json.dump(out, open(sys.argv[2], "w"))
    total = sum(r["bytes"] for r in out)
    print(f"encoded {len(out)} files, {total / 1048576:.2f} MB")
    sys.exit(1 if bad else 0)


main()

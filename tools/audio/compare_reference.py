# Compares a Godot capture of `audio_test.tscn -- --switches=...` with the web build's own
# renders of the same scenario (`tools/render_audio.ts --only=reference`).
#
#   uv run --no-project --with soundfile --with numpy --with scipy python tools/audio/compare_reference.py \
#       /tmp/switches.wav audio_test.json /tmp/opus-port-audio-ref
#
# For each run: integrated loudness of both, and around every switch the momentary loudness
# (400 ms) of both, aligned: how far each dips below the quieter world, and how far the two
# traces differ once their overall levels are matched.

import json
import os
import sys

import numpy as np
import soundfile as sf
from scipy.signal import correlate

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(__file__))
from analyze_capture import blocks, kweight, lufs  # noqa: E402


def main():
    cap, sr = sf.read(sys.argv[1], dtype="float64", always_2d=True)
    marks = json.load(open(sys.argv[2]))["marks"]
    ref_dir = sys.argv[3]
    runs = [m for m in marks if m["kind"] == "song"]
    hop = 0.05
    worst = 0.0
    for m in runs:
        ref, rsr = sf.read(os.path.join(ref_dir, f"{m['id']}_r{m['restored']}.wav"), dtype="float64", always_2d=True)
        assert rsr == sr
        # Align: the web render starts its song 50 ms in; Godot starts at the next mix after the mark.
        a = int(m["t"] * sr)
        g = cap[a : a + len(ref) + sr]
        c = correlate(np.sum(g[: 4 * sr], 1), np.sum(ref[: 3 * sr], 1), "valid", method="fft")
        lag = int(np.argmax(c))
        g = g[lag : lag + len(ref)]
        mg = blocks(kweight(g, sr), sr, int(0.4 * sr), int(hop * sr))
        mr = blocks(kweight(ref, sr), sr, int(0.4 * sr), int(hop * sr))
        n = min(len(mg), len(mr))
        mg, mr = mg[:n], mr[:n]
        lg, lr = lufs(g, sr), lufs(ref, sr)
        print(f"{m['id']:9} {m['restored']} notes: Godot {lg:6.1f} LUFS, web {lr:6.1f} LUFS ({lg - lr:+.1f} dB), aligned at {lag / sr * 1000:.0f} ms")
        off = lg - lr
        for k, t in enumerate([6.0, 14.0, 22.0, 30.0]):
            i0 = int((t - 1.0) / hop)
            seg = slice(int((t + 0.1) / hop), int((t + 0.9) / hop))

            def dip(tr):
                before = np.mean(tr[i0 : i0 + 16])
                after = np.mean(tr[int((t + 1.0) / hop) : int((t + 2.0) / hop)])
                return float(np.min(tr[seg]) - min(before, after))

            diff = float(np.max(np.abs((mg[seg] - off) - mr[seg])))
            worst = max(worst, diff)
            print(f"   switch to {'page ' if k % 2 == 0 else 'stage'} at {t:4.0f} s: dip Godot {dip(mg):+5.1f} dB, web {dip(mr):+5.1f} dB, largest trace difference {diff:4.1f} dB")
    print(f"largest difference between the traces through a switch, levels matched: {worst:.1f} dB")


main()

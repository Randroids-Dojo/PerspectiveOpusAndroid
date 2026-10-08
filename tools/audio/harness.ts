// Runs in headless Chrome (served by tools/render_audio.ts). Drives the web build's
// real audio code through OfflineAudioContexts and posts raw float32 audio back to
// the tool, which encodes it. Nothing here changes how a sound is made: the songs,
// players, mixer chains, rooms, instruments and effects are the web build's own.
//
//   window.__port.songInfo(id)          timelines, tempo, chords (as harmony indices)
//   window.__port.renderStems(...)      one stem per arrangement and restore layer
//   window.__port.recordSfx()           every tonal effect, per harmony, as a recipe
//   window.__port.renderVoices(...)     the notes and one-shots those recipes play
//   window.__port.renderBeds(...)       looped ambience beds

import { Ambience } from '../../../PerspectiveOpus/src/audio/ambience';
import { PRIO, SampleBank, zoneJobs } from '../../../PerspectiveOpus/src/audio/bank';
import { SFX_DEFS } from '../../../PerspectiveOpus/src/audio/dsp/sfx';
import { INSTRUMENTS, type InstId } from '../../../PerspectiveOpus/src/audio/instruments';
import { Mixer } from '../../../PerspectiveOpus/src/audio/mixer';
import { compileSong } from '../../../PerspectiveOpus/src/audio/music/arranger';
import { SONGS } from '../../../PerspectiveOpus/src/audio/music/songs';
import { parseChord, type Chord, type Key } from '../../../PerspectiveOpus/src/audio/music/theory';
import type { AmbienceId, Timeline } from '../../../PerspectiveOpus/src/audio/music/types';
import { SongPlayer } from '../../../PerspectiveOpus/src/audio/player';
import { Sfx, type Harmony } from '../../../PerspectiveOpus/src/audio/sfx';
import { VoicePool } from '../../../PerspectiveOpus/src/audio/voices';
import { renderSong as webRenderSong, type RenderOpts } from '../../../PerspectiveOpus/src/audio/dev/offline';
import type { SongId } from '../../../PerspectiveOpus/src/audio/audio';
import type { GameEvent } from '../../../PerspectiveOpus/src/game/sim';

const bank = new SampleBank();

// ------------------------------------------------------------------ helpers

/** Actions to run while an offline render is paused (one suspend per render quantum). */
class Script {
  private actions = new Map<number, ((t: number) => void)[]>();
  constructor(private ctx: OfflineAudioContext) {}
  at(t: number, fn: (t: number) => void): void {
    const q = 128;
    const frame = Math.max(q, Math.round((t * this.ctx.sampleRate) / q) * q);
    if (frame >= this.ctx.length) return;
    const list = this.actions.get(frame) ?? [];
    list.push(fn);
    this.actions.set(frame, list);
  }
  arm(): void {
    for (const [frame, fns] of this.actions) {
      const t = frame / this.ctx.sampleRate;
      void this.ctx.suspend(t).then(() => {
        for (const fn of fns) fn(t);
        void this.ctx.resume();
      });
    }
  }
}

async function save(name: string, data: Float32Array, meta: Record<string, unknown>): Promise<void> {
  const q = new URLSearchParams({ name, meta: JSON.stringify(meta) });
  const r = await fetch(`/__save?${q}`, { method: 'POST', body: data.buffer as ArrayBuffer });
  if (!r.ok) throw new Error(`save ${name}: ${r.status}`);
}

function interleave(l: Float32Array, r: Float32Array, a: number, b: number): Float32Array {
  const out = new Float32Array((b - a) * 2);
  for (let i = a, j = 0; i < b; i++, j += 2) {
    out[j] = l[i];
    out[j + 1] = r[i];
  }
  return out;
}

const db = (x: number) => (x > 0 ? 20 * Math.log10(x) : -200);

/**
 * Renders run at the web build's own context rate. Its rooms are noise impulse responses
 * normalised per sample, so their level depends on the rate: at 32 kHz they would come out
 * about 1.8 dB weaker than in the browser. tools/audio/encode.py then downsamples to the
 * files' 32 kHz, so every length here is a whole multiple of RATE_STEP frames.
 */
export const RENDER_SR = 48000;
export const RATE_STEP = 3;
const snap = (seconds: number) => RATE_STEP * Math.round((seconds * RENDER_SR) / RATE_STEP);
const snapUp = (frames: number) => RATE_STEP * Math.ceil(frames / RATE_STEP);
/** Frames of real context kept before a render (and after, for loops) for the downsampler. */
const MARGIN = snap(0.1);

function levels(x: Float32Array): { peakDb: number; rmsDb: number } {
  let p = 0;
  let e = 0;
  for (let i = 0; i < x.length; i++) {
    const v = Math.abs(x[i]);
    if (v > p) p = v;
    e += x[i] * x[i];
  }
  return { peakDb: db(p), rmsDb: db(Math.sqrt(e / Math.max(1, x.length))) };
}

/** The mixer's `pre` (everything before compression and limiting), forced to stereo. */
function tap(ctx: BaseAudioContext, m: Mixer): GainNode {
  const g = ctx.createGain();
  g.channelCount = 2;
  g.channelCountMode = 'explicit';
  g.channelInterpretation = 'speakers';
  m.pre.connect(g);
  return g;
}

/** A desk whose master chain goes nowhere: only `pre` (tapped) is heard, so renders stay linear. */
function desk(ctx: BaseAudioContext, sink: AudioNode): Mixer {
  const m = new Mixer(ctx, sink);
  m.setVolumes({ master: 1, music: 1, sfx: 1 }, 0);
  // setVolumes glides; start every bus at its full-volume level so short sounds are not caught mid-glide.
  for (const b of [m.sfx.page, m.sfx.stage, m.ui, m.amb]) {
    const v = b.input.gain;
    const target = b === m.amb ? 1 : 0.8; // the desk's SFX_LEVEL
    v.cancelScheduledValues(0);
    v.setValueAtTime(target, 0);
  }
  return m;
}

async function prepareSong(id: SongId): Promise<void> {
  const c = compileSong(SONGS[id]);
  const jobs = [];
  for (const [inst, pitches] of c.needs) jobs.push(...zoneJobs(inst, pitches));
  await bank.need(jobs, PRIO.now);
}

// ------------------------------------------------------------------ harmony

export interface HarmonyDesc {
  symbol: string;
  root: number;
  pcs: number[];
  intervals: number[];
  bass: number;
  third: number | null;
  seventh: number | null;
  key: Key;
}

const harmonies: HarmonyDesc[] = [];
const harmonyIndex = new Map<string, number>();
const harmonyObjs: Harmony[] = [];

function harmonyOf(chord: Chord, key: Key): number {
  const d: HarmonyDesc = {
    symbol: chord.symbol,
    root: chord.root,
    pcs: chord.pcs,
    intervals: chord.intervals,
    bass: chord.bass,
    third: chord.third,
    seventh: chord.seventh,
    key: { tonic: key.tonic, mode: key.mode },
  };
  // Effects only read pitch content, so chords spelled the same share an entry.
  const k = JSON.stringify([d.root, d.pcs, d.intervals, d.third, d.seventh, d.key]);
  let i = harmonyIndex.get(k);
  if (i === undefined) {
    i = harmonies.length;
    harmonies.push(d);
    harmonyObjs.push({ chord, key });
    harmonyIndex.set(k, i);
  }
  return i;
}

function timelineInfo(tl: Timeline | null) {
  if (!tl) return null;
  return {
    duration: tl.duration,
    beats: tl.beats,
    tempo: tl.tempo,
    chords: tl.chords.map((s) => ({ t: s.t, beat: s.beat, h: harmonyOf(s.chord, s.key) })),
    sections: tl.sections,
  };
}

export function songInfo(id: SongId) {
  const c = compileSong(SONGS[id]);
  const def = c.def;
  return {
    id,
    bpm: def.bpm,
    meter: def.meter,
    key: def.key,
    loop: def.loop,
    full: !!def.full,
    ambience: def.ambience ?? null,
    trim: def.trim ?? {},
    intro: timelineInfo(c.intro),
    body: timelineInfo(c.body)!,
    tracks: def.tracks.map((t) => ({ id: t.id, inst: t.inst, arr: t.arr, layer: t.layer, fade: t.fade ?? 2.4 })),
    warnings: c.warnings,
  };
}

/** The harmony the engine falls back to with no music: the tonic of the last key heard. */
export function fallbackHarmony(key: Key): number {
  return harmonyOf(parseChord('I', key), key);
}

export function harmonyList(): HarmonyDesc[] {
  return harmonies;
}

// ------------------------------------------------------------------ music stems

export interface StemSpec {
  name: string;
  arr: 'score' | 'stage';
  layers: number[];
}

export interface StemOpts {
  /** Seconds of the body played before the loop region starts (lets the previous pass's tails die away). */
  head: number;
  /** Crossfade at the loop wrap, seconds. */
  xfade: number;
  /** Silence kept before beat 0, seconds (the render's lead-in is cut). */
  lead: number;
  /** Seconds of ring after a non-looping song. */
  tail: number;
}

/**
 * Renders several stems of one song in a single offline pass: one SongPlayer, each
 * track routed through its own copy of the mixer's music chain (filter, shelves,
 * level, room or hall send) and out on its own pair of channels.
 *
 * Looping songs are written as one contiguous slice of the timeline: intro, the
 * first `head` seconds of the body, then exactly one body length. The loop region
 * starts `head` seconds into the body, where the previous pass's tails have died
 * away, so it repeats seamlessly (a short crossfade hides the sub-sample difference
 * between a loop of whole samples and the song's exact length), and the first time
 * through starts clean, as the web build does.
 */
export async function renderStems(id: SongId, stems: StemSpec[], o: StemOpts) {
  await prepareSong(id);
  const c = compileSong(SONGS[id]);
  const def = c.def;
  const sr = RENDER_SR;
  const intro = c.intro?.duration ?? 0;
  const body = c.body.duration;
  const S0 = snap(o.lead);
  const I = snap(intro);
  const B = snap(body);
  const Hs = snap(o.head);
  const X = Math.round(o.xfade * sr);
  const end = def.loop ? S0 + I + B + Hs + 64 : S0 + I + B + snap(o.tail);
  const ctx = new OfflineAudioContext(stems.length * 2, end, sr);
  ctx.destination.channelInterpretation = 'discrete';
  const merger = ctx.createChannelMerger(stems.length * 2);
  merger.connect(ctx.destination);
  const sink = ctx.createGain();
  const pool = new VoicePool(ctx, 2048);
  const player = new SongPlayer(ctx, c, bank, pool, desk(ctx, sink), o.lead, 7, 0.001);
  const chains = stems.map((s, k) => {
    const m = desk(ctx, sink);
    m.setBlendAt(s.arr === 'score' ? 0 : 1, 0);
    const trimDb = (s.arr === 'score' ? def.trim?.score : def.trim?.stage) ?? 0;
    const trim = ctx.createGain();
    trim.gain.value = Math.pow(10, trimDb / 20);
    trim.connect(m.music[s.arr].input);
    const split = ctx.createChannelSplitter(2);
    tap(ctx, m).connect(split);
    split.connect(merger, 0, 2 * k);
    split.connect(merger, 1, 2 * k + 1);
    return trim;
  });
  type Strip = { def: { arr: string; layer: number }; nodes: AudioNode[]; on: boolean; gain: GainNode };
  const strips = (player as unknown as { strips: Strip[] }).strips;
  const counts = stems.map(() => 0);
  strips.forEach((s) => {
    const last = s.nodes[s.nodes.length - 1];
    last.disconnect();
    const k = stems.findIndex((st) => st.arr === s.def.arr && st.layers.includes(s.def.layer));
    if (k < 0) {
      s.on = false;
      return;
    }
    counts[k]++;
    last.connect(chains[k]);
  });
  const script = new Script(ctx);
  player.schedule(0.5);
  for (let k = 1; k * 0.25 < end / sr; k++) script.at(k * 0.25, (t) => player.schedule(t + 0.35));
  script.arm();
  const t0 = performance.now();
  const buf = await ctx.startRendering();
  const renderSeconds = (performance.now() - t0) / 1000;
  const out = [];
  for (let k = 0; k < stems.length; k++) {
    const l = buf.getChannelData(2 * k);
    const r = buf.getChannelData(2 * k + 1);
    let data: Float32Array;
    let seam: Record<string, number> | null = null;
    // Posted with MARGIN frames of the lead-in before it, for the downsampler.
    const a = S0 - MARGIN;
    if (def.loop) {
      const b = S0 + I + B + Hs;
      data = interleave(l, r, a, b);
      // How far the steady state before the wrap is from the stretch that leads into the loop start
      // (residual tails plus the sub-sample shift), against the stem's average level.
      const w = Math.round(2 * sr);
      let eAll = 0;
      for (let i = S0; i < b; i++) eAll += l[i] * l[i] + r[i] * r[i];
      eAll /= b - S0;
      let eDiff = 0;
      for (let i = 0; i < w; i++) {
        const p = b - w + i;
        const q = S0 + I + Hs - w + i;
        for (const ch of [l, r]) eDiff += (ch[p] - ch[q]) * (ch[p] - ch[q]);
      }
      eDiff /= w;
      // Crossfade the last X samples into the stretch that flows into the loop start.
      for (let i = 0; i < X; i++) {
        const wgt = (i + 1) / X;
        const p = b - X + i;
        const q = S0 + I + Hs - X + i;
        const j = (p - a) * 2;
        data[j] = l[p] * (1 - wgt) + l[q] * wgt;
        data[j + 1] = r[p] * (1 - wgt) + r[q] * wgt;
      }
      seam = { residualDb: 10 * Math.log10(Math.max(eDiff, 1e-20) / Math.max(eAll, 1e-20)) };
    } else {
      // Played once: the song and its full ring, the same length for every stem.
      data = interleave(l, r, a, end);
    }
    const lv = levels(data);
    const meta = {
      sr,
      channels: 2,
      frames: data.length / 2 - MARGIN,
      marginBefore: MARGIN,
      loop: def.loop,
      loopStart: def.loop ? I + Hs : 0,
      loopFrames: def.loop ? B : 0,
      tracks: counts[k],
    };
    await save(`music/${id}/${stems[k].name}`, data, meta);
    out.push({ name: stems[k].name, ...meta, ...lv, seam });
  }
  return { renderSeconds, stems: out, intro: I, body: B, head: Hs };
}

// ------------------------------------------------------------------ effects as recipes

type Bus = 'page' | 'stage' | 'ui';

export interface Entry {
  /** Seconds after the effect starts. */
  at: number;
  bus: Bus;
  vel: number;
  /** A note: instrument, pitch, sounding length (sustained or damped), attack skip. */
  voice?: string;
  /** A one-shot effect sample: id, variant (-1 any), playback rate. */
  sfx?: string;
  variant?: number;
  rate?: number;
}

export interface Recipe {
  e: Entry[];
  /** Music duck: depth, hold, release, at. */
  duck?: [number, number, number, number];
}

const NOW = 0.005;

export interface VoiceSpec {
  inst: InstId;
  midi: number;
  dur: number | null;
  skip: number | null;
}

const voiceKey = (inst: InstId, midi: number, dur?: number, skip?: number): string =>
  `${inst}:${midi}:${dur === undefined ? '' : +dur.toFixed(3)}:${skip === undefined ? '' : +skip.toFixed(3)}`;

/**
 * Runs the web build's own Sfx class against every harmony the songs use and
 * records what it would play: notes (as voices), one-shot samples, and music ducks.
 * Randomness inside effects (a few milliseconds of spread) is fixed at its middle.
 */
export function recordSfx(groups: number[]) {
  const recipes: Recipe[] = [];
  const recipeIndex = new Map<string, number>();
  const voices = new Map<string, VoiceSpec & { buses: Set<Bus> }>();
  const oneshots = new Map<string, Set<Bus>>();
  let cur: Recipe = { e: [] };
  let H: Harmony = harmonyObjs[0];
  const fakeCtx = { currentTime: 0 } as BaseAudioContext;
  const fakeMixer = {
    sfx: { page: { input: 'page' }, stage: { input: 'stage' } },
    ui: { input: 'ui' },
    duckMusic: (depth: number, hold: number, release: number, at: number) => {
      cur.duck = [depth, hold, release, +(at - NOW).toFixed(4)];
    },
  };
  const fx = new Sfx(fakeCtx, bank, fakeMixer as unknown as Mixer, null as unknown as VoicePool, {
    harmony: () => H,
    nextBeat: (at: number) => at,
  });
  const fxa = fx as unknown as Record<string, unknown>;
  fxa.one = (id: string, dest: Bus, when: number, vel: number, rate = 1, variant?: number) => {
    cur.e.push({ at: +(when - NOW).toFixed(4), bus: dest, vel: +vel.toFixed(4), sfx: id, variant: variant ?? -1, rate: +rate.toFixed(5) });
    if (!oneshots.has(id)) oneshots.set(id, new Set());
    oneshots.get(id)!.add(dest);
  };
  fxa.note = (inst: InstId, midi: number, dest: Bus, when: number, vel: number, dur?: number, skip?: number) => {
    const meta = INSTRUMENTS[inst];
    // As Sfx.note: sustained notes default to a second; struck notes ring unless given a length.
    const d = meta.sustain ? (dur ?? 1) : dur;
    const k = voiceKey(inst, midi, d, skip);
    if (!voices.has(k)) voices.set(k, { inst, midi, dur: d ?? null, skip: skip ?? null, buses: new Set() });
    voices.get(k)!.buses.add(dest);
    cur.e.push({ at: +(when - NOW).toFixed(4), bus: dest, vel: +(vel * meta.level).toFixed(4), voice: k });
  };
  const take = (fn: () => void, shift = 0, drop?: (e: Entry) => boolean): number => {
    cur = { e: [] };
    fn();
    if (shift) for (const e of cur.e) e.at = +(e.at - shift).toFixed(4);
    if (drop) cur.e = cur.e.filter((e) => !drop(e));
    cur.e.sort((a, b) => a.at - b.at);
    const k = JSON.stringify(cur);
    let i = recipeIndex.get(k);
    if (i === undefined) {
      i = recipes.length;
      recipes.push(cur);
      recipeIndex.set(k, i);
    }
    return i;
  };
  const rnd = Math.random;
  Math.random = () => 0.5;
  const table = [];
  try {
    for (let h = 0; h < harmonyObjs.length; h++) {
      H = harmonyObjs[h];
      const row: Record<string, unknown> = {};
      for (const mode of ['2d', '3d'] as const) {
        const m = mode === '2d' ? 'page' : 'stage';
        const ev = (e: GameEvent) => () => fx.handle(e, mode);
        row[m] = {
          note: [1, 2, 3, 4, 5, 6, 7].map((d) => take(ev({ t: 'note', id: 0, count: d, total: 7 }))),
          // The first click plays at once; the rest waits for the next beat (offsets from that beat).
          checkpoint: take(ev({ t: 'checkpoint', id: 0 }), 0.08, (e) => e.sfx === 'metronome' && e.variant === 0),
          death: take(ev({ t: 'death', cause: 'thorn', pos: { x: 0, y: 0, z: 0 } } as GameEvent)),
          respawn: take(ev({ t: 'respawn' })),
          switch: [false, true].map((embedded) => take(ev({ t: 'switch', mode, embedded }))),
          bounce: take(ev({ t: 'bounce', id: 0 })),
          keyOn: groups.map((g) => take(ev({ t: 'key', id: 0, group: g, on: true }))),
          keyOff: groups.map((g) => take(ev({ t: 'key', id: 0, group: g, on: false }))),
          gateOn: take(ev({ t: 'gate', group: 0, on: true })),
          gateOff: take(ev({ t: 'gate', group: 0, on: false })),
          exit: take(ev({ t: 'exit' })),
        };
      }
      // A jump plucks the next chord tone between G4 and G5 (the engine cycles through them).
      const tones = (fx as unknown as { tones: (h: Harmony, lo: number, hi: number) => number[] }).tones.bind(fx);
      const note = fxa.note as (...a: unknown[]) => void;
      cur = { e: [] };
      row.jump = tones(H, 67, 79).map((n) => {
        note('pizz', n, 'page', NOW + 0.01, 0.16);
        note('harp', n, 'stage', NOW + 0.01, 0.11);
        return cur.e.slice(-2);
      });
      const ui: Record<string, number> = {};
      for (const s of ['confirm', 'back', 'pause', 'resume', 'start', 'complete', 'unlock'] as const) ui[s] = take(() => fx.ui(s));
      row.ui = ui;
      table.push(row);
    }
    // One-shots the engine plays directly (not through a recipe).
    for (const m of ['stone', 'brick', 'wood', 'brass', 'dark', 'crystal', 'leaf', 'marble']) {
      oneshots.set(`step.page.${m}`, new Set<Bus>(['page']));
      oneshots.set(`step.stage.${m}`, new Set<Bus>(['stage']));
    }
    for (const [id, bus] of [
      ['jump.page', 'page'],
      ['jump.stage', 'stage'],
      ['land.page', 'page'],
      ['land.stage', 'stage'],
      ['bonk.page', 'page'],
      ['bonk.stage', 'stage'],
      ['metronome', 'page'],
      ['metronome', 'stage'],
      ['tap', 'ui'],
      ['pageturn', 'ui'],
    ] as [string, Bus][]) {
      if (!oneshots.has(id)) oneshots.set(id, new Set());
      oneshots.get(id)!.add(bus);
    }
  } finally {
    Math.random = rnd;
  }
  return {
    recipes,
    table,
    voices: [...voices].map(([k, v]) => ({ key: k, inst: v.inst, midi: v.midi, dur: v.dur, skip: v.skip, buses: [...v.buses] })),
    oneshots: [...oneshots].map(([id, b]) => ({ id, variants: SFX_DEFS[id]?.variants ?? 1, buses: [...b] })),
  };
}

// ------------------------------------------------------------------ voices and one-shots

export interface ShotSpec {
  name: string;
  bus: Bus | 'amb' | 'dry';
  /** A note (voice key fields) or a one-shot sample. */
  inst?: InstId;
  midi?: number;
  dur?: number | null;
  skip?: number | null;
  sfx?: string;
  variant?: number;
}

/**
 * Renders single sounds exactly as the web build plays them (VoicePool envelopes,
 * zone and rate, release), at unit velocity, through a bus of the real desk (dry plus
 * its room or hall send) or dry. `pre` seconds of silence lead each sound so the
 * native engine can place it with sub-frame accuracy.
 */
export async function renderShots(list: ShotSpec[], o: { pre: number }) {
  const sr = RENDER_SR;
  const jobs = [];
  for (const s of list) {
    if (s.inst) jobs.push(...zoneJobs(s.inst, [s.midi!]));
    else jobs.push({ kind: 'sfx' as const, id: s.sfx!, variant: s.variant! });
  }
  await bank.need(jobs, PRIO.now);
  const out = [];
  for (const s of list) {
    const tailFor = s.bus === 'stage' || s.bus === 'amb' ? 3.5 : s.bus === 'dry' ? 0.1 : 1.0;
    let len = 0;
    if (s.inst) {
      const ns = bank.note(s.inst, s.midi!)!;
      const meta = INSTRUMENTS[s.inst];
      const natural = ns.buffer.duration / ns.rate;
      len = s.dur !== null && s.dur !== undefined ? Math.min(natural, s.dur + meta.release * 1.6 + 0.05) : natural;
      if (meta.sustain) len = (s.dur ?? 1) + meta.release * 1.6 + 0.05;
    } else {
      const sm = bank.sfx(s.sfx!, s.variant!)!;
      len = sm.buffer.duration;
    }
    const frames = snapUp(Math.ceil((o.pre + len + tailFor) * sr));
    const ctx = new OfflineAudioContext(2, frames, sr);
    const sink = ctx.createGain();
    const m = desk(ctx, sink);
    const pool = new VoicePool(ctx, 8);
    let dest: AudioNode;
    if (s.bus === 'dry') {
      const g = ctx.createGain();
      g.channelCount = 2;
      g.channelCountMode = 'explicit';
      g.connect(ctx.destination);
      dest = g;
    } else {
      tap(ctx, m).connect(ctx.destination);
      dest = s.bus === 'page' ? m.sfx.page.input : s.bus === 'stage' ? m.sfx.stage.input : s.bus === 'ui' ? m.ui.input : m.amb.input;
    }
    const fx = new Sfx(ctx, bank, m, pool, { harmony: () => harmonyObjs[0], nextBeat: (at: number) => at });
    const fxa = fx as unknown as Record<string, (...a: unknown[]) => void>;
    if (s.inst) {
      // Sfx.note multiplies by the instrument level; the recipes carry it, so render at unit gain.
      fxa.note(s.inst, s.midi, dest, o.pre, 1 / INSTRUMENTS[s.inst].level, s.dur ?? undefined, s.skip ?? undefined);
    } else fxa.one(s.sfx, dest, o.pre, 1, 1, s.variant);
    const buf = await ctx.startRendering();
    const l = buf.getChannelData(0);
    const r = buf.getChannelData(1);
    // Trim the tail once it is 66 dB under the sound's peak (and under -80 dBFS at unit velocity).
    let peak = 0;
    for (let i = 0; i < frames; i++) peak = Math.max(peak, Math.abs(l[i]), Math.abs(r[i]));
    const floor = Math.max(1e-4, peak * Math.pow(10, -66 / 20));
    let last = frames - 1;
    while (last > 0 && Math.abs(l[last]) < floor && Math.abs(r[last]) < floor) last--;
    const n = Math.min(frames, snapUp(last + Math.round(0.08 * sr)));
    // Fade the last 80 ms so a trimmed tail never clicks.
    const fade = Math.min(n, Math.round(0.08 * sr));
    for (let i = 0; i < fade; i++) {
      const g = i / fade;
      l[n - 1 - i] *= g;
      r[n - 1 - i] *= g;
    }
    let mono = true;
    for (let i = 0; i < n && mono; i++) if (Math.abs(l[i] - r[i]) > 1e-6) mono = false;
    const data = mono ? l.slice(0, n) : interleave(l, r, 0, n);
    const lv = levels(data);
    const meta = { sr, channels: mono ? 1 : 2, frames: n, pre: o.pre, loop: false };
    await save(s.name, data, meta);
    out.push({ name: s.name, ...meta, ...lv });
  }
  return out;
}

// ------------------------------------------------------------------ ambience beds

/**
 * Renders each movement's noise beds (filters, slow level LFOs and drifting cutoffs,
 * through the ambience bus and its hall send) at full level, then loops them with an
 * equal-power crossfade. The sparse events (birds, drips, crickets) are separate
 * one-shots that the native engine scatters as the web build does.
 */
export async function renderBeds(ids: AmbienceId[], o: { seconds: number; xfade: number; settle: number }) {
  const sr = RENDER_SR;
  const out = [];
  for (const id of ids) {
    const L = snap(o.seconds);
    const X = Math.round(o.xfade * sr);
    const S = Math.round(o.settle * sr);
    const ctx = new OfflineAudioContext(2, S + L + X + 128, sr);
    const sink = ctx.createGain();
    const m = desk(ctx, sink);
    tap(ctx, m).connect(ctx.destination);
    const amb = new Ambience(ctx, bank, new VoicePool(ctx, 8), m);
    await bank.need(
      [
        { kind: 'sfx', id: 'noise.pink', variant: 0 },
        { kind: 'sfx', id: 'noise.brown', variant: 0 },
      ],
      PRIO.now,
    );
    amb.start(id, 0);
    // Let the bank promise inside start() resolve so the beds are wired before rendering.
    await new Promise((res) => setTimeout(res, 50));
    const buf = await ctx.startRendering();
    const l = buf.getChannelData(0);
    const r = buf.getChannelData(1);
    const data = new Float32Array(L * 2);
    for (let i = 0; i < L; i++) {
      let a = l[S + i];
      let b = r[S + i];
      if (i < X) {
        // The stretch after the loop's end, faded out, over the loop's start, faded in.
        const g = (i + 0.5) / X;
        const gi = Math.sin((g * Math.PI) / 2);
        const go = Math.cos((g * Math.PI) / 2);
        a = a * gi + l[S + L + i] * go;
        b = b * gi + r[S + L + i] * go;
      }
      data[i * 2] = a;
      data[i * 2 + 1] = b;
    }
    const lv = levels(data);
    const meta = { sr, channels: 2, frames: L, loop: true, loopStart: 0, loopFrames: L };
    await save(`amb/${id}`, data, meta);
    out.push({ name: `amb/${id}`, ...meta, ...lv });
  }
  return out;
}

/** The sparse events each ambience scatters (read from a live Ambience, so they match the web build). */
export async function ambienceEvents(ids: AmbienceId[]) {
  const ctx = new OfflineAudioContext(2, 128, 32000);
  const m = desk(ctx, ctx.createGain());
  const out: Record<string, unknown[]> = {};
  for (const id of ids) {
    const amb = new Ambience(ctx, bank, new VoicePool(ctx, 8), m);
    amb.start(id, 0);
    const voices = (amb as unknown as { voices: { spec: Record<string, unknown> }[] }).voices;
    const specs = [...new Set(voices.map((v) => v.spec))];
    out[id] = specs.map((s) => ({ ...s, variants: SFX_DEFS[s.id as string]?.variants ?? 1 }));
    amb.stop(0, 0);
  }
  return out;
}

/**
 * The web desk's master chain measured on a steady tone: the level after its compressor
 * and after its limiter, for each input level. Web Audio compressors add makeup gain
 * of their own, which the native master chain has to match.
 */
export async function masterCurve(levels: number[]) {
  const sr = 48000;
  const out = [];
  for (const lv of levels) {
    const ctx = new OfflineAudioContext(2, sr, sr);
    ctx.destination.channelInterpretation = 'discrete';
    const merger = ctx.createChannelMerger(2);
    merger.connect(ctx.destination);
    const final = ctx.createGain();
    final.connect(merger, 0, 0);
    const m = new Mixer(ctx, final);
    m.setVolumes({ master: 1, music: 1, sfx: 1 }, 0);
    m.comp.connect(merger, 0, 1);
    const osc = ctx.createOscillator();
    osc.frequency.value = 997;
    const g = ctx.createGain();
    g.gain.value = Math.pow(10, lv / 20);
    osc.connect(g).connect(m.pre);
    osc.start(0);
    const buf = await ctx.startRendering();
    const peak = (ch: number) => {
      const d = buf.getChannelData(ch);
      let p = 0;
      for (let i = Math.round(0.7 * sr); i < d.length; i++) p = Math.max(p, Math.abs(d[i]));
      return db(p);
    };
    out.push({ in: lv, comp: peak(1), out: peak(0) });
  }
  return out;
}

/**
 * The web build's own full mix of a scenario (its offline renderer: one clock, the
 * real desk with compressor and limiter), as a WAV, to compare with a Godot capture.
 */
export async function renderReference(o: RenderOpts) {
  const r = await webRenderSong({ ...o, wav: true });
  return { wav: r.wav!, lufs: r.analysis.lufs, peakDb: r.analysis.peakDb };
}

const harness = { renderReference, masterCurve, songInfo, fallbackHarmony, harmonyList, renderStems, recordSfx, renderShots, renderBeds, ambienceEvents };

declare global {
  interface Window {
    __port: typeof harness;
  }
}
window.__port = harness;

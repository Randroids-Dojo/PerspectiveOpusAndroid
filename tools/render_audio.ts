// Pre-renders all of the web build's music and sound for the native port.
//
//   ../PerspectiveOpus/node_modules/.bin/tsx tools/render_audio.ts [--only=music|sfx|amb] [--songs=a,b] [--keep-raw]
//
// Starts Vite on the web repo (no live reload), opens tools/audio/harness.ts in
// headless Chrome, and drives the web build's real audio code offline:
//   music   one stem per song, arrangement and restore layer, each exactly one loop
//           long after its intro (stems play in sync and loop at a shared offset)
//   sfx     every tonal effect recorded per harmony as a recipe of voices, the voices
//           themselves (notes with their room or hall), and every one-shot sample
//   amb     each movement's noise beds as seamless loops, plus the scattered events
//   reference (only when asked, --only=reference --songs=overture) the web build's own
//           mix of the switch scenario src/audio/dev/audio_test.tscn plays with
//           --switches, as WAVs in /tmp/opus-port-audio-ref, for analyze_capture.py
// Raw float32 goes to /tmp/opus-port-audio, tools/audio/encode.py turns it into Ogg
// Vorbis in assets/audio, and assets/audio/audio.json describes it all for
// src/audio/audio.gd. A report with levels and loop seams is printed and written to
// /tmp/opus-port-audio/report.json.

import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { createWriteStream, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import type { IncomingMessage, ServerResponse } from 'node:http';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const WEB = resolve(ROOT, '../PerspectiveOpus');
const RAW = process.env.RAW ?? '/tmp/opus-port-audio';
const OUT = join(ROOT, 'assets/audio');

const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const [k, v] = a.replace(/^--/, '').split('=');
    return [k, v ?? '1'];
  }),
);
const only = args.only ? new Set(String(args.only).split(',')) : null;
const want = (part: string) => !only || only.has(part);

const SONG_IDS = ['title', 'overture', 'adagio', 'scherzo', 'nocturne', 'toccata', 'finale', 'ending'] as const;
const songs = args.songs ? String(args.songs).split(',') : [...SONG_IDS];
const AMBIENCES = ['meadow', 'lake', 'village', 'garden', 'clock', 'hall'];

/** Sample rate of every file (the instruments themselves are 22 to 32 kHz). Renders run at
 *  48 kHz, the web build's own rate, and are downsampled (see harness.ts, RENDER_SR). */
const SR = 32000;
const RENDER_SR = 48000;
/** Render frames to file frames (render lengths are whole multiples of 3). */
const toFile = (frames: number) => (frames * SR) / RENDER_SR;
/** Seconds of silence before each effect sound, for sub-frame placement. */
const PRE = 0.06;
/** Effect sounds are rendered at unit velocity (a few peak just over full scale in the hall)
 *  and stored this much quieter; the engine multiplies velocities back up (sfx.gain). */
const SHOT_GAIN = 0.5;
/** Vorbis quality (libsndfile compression level: 0 best, 1 smallest). */
const Q = { music: Number(args.qmusic ?? 0.9), shots: Number(args.qshots ?? 0.86), amb: Number(args.qamb ?? 0.9) };

const req = createRequire(join(WEB, 'package.json'));
const { chromium } = req('playwright-core') as typeof import('playwright-core');
const vite = (await import(pathToFileURL(join(WEB, 'node_modules/vite/dist/node/index.js')).href)) as typeof import('vite');

mkdirSync(RAW, { recursive: true });

// ------------------------------------------------------------------ server

const harnessUrl = `/@fs${join(ROOT, 'tools/audio/harness.ts')}`;
const server = await vite.createServer({
  configFile: false,
  root: WEB,
  logLevel: 'warn',
  cacheDir: join(RAW, 'vite-cache'),
  define: { __APP_VERSION__: JSON.stringify('dev') },
  server: { port: 5246, strictPort: false, hmr: false, watch: null, fs: { allow: [WEB, join(ROOT, 'tools')] } },
  plugins: [
    {
      name: 'port-audio',
      configureServer(s) {
        s.middlewares.use((req: IncomingMessage, res: ServerResponse, next: () => void) => {
          const url = new URL(req.url ?? '/', 'http://x');
          if (url.pathname === '/__port_audio.html') {
            res.setHeader('content-type', 'text/html');
            res.end(`<!doctype html><meta charset="utf-8"><title>port audio</title><script type="module" src="${harnessUrl}"></script>`);
            return;
          }
          if (url.pathname === '/__save' && req.method === 'POST') {
            const name = url.searchParams.get('name')!;
            const meta = url.searchParams.get('meta')!;
            const file = join(RAW, `${name}.f32`);
            mkdirSync(dirname(file), { recursive: true });
            writeFileSync(join(RAW, `${name}.json`), meta);
            const ws = createWriteStream(file);
            req.pipe(ws);
            ws.on('finish', () => res.end('ok'));
            ws.on('error', (e) => {
              res.statusCode = 500;
              res.end(String(e));
            });
            return;
          }
          next();
        });
      },
    },
  ],
});
await server.listen();
const base = server.resolvedUrls!.local[0];

const browser = await chromium.launch({
  channel: process.env.CHANNEL ?? 'chrome',
  headless: true,
  args: ['--autoplay-policy=no-user-gesture-required'],
});
const page = await browser.newPage();
const problems: string[] = [];
page.on('console', (m) => {
  if (m.type() === 'error' || m.type() === 'warning') problems.push(`[${m.type()}] ${m.text()}`);
});
page.on('pageerror', (e) => problems.push(`[pageerror] ${e.message}`));
await page.goto(`${base}__port_audio.html`);
await page.waitForFunction(() => !!window.__port, null, { timeout: 60000 });

type Port = Window['__port'];
const call = <K extends keyof Port>(fn: K, ...a: Parameters<Port[K]>): Promise<Awaited<ReturnType<Port[K]>>> =>
  page.evaluate(([f, x]) => (window.__port[f as K] as (...y: unknown[]) => unknown)(...(x as unknown[])), [fn, a] as const) as never;

const t0 = Date.now();
const log = (...a: unknown[]) => console.log(`[${((Date.now() - t0) / 1000).toFixed(0).padStart(4)}s]`, ...a);
const report: Record<string, unknown> = {};
const encodeJobs: { raw: string; out: string; q: number; gain?: number }[] = [];
const fileOf = (name: string) => join(OUT, `${name}.ogg`);

// ------------------------------------------------------------------ the master chain

const curve = await call('masterCurve', [-40, -30, -20, -16, -12, -8, -4, 0]);
const low = curve[0];
const master = {
  // Makeup gain the web build's compressor and limiter add (Web Audio applies it automatically).
  compMakeupDb: +(low.comp - low.in).toFixed(2),
  limitMakeupDb: +(low.out - low.comp).toFixed(2),
  curve,
};
log(`master chain: compressor makeup ${master.compMakeupDb} dB, limiter makeup ${master.limitMakeupDb} dB`);
for (const c of curve) log(`  in ${String(c.in).padStart(4)} dB -> compressor ${c.comp.toFixed(2)} -> out ${c.out.toFixed(2)} dB`);

// ------------------------------------------------------------------ songs and harmony

const infos: Record<string, Awaited<ReturnType<Port['songInfo']>>> = {};
for (const id of SONG_IDS) infos[id] = await call('songInfo', id as never);
const keys = new Map<string, { tonic: number; mode: string }>();
const harmonies0 = await call('harmonyList');
for (const h of harmonies0) keys.set(JSON.stringify(h.key), h.key);
keys.set(JSON.stringify({ tonic: 63, mode: 'major' }), { tonic: 63, mode: 'major' });
const fallback: Record<string, number> = {};
for (const [k, key] of keys) fallback[k] = await call('fallbackHarmony', key as never);
// Every harmony the songs use, then each key's tonic (the effects' fallback with no music).
const harmonies = await call('harmonyList');

/** Stems for a song: one per arrangement and layer, or one per arrangement for always-full songs. */
function stemsOf(id: string) {
  const info = infos[id];
  const out: { name: string; arr: 'score' | 'stage'; layers: number[]; layer: number; fade: number }[] = [];
  for (const arr of ['score', 'stage'] as const) {
    const tracks = info.tracks.filter((t) => t.arr === arr);
    if (info.full) {
      out.push({ name: `${arr}`, arr, layers: [...new Set(tracks.map((t) => t.layer))], layer: 0, fade: 2.4 });
      continue;
    }
    for (const layer of [...new Set(tracks.map((t) => t.layer))].sort((a, b) => a - b)) {
      const fades = tracks.filter((t) => t.layer === layer).map((t) => t.fade);
      out.push({ name: `${arr}_${layer}`, arr, layers: [layer], layer, fade: Math.max(...fades) });
    }
  }
  return out;
}

// ------------------------------------------------------------------ music

const music: Record<string, unknown> = {};
if (want('music')) {
  const stemReport: Record<string, unknown> = {};
  for (const id of songs) {
    const stems = stemsOf(id);
    const opts = { head: 8, xfade: 0.03, lead: 0.25, tail: 7 };
    // Four stems (eight channels) per offline pass keeps memory modest; passes run side by side.
    const groups: (typeof stems)[] = [];
    for (let i = 0; i < stems.length; i += 4) groups.push(stems.slice(i, i + 4));
    const results = await Promise.all(groups.map((g) => call('renderStems', id as never, g.map(({ name, arr, layers }) => ({ name, arr, layers })), opts)));
    const r0 = results[0];
    const flat = results.flatMap((r) => r.stems);
    log(`${id}: ${flat.length} stems in ${results.map((r) => r.renderSeconds.toFixed(1)).join('+')} s`);
    for (const s of flat) {
      log(
        `  ${s.name.padEnd(9)} tracks ${s.tracks}  peak ${s.peakDb.toFixed(1).padStart(6)}  rms ${s.rmsDb.toFixed(1).padStart(6)}` +
          (s.seam ? `  wrap residual ${s.seam.residualDb.toFixed(1)} dB` : ''),
      );
      encodeJobs.push({ raw: join(RAW, `music/${id}/${s.name}`), out: fileOf(`music/${id}/${s.name}`), q: Q.music });
    }
    stemReport[id] = flat;
    const info = infos[id];
    music[id] = {
      loop: info.loop,
      full: info.full,
      bpm: info.bpm,
      meter: info.meter,
      ambience: info.ambience,
      sr: SR,
      // Frames: the intro, then `head` frames of the body before the loop region, then one body.
      introFrames: toFile(r0.intro),
      headFrames: toFile(r0.head),
      bodyFrames: toFile(r0.body),
      loopStart: info.loop ? toFile(r0.intro + r0.head) : 0,
      frames: toFile(flat[0].frames),
      intro: info.intro && { duration: info.intro.duration, beats: info.intro.beats, tempo: info.intro.tempo, chords: info.intro.chords.map((c) => [c.t, c.h]) },
      body: { duration: info.body.duration, beats: info.body.beats, tempo: info.body.tempo, chords: info.body.chords.map((c) => [c.t, c.h]) },
      stems: stems.map((s) => ({ file: `music/${id}/${s.name}.ogg`, arr: s.arr, layer: s.layer, fade: s.fade })),
    };
  }
  report.music = stemReport;
}

// ------------------------------------------------------------------ effects

let sfxData: Record<string, unknown> | null = null;
if (want('sfx')) {
  // Key groups in the levels run 1 to 9; record a few more so a new level cannot fall off the table.
  const groupsUsed = Array.from({ length: 16 }, (_, i) => i);
  const rec = await call('recordSfx', groupsUsed);
  log(`effects: ${rec.recipes.length} recipes over ${rec.table.length} harmonies, ${rec.voices.length} voices, ${rec.oneshots.length} one-shot ids`);
  const shots: Parameters<Port['renderShots']>[0] = [];
  const voiceFiles: Record<string, Record<string, string>> = {};
  const safe = (s: string) => s.replace(/[.:]/g, '_');
  for (const v of rec.voices) {
    voiceFiles[v.key] = {};
    for (const bus of v.buses) {
      const tag = `${v.inst}_${v.midi}` + (v.dur !== null ? `_d${v.dur}` : '') + (v.skip !== null ? `_s${v.skip}` : '') + `_${bus}`;
      const name = `notes/${safe(tag)}`;
      voiceFiles[v.key][bus] = `${name}.ogg`;
      shots.push({ name, bus, inst: v.inst as never, midi: v.midi, dur: v.dur, skip: v.skip });
    }
  }
  const shotFiles: Record<string, Record<string, string[]>> = {};
  for (const o of rec.oneshots) {
    shotFiles[o.id] = {};
    for (const bus of o.buses) {
      shotFiles[o.id][bus] = [];
      for (let v = 0; v < o.variants; v++) {
        const name = `sfx/${safe(o.id)}_${v}_${bus}`;
        shotFiles[o.id][bus].push(`${name}.ogg`);
        shots.push({ name, bus, sfx: o.id, variant: v });
      }
    }
  }
  const ambEvents = await call('ambienceEvents', AMBIENCES as never);
  const eventIds = new Map<string, number>();
  for (const list of Object.values(ambEvents)) for (const e of list as { id: string; variants: number }[]) eventIds.set(e.id, e.variants);
  const eventFiles: Record<string, string[]> = {};
  for (const [id, n] of eventIds) {
    eventFiles[id] = [];
    for (let v = 0; v < n; v++) {
      const name = `amb/${safe(id)}_${v}`;
      eventFiles[id].push(`${name}.ogg`);
      shots.push({ name, bus: 'amb', sfx: id, variant: v });
    }
  }
  // Render in a few parallel batches.
  const batches: (typeof shots)[] = [[], [], [], []];
  shots.forEach((s, i) => batches[i % batches.length].push(s));
  const rendered = (await Promise.all(batches.map((b) => call('renderShots', b, { pre: PRE })))).flat();
  log(`rendered ${rendered.length} effect sounds`);
  for (const s of rendered) encodeJobs.push({ raw: join(RAW, s.name), out: fileOf(s.name), q: Q.shots, gain: SHOT_GAIN });
  report.shots = rendered;
  sfxData = {
    pre: PRE,
    gain: 1 / SHOT_GAIN,
    recipes: rec.recipes,
    table: rec.table,
    voices: voiceFiles,
    oneshots: shotFiles,
    ambience: { events: ambEvents, files: eventFiles },
  };
}

// ------------------------------------------------------------------ ambience beds

let beds: Record<string, string> | null = null;
if (want('amb')) {
  const r = await call('renderBeds', AMBIENCES as never, { seconds: 36, xfade: 4, settle: 8 });
  beds = {};
  for (const b of r) {
    log(`  ${b.name.padEnd(12)} peak ${b.peakDb.toFixed(1)}  rms ${b.rmsDb.toFixed(1)}`);
    encodeJobs.push({ raw: join(RAW, b.name), out: fileOf(b.name), q: Q.amb });
    beds[b.name.split('/')[1]] = `${b.name}.ogg`;
  }
  report.beds = r;
}

// ------------------------------------------------------------------ web references

if (only?.has('reference')) {
  const dir = process.env.REF ?? '/tmp/opus-port-audio-ref';
  mkdirSync(dir, { recursive: true });
  for (const id of songs)
    for (const restored of [7, 3]) {
      // Start on the stage; switch to the page and back twice, 0.8 s glides with the game's slow-down.
      const r = await call('renderReference', {
        song: id as never,
        seconds: 36,
        blend: 1,
        restored,
        switches: [6, 14, 22, 30].map((t, k) => ({ t, to: k % 2 === 0 ? 0 : 1 })),
      } as never);
      writeFileSync(join(dir, `${id}_r${restored}.wav`), Buffer.from(r.wav, 'base64'));
      log(`reference ${id} restored ${restored}: ${r.lufs.toFixed(1)} LUFS, peak ${r.peakDb.toFixed(1)} dB`);
    }
  await browser.close();
  await server.close();
  process.exit(0);
}

await browser.close();
await server.close();
if (problems.length) {
  log(`${problems.length} console messages from the page:`);
  for (const p of [...new Set(problems)].slice(0, 20)) log('  ' + p);
}

// ------------------------------------------------------------------ encode and describe

writeFileSync(join(RAW, 'encode.json'), JSON.stringify(encodeJobs.map((j) => ({ ...j, sr: SR }))));
log(`encoding ${encodeJobs.length} files`);
const enc = spawnSync('uv', ['run', '--no-project', '--quiet', '--with', 'soundfile', '--with', 'numpy', '--with', 'scipy', 'python', join(ROOT, 'tools/audio/encode.py'), join(RAW, 'encode.json'), join(RAW, 'encoded.json')], {
  stdio: 'inherit',
});
if (enc.status !== 0) throw new Error('encoding failed');
const encoded = JSON.parse(readFileSync(join(RAW, 'encoded.json'), 'utf8')) as { out: string; bytes: number; seam?: Record<string, number> }[];
report.encoded = encoded;

// Merge with what is already on disk when only part was rendered.
const manifestPath = join(OUT, 'audio.json');
const prev = existsSync(manifestPath) ? JSON.parse(readFileSync(manifestPath, 'utf8')) : {};
const manifest = {
  note: 'Generated by tools/render_audio.ts from the web build. Do not edit.',
  sr: SR,
  master,
  songs: { ...(prev.songs ?? {}), ...music },
  // Each harmony with `f`, the tonic of its key (what effects use once the music stops).
  harmonies: harmonies.map((h) => ({ ...h, f: fallback[JSON.stringify(h.key)] })),
  defaultHarmony: fallback[JSON.stringify({ tonic: 63, mode: 'major' })],
  sfx: sfxData ?? prev.sfx,
  beds: beds ?? prev.beds,
};
writeFileSync(manifestPath, JSON.stringify(manifest));
writeFileSync(join(RAW, 'report.json'), JSON.stringify(report, null, 1));

const total = encoded.reduce((n, e) => n + e.bytes, 0);
log(`wrote ${encoded.length} files, ${(total / 1048576).toFixed(2)} MB this run; manifest ${(readFileSync(manifestPath).length / 1024).toFixed(0)} KB`);
if (!args['keep-raw']) rmSync(RAW, { recursive: true, force: true });
process.exit(0);

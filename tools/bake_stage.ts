// Bakes the Stage (3D world) from the web build by running its own code in Chrome, so the
// native Stage draws exactly the same scene: every generated mesh, material and texture,
// the state each stage module animates from, the light rig and the studio environment.
//   ../PerspectiveOpus/node_modules/.bin/tsx tools/bake_stage.ts
//
// assets/data/stage/<level>__<palette>.json (+ .bin)   the built scene for one level start (.bin is zstd)
// assets/data/stage/dfg.json                            three.js's DFG table (split sum)
// assets/stage/detail.png, normal.png                   the block texture arrays, one layer per 128 rows
// assets/stage/sprites.png, clouds.png, moon.png        canvas atlases, stored flipped so uvs match
// assets/stage/env_<palette>.hdr                        the PMREM of each palette's environment
// assets/stage/<level>__<palette>_<n>.png               textures made for one level (the clock face)
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { build } from '../../PerspectiveOpus/node_modules/esbuild/lib/main.js';
import { chromium } from '../../PerspectiveOpus/node_modules/playwright-core/index.mjs';

/** Every level start the game makes: each movement in its palette, the title, the ending's title in the finale palette, the gallery. */
const BAKES: [string, string][] = [
  ['overture', 'dawn'],
  ['adagio', 'lake'],
  ['scherzo', 'autumn'],
  ['nocturne', 'night'],
  ['toccata', 'clock'],
  ['finale', 'finale'],
  ['title', 'title'],
  ['title', 'finale'],
  ['gallery', 'dawn'],
];
const PALETTE_IDS = ['dawn', 'lake', 'autumn', 'night', 'clock', 'finale', 'title'];

const here = fileURLToPath(new URL('.', import.meta.url));
const webModules = fileURLToPath(new URL('../../PerspectiveOpus/node_modules', import.meta.url));
const bundle = await build({
  entryPoints: [`${here}stage_bake_entry.ts`],
  bundle: true,
  format: 'iife',
  write: false,
  nodePaths: [webModules],
  logLevel: 'warning',
});
const code = bundle.outputFiles[0].text;

const browser = await chromium.launch({
  channel: 'chrome',
  headless: true,
  args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'],
});
const page = await browser.newPage({ viewport: { width: 844, height: 390 } });
page.on('pageerror', (e: Error) => console.log('[pageerror]', e.message));
page.on('console', (m: { type(): string; text(): string }) => {
  if (m.type() === 'error' || m.type() === 'warning') console.log('[page]', m.text());
});
await page.setContent('<html><body style="margin:0"></body></html>');
await page.addScriptTag({ content: code });

mkdirSync('assets/data/stage', { recursive: true });
mkdirSync('assets/stage', { recursive: true });

/** Import settings are written once; Godot then owns them (and the uid inside). */
const writeImport = (path: string, text: string): void => {
  if (!existsSync(path)) writeFileSync(path, text);
};
const savePng = (path: string, dataUrl: string): void => writeFileSync(path, Buffer.from(dataUrl.split(',')[1], 'base64'));

/** Godot import settings for a texture array made of `layers` square tiles stacked vertically. */
const arrayImport = (layers: number): string => `[remap]

importer="2d_array_texture"
type="CompressedTexture2DArray"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
slices/horizontal=1
slices/vertical=${layers}
`;

/** Godot import settings for a plain texture. */
const texImport = (mip: boolean): string => `[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=2
compress/channel_pack=0
mipmaps/generate=${mip}
mipmaps/limit=-1
roughness/mode=0
process/fix_alpha_border=false
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
`;

// A tiny PNG encoder for the texture arrays (RGBA8, no filtering, zlib from node).
import { constants as zc, deflateSync, zstdCompressSync } from 'node:zlib';
function crc32(buf: Uint8Array): number {
  let c = ~0;
  for (let i = 0; i < buf.length; i++) {
    c ^= buf[i];
    for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1));
  }
  return ~c >>> 0;
}
function png(w: number, h: number, rgba: Uint8Array): Buffer {
  const chunk = (type: string, data: Uint8Array) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type, 'ascii'), Buffer.from(data)]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(td));
    return Buffer.concat([len, td, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    Buffer.from(rgba.buffer, rgba.byteOffset + y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1);
  }
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw, { level: 9 })), chunk('IEND', new Uint8Array(0))]);
}

function halfToFloat(h: number): number {
  const s = h & 0x8000 ? -1 : 1;
  const e = (h >> 10) & 0x1f;
  const f = h & 0x3ff;
  if (e === 0) return s * Math.pow(2, -14) * (f / 1024);
  if (e === 31) return f ? NaN : s * Infinity;
  return s * Math.pow(2, e - 15) * (1 + f / 1024);
}

/** Radiance RGBE with run-length scanlines; the first scanline is image row 0. */
function hdr(w: number, h: number, rgb: Float32Array): Buffer {
  const head = Buffer.from(`#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y ${h} +X ${w}\n`, 'ascii');
  const out: Buffer[] = [head];
  const line = new Uint8Array(w * 4);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 3;
      const r = Math.max(0, rgb[i]);
      const g = Math.max(0, rgb[i + 1]);
      const b = Math.max(0, rgb[i + 2]);
      const m = Math.max(r, g, b);
      if (m < 1e-32) {
        line[x] = line[w + x] = line[2 * w + x] = line[3 * w + x] = 0;
        continue;
      }
      const e = Math.ceil(Math.log2(m) + 1e-9);
      const sc = Math.pow(2, -e) * 256;
      line[x] = Math.min(255, Math.floor(r * sc));
      line[w + x] = Math.min(255, Math.floor(g * sc));
      line[2 * w + x] = Math.min(255, Math.floor(b * sc));
      line[3 * w + x] = e + 128;
    }
    const enc: number[] = [2, 2, w >> 8, w & 255];
    for (let ch = 0; ch < 4; ch++) {
      for (let x = 0; x < w; x += 128) {
        const n = Math.min(128, w - x);
        enc.push(n);
        for (let k = 0; k < n; k++) enc.push(line[ch * w + x + k]);
      }
    }
    out.push(Buffer.from(enc));
  }
  return Buffer.concat(out);
}

// Shared textures.
{
  const sh = await page.evaluate(() => (window as any).bakeShared());
  for (const name of ['detail', 'normal'] as const) {
    const t = sh[name];
    const data = new Uint8Array(Buffer.from(t.b64, 'base64'));
    // Layers are stored one after another; a vertical strip keeps each layer's rows in order.
    writeFileSync(`assets/stage/${name}.png`, png(t.w, t.h * t.depth, data));
    writeImport(`assets/stage/${name}.png.import`, arrayImport(t.depth));
  }
  for (const name of ['sprites', 'clouds', 'moon'] as const) {
    savePng(`assets/stage/${name}.png`, sh[name]);
    writeImport(`assets/stage/${name}.png.import`, texImport(true));
  }
  console.log('baked shared textures');
}

// three.js's DFG table, straight from its source.
{
  const src = readFileSync(`${webModules}/three/src/renderers/shaders/DFGLUTData.js`, 'utf8');
  const hex = [...src.slice(src.indexOf('Uint16Array')).matchAll(/0x([0-9a-f]{4})/gi)].map((m) => halfToFloat(parseInt(m[1], 16)));
  writeFileSync('assets/data/stage/dfg.json', JSON.stringify({ size: 16, rg: hex.map((v) => Number(v.toPrecision(6))) }) + '\n');
}

// Environments.
for (const id of PALETTE_IDS) {
  const e = await page.evaluate(([lv, p]) => {
    (window as any).bakeStage(lv, p);
    return (window as any).bakeEnv(p);
  }, ['overture', id] as const);
  if (!e) {
    console.log('no environment for', id);
    continue;
  }
  const raw = new Uint16Array(new Uint8Array(Buffer.from(e.b64, 'base64')).buffer);
  const rgb = new Float32Array(e.w * e.h * 3);
  for (let i = 0; i < e.w * e.h; i++) for (let k = 0; k < 3; k++) rgb[i * 3 + k] = halfToFloat(raw[i * 4 + k]);
  writeFileSync(`assets/stage/env_${id}.hdr`, hdr(e.w, e.h, rgb));
  writeImport(`assets/stage/env_${id}.hdr.import`, texImport(false));
  console.log('baked env', id, e.w, 'x', e.h);
}

for (const [lv, pal] of BAKES) {
  const r = await page.evaluate(([l, p]) => (window as any).bakeStage(l, p), [lv, pal] as const);
  const name = `${lv}__${pal}`;
  r.texs.forEach((t: { name: string; png: string; mip: boolean }, i: number) => {
    const file = `assets/stage/${name}_${i}.png`;
    savePng(file, t.png);
    writeImport(`${file}.import`, texImport(t.mip));
    (t as { file?: string }).file = `res://${file}`;
    delete (t as { png?: string }).png;
  });
  // The arrays are very repetitive: zstd makes them about an eighth of the size.
  const bin = Buffer.from(r.bin, 'base64');
  delete r.bin;
  r.binSize = bin.length;
  const packed = zstdCompressSync(bin, { params: { [zc.ZSTD_c_compressionLevel]: 19 } });
  writeFileSync(`assets/data/stage/${name}.bin`, packed);
  const json = JSON.stringify(r);
  writeFileSync(`assets/data/stage/${name}.json`, json + '\n');
  console.log('baked', name, `json ${(json.length / 1024).toFixed(0)} KB, bin ${(packed.length / 1024).toFixed(0)} KB (${(bin.length / 1024).toFixed(0)} KB raw), ${r.nodes.length} nodes, ${r.geos.length} geometries, ${r.mats.length} materials`);
}
await browser.close();

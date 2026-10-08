// Bakes the page's canvas-made textures by running the web build's own generators in
// Chrome, so the native Score sits on exactly the same paper, patterns and backdrops.
//   ../PerspectiveOpus/node_modules/.bin/tsx tools/bake_page_textures.ts
//
// Per palette (assets/page/<palette>/): paper.png and vignette.png (made for the base
// screen 844x390 at 2x, stretched to other screens), the backdrop's two silhouette
// bands, staves, sky emblem and clouds (made at the base ppu, scaled by the page).
// Shared (assets/page/): white hatching masks for every pattern spacing and the
// watercolour wash masks; the page tints them with the palette's shade at runtime.
import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { build } from '../../PerspectiveOpus/node_modules/esbuild/lib/main.js';
import { chromium } from '../../PerspectiveOpus/node_modules/playwright-core/index.mjs';

const BASE_W = 844;
const BASE_H = 390;
const BASE_DPR = 2;
const BASE_PPU = Math.min(BASE_H / 12.5, BASE_W / 16);

const entry = `
import { PALETTES } from '../../PerspectiveOpus/src/game/palettes';
import { makeTones } from '../../PerspectiveOpus/src/render2d/tones';
import { Paper } from '../../PerspectiveOpus/src/render2d/paper';
import { Backdrop } from '../../PerspectiveOpus/src/render2d/backdrop';
import { hatchTile, washTile } from '../../PerspectiveOpus/src/render2d/ink';

const url = (c) => (c ? c.toDataURL('image/png') : null);

window.bakePalette = (id, w, h, dpr, ppu) => {
  const t = makeTones(PALETTES[id], 8);
  const paper = new Paper();
  paper.build(t, w, h, dpr);
  const bd = new Backdrop();
  bd.build(t, id, w, h, dpr, ppu);
  const bands = bd.bands.map((b) => ({ png: url(b.cv), tw: b.tw, th: b.th, skirt: b.skirt, fx: b.fx, fy: b.fy, lift: b.lift, base: b.base }));
  return {
    paper: url(paper.canvas),
    vignette: url(paper.vignette),
    staves: url(bd.staves),
    stavesTW: bd.stavesTW,
    stavesTH: bd.stavesTH,
    sky: url(bd.sky),
    clouds: url(bd.clouds),
    emblemFront: bd.emblemFront,
    rs: bd.rs,
    bands,
  };
};

// The pattern tiles exactly as makePatterns makes them, in white so the page can tint them.
window.bakePatterns = (sp) => {
  const dpr = sp / 4.2;
  const size = sp * 16;
  const white = 'rgb(255,255,255)';
  return {
    hatch: url(hatchTile(size, white, 0.5, sp, 0.9 * dpr, false, 11)),
    hatchInv: url(hatchTile(size, white, 0.55, sp, 0.9 * dpr, false, 11)),
    cross: url(hatchTile(size, white, 0.45, sp, 0.8 * dpr, true, 23)),
    crossInv: url(hatchTile(size, white, 0.5, sp, 0.8 * dpr, true, 23)),
    dense: url(hatchTile(Math.round(size * 0.75), white, 0.6, Math.max(2, Math.round(sp * 0.75)), 0.85 * dpr, true, 37)),
    light: url(hatchTile(size, white, 0.5, sp, 0.7 * dpr, false, 41)),
  };
};

window.bakeWash = (size, alpha, seed) => url(washTile(size, [255, 255, 255], alpha, seed));
`;

const here = fileURLToPath(new URL('.', import.meta.url));
const bundle = await build({
  stdin: { contents: entry, resolveDir: here, loader: 'ts' },
  bundle: true,
  format: 'iife',
  write: false,
  logLevel: 'warning',
});
const code = bundle.outputFiles[0].text;

const browser = await chromium.launch({ channel: 'chrome', headless: true });
const page = await browser.newPage({ viewport: { width: 64, height: 64 } });
page.on('pageerror', (e) => console.log('[pageerror]', e.message));
await page.setContent('<html><body></body></html>');
await page.addScriptTag({ content: code });

const save = (path: string, dataUrl: string | null): void => {
  if (!dataUrl) return;
  writeFileSync(path, Buffer.from(dataUrl.split(',')[1], 'base64'));
};

const PALETTE_IDS = ['dawn', 'lake', 'autumn', 'night', 'clock', 'finale', 'title'];
for (const id of PALETTE_IDS) {
  const dir = `assets/page/${id}`;
  mkdirSync(dir, { recursive: true });
  const r = await page.evaluate(([i, w, h, d, p]) => (window as any).bakePalette(i, w, h, d, p), [id, BASE_W, BASE_H, BASE_DPR, BASE_PPU] as const);
  save(`${dir}/paper.png`, r.paper);
  save(`${dir}/vignette.png`, r.vignette);
  save(`${dir}/staves.png`, r.staves);
  save(`${dir}/sky.png`, r.sky);
  save(`${dir}/clouds.png`, r.clouds);
  r.bands.forEach((b: { png: string }, i: number) => save(`${dir}/band${i}.png`, b.png));
  const manifest = {
    w: BASE_W,
    h: BASE_H,
    dpr: BASE_DPR,
    ppu: BASE_PPU,
    rs: r.rs,
    stavesTW: r.stavesTW,
    stavesTH: r.stavesTH,
    emblemFront: r.emblemFront,
    clouds: !!r.clouds,
    bands: r.bands.map(({ png: _png, ...rest }: { png: string }) => rest),
  };
  writeFileSync(`${dir}/backdrop.json`, JSON.stringify(manifest, null, 1) + '\n');
  console.log('baked', id);
}

mkdirSync('assets/page/patterns', { recursive: true });
for (let sp = 3; sp <= 18; sp++) {
  const r = await page.evaluate((s) => (window as any).bakePatterns(s), sp);
  for (const [name, png] of Object.entries(r)) save(`assets/page/patterns/${name}_${sp}.png`, png as string);
}
// Wash masks: the tile used on the page (alpha 0.15, or 0.2 on the Nocturne) and the
// one the backdrop granulates its bands with (made at 256 like the web build).
save('assets/page/patterns/wash.png', await page.evaluate(() => (window as any).bakeWash(512, 0.15, 7)));
save('assets/page/patterns/wash_inv.png', await page.evaluate(() => (window as any).bakeWash(512, 0.2, 7)));
save('assets/page/patterns/band_wash.png', await page.evaluate(() => (window as any).bakeWash(256, 0.1, 19)));
save('assets/page/patterns/band_wash_inv.png', await page.evaluate(() => (window as any).bakeWash(256, 0.22, 19)));
console.log('baked patterns');
await browser.close();

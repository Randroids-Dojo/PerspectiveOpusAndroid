// Renders the Android launcher icons from SVG.  ../PerspectiveOpus/node_modules/.bin/tsx tools/icons.ts
import { readFileSync } from 'node:fs';
import { chromium } from '../../PerspectiveOpus/node_modules/playwright-core/index.mjs';

const quaver = (fill: string, gold: string, scarf: string, eyes: boolean) => `
  <g transform="translate(137 85) scale(0.75)">
    <ellipse cx="66" cy="262" rx="74" ry="54" transform="rotate(-22 66 262)" fill="${fill}"/>
    ${eyes ? '<ellipse cx="44" cy="244" rx="18" ry="9" transform="rotate(-22 44 244)" fill="#fff" fill-opacity="0.35"/>' : ''}
    <rect x="124" y="30" width="22" height="236" rx="10" fill="${fill}" ${eyes ? `stroke="${gold}" stroke-width="5"` : ''}/>
    <path d="M140 30c12 50 78 66 70 140-4-40-36-66-70-70z" fill="${gold}"/>
    <path d="M118 258c18 6 36 2 52-8l6 14c-22 12-42 14-62 6z" fill="${scarf}"/>
    ${eyes ? '<circle cx="48" cy="250" r="12" fill="#fff"/><circle cx="84" cy="236" r="12" fill="#fff"/><circle cx="51" cy="252" r="5" fill="#141014"/><circle cx="87" cy="238" r="5" fill="#141014"/>' : ''}
  </g>`;
const defs = `<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2a1830"/><stop offset="1" stop-color="#0f0a14"/></linearGradient>
  <linearGradient id="page" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f6ecd2"/><stop offset="1" stop-color="#e3d2ad"/></linearGradient>
  <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fbe7b0"/><stop offset="0.5" stop-color="#e2b456"/><stop offset="1" stop-color="#a87a2c"/></linearGradient>
</defs>`;
const background = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 432 432">${defs}
  <rect width="432" height="432" fill="url(#bg)"/>
  <rect width="216" height="432" fill="url(#page)"/>
  <g stroke="#2b211c" stroke-opacity="0.18" stroke-width="4"><line x1="40" y1="150" x2="216" y2="150"/><line x1="40" y1="172" x2="216" y2="172"/><line x1="40" y1="194" x2="216" y2="194"/><line x1="40" y1="216" x2="216" y2="216"/><line x1="40" y1="238" x2="216" y2="238"/></g>
  <line x1="216" y1="0" x2="216" y2="432" stroke="#e2b456" stroke-width="3" stroke-opacity="0.7"/>
</svg>`;
const foreground = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 432 432">${defs}${quaver('#141014', 'url(#gold)', '#b2362b', true)}</svg>`;
const monochrome = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 432 432">${quaver('#fff', '#fff', '#fff', false)}</svg>`;
const main192 = readFileSync('../PerspectiveOpus/public/icon.svg', 'utf8');

const browser = await chromium.launch({ channel: 'chrome', headless: true });
async function render(svg: string, size: number, path: string) {
  const page = await browser.newPage({ viewport: { width: size, height: size } });
  await page.setContent(`<html><body style="margin:0;background:transparent">${svg.replace('<svg ', `<svg width="${size}" height="${size}" `)}</body></html>`);
  await page.screenshot({ path, omitBackground: true });
  await page.close();
}
await render(background, 432, 'assets/icons/adaptive_background.png');
await render(foreground, 432, 'assets/icons/adaptive_foreground.png');
await render(monochrome, 432, 'assets/icons/adaptive_monochrome.png');
await render(main192, 192, 'assets/icons/icon_192.png');
await render(main192, 512, 'icon.png');
await browser.close();
console.log('icons written');

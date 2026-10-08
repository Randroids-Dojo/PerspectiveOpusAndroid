// Composes the Play feature graphic (1024x500) from the web build's title scene on both worlds.
//   ../PerspectiveOpus/node_modules/.bin/tsx tools/store_feature.ts [url]
import { writeFileSync } from 'node:fs';
import { chromium } from '../../PerspectiveOpus/node_modules/playwright-core/index.mjs';

const url = process.argv[2] ?? 'https://perspective-opus.vercel.app/';
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--use-angle=metal', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 1024, height: 500 }, deviceScaleFactor: 2 });
await page.goto(url);
await page.addStyleTag({ content: '#ui, #boot { display: none !important; }' });
await page.waitForTimeout(2500);
await page.evaluate(() => {
  const app = (window as any).__opus;
  app.view.focus = { x: 22, y: 9.6, z: 4 };
});
await page.waitForTimeout(1500);
const stage = (await page.screenshot()).toString('base64');
await page.evaluate(() => (window as any).__opus.game.toggleMode());
await page.waitForTimeout(2200);
const score = (await page.screenshot()).toString('base64');
const html = `<html><head><style>
  @import url('https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@1,500;1,600&display=swap');
  body{margin:0;width:1024px;height:500px;position:relative;overflow:hidden;background:#000}
  img{position:absolute;inset:0;width:1024px;height:500px}
  .score{clip-path:polygon(0 0,560px 0,470px 500px,0 500px)}
  .seam{position:absolute;inset:0;background:linear-gradient(101deg,transparent 49.6%,rgba(230,196,124,.9) 49.8%,rgba(230,196,124,.9) 50%,transparent 50.2%)}
  .mark{position:absolute;left:0;right:0;top:118px;text-align:center;font-family:'Cormorant Garamond',serif;font-style:italic;color:#fff8e0;text-shadow:0 3px 18px rgba(0,0,0,.6),0 1px 2px rgba(0,0,0,.6)}
  .w1{font-size:66px;font-weight:500;line-height:1}
  .w2{font-size:124px;font-weight:600;line-height:.9;color:#f2d48c}
  .k{font:500 15px Georgia;letter-spacing:.3em;text-transform:uppercase;color:#fff3d6;margin-top:10px;text-shadow:0 1px 6px rgba(0,0,0,.8)}
</style></head><body>
<img src="data:image/png;base64,${stage}"><img class="score" src="data:image/png;base64,${score}"><div class="seam"></div>
<div class="mark"><div class="w1">Perspective</div><div class="w2">Opus</div><div class="k">A symphony in two worlds</div></div>
</body></html>`;
const comp = await browser.newPage({ viewport: { width: 1024, height: 500 }, deviceScaleFactor: 1 });
await comp.setContent(html, { waitUntil: 'networkidle' });
await comp.waitForTimeout(800);
await comp.screenshot({ path: 'docs/store/feature.png' });
writeFileSync('docs/store/.keep', '');
await browser.close();
console.log('docs/store/feature.png');

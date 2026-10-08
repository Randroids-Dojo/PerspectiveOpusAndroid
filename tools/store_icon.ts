// Full-bleed 512x512 Play Store icon from the adaptive layers (Play applies its own mask).
//   ../PerspectiveOpus/node_modules/.bin/tsx tools/store_icon.ts
import { readFileSync } from 'node:fs';
import { chromium } from '../../PerspectiveOpus/node_modules/playwright-core/index.mjs';

const b64 = (p: string) => readFileSync(p).toString('base64');
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const page = await browser.newPage({ viewport: { width: 512, height: 512 } });
await page.setContent(`<html><body style="margin:0">
  <img src="data:image/png;base64,${b64('assets/icons/adaptive_background.png')}" style="position:absolute;inset:0;width:512px;height:512px">
  <img src="data:image/png;base64,${b64('assets/icons/adaptive_foreground.png')}" style="position:absolute;left:-40px;top:-40px;width:592px;height:592px">
</body></html>`);
await page.waitForTimeout(300);
await page.screenshot({ path: 'docs/store/icon-512.png' });
await browser.close();
console.log('docs/store/icon-512.png');

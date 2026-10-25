// Measures frame rate at 1280x800 at each screenshot location (GPU headless Chrome/Edge).
import { createServer } from 'vite';
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const exe = [process.env.CHROME_PATH, 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', '/usr/bin/google-chrome'].filter(Boolean).find((p) => fs.existsSync(p));
const server = await createServer({ root, configFile: path.join(root, 'vite.config.js'), logLevel: 'warn' });
await server.listen();
const browser = await chromium.launch({ executablePath: exe, headless: !process.argv.includes('--headed'),
  args: ['--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist', '--disable-gpu-vsync', '--disable-frame-rate-limit'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1 });
await page.goto(`http://localhost:${server.config.server.port}/`);
await page.waitForFunction(() => typeof window.__placePlayer === 'function', null, { timeout: 60000 });
const pts = [[0, 1.4], [-2.4, -0.6], [6, 3], [22.4, 2.5], [28, -4.8]];
for (const [x, z] of pts) {
  await page.evaluate(([x, z]) => window.__placePlayer(x, z), [x, z]);
  await page.waitForTimeout(3500);
  const fps = await page.evaluate(() => window.__fps);
  console.log(`(${x}, ${z})  ${fps.toFixed(1)} fps`);
}
await browser.close();
await server.close();

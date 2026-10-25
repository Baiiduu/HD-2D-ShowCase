// Automated screenshot capture: starts the Vite dev server, drives a GPU-enabled headless
// Chrome/Edge via playwright-core, and the page saves 1280x800 PNGs into ./screenshots.
// Usage: npm run shots            (all five)
//        npm run shots -- 3       (only shot 3)
import { createServer } from 'vite';
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const which = process.argv[2] || 'all';
const headed = process.argv.includes('--headed');

function findBrowser() {
  const c = [
    process.env.CHROME_PATH,
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
    'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser',
  ].filter(Boolean);
  return c.find((p) => fs.existsSync(p));
}

const server = await createServer({ root, configFile: path.join(root, 'vite.config.js'), logLevel: 'warn' });
await server.listen();
const extra = process.argv.find((a) => a.startsWith('--q='))?.slice(4) || '';
const url = `http://localhost:${server.config.server.port}/?shots=${which}${extra ? '&' + extra : ''}`;
const executablePath = findBrowser();
if (!executablePath) { console.error('No Chrome/Edge found; set CHROME_PATH'); process.exit(1); }
const browser = await chromium.launch({
  executablePath, headless: !headed,
  args: ['--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist', '--enable-webgl', '--disable-gpu-sandbox', '--force-device-scale-factor=1'],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1 });
page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') console.log('[page]', m.type(), m.text().slice(0, 400)); });
page.on('pageerror', (e) => console.log('[pageerror]', e.message));
console.log('opening', url);
await page.goto(url);
const gpu = await page.evaluate(() => {
  const gl = document.createElement('canvas').getContext('webgl2');
  const ext = gl && gl.getExtension('WEBGL_debug_renderer_info');
  return ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : 'unknown';
});
console.log('GPU:', gpu);
await page.waitForFunction(() => window.__done === true, null, { timeout: 300000 });
console.log('saved to', path.join(root, 'screenshots'));
await browser.close();
await server.close();

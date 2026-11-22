/* Checks the player in a browser with no window: serves it with one scene (serve.mjs), opens it in headless Chromium with WebGPU at
   the 1472 by 1056 window that gives the kit's 1440 by 960 stage, waits for the ready flag, confirms two pictures of the stage a
   second apart differ (it plays), saves a screenshot of the page, prints the page's console errors and warnings, stops the server and
   confirms the port is free again. Exits 0 only when all of that holds. Playwright is not one of the player's packages: install it
   into this folder first (references/proof.md, 3).

     node player/check.mjs <scene.bin> <still.png> <screenshot.png> [port] */
import { spawn } from 'node:child_process';
import { createConnection } from 'node:net';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const [sceneFile, stillFile, shotFile, port = '4173'] = process.argv.slice(2);
if (!sceneFile || !stillFile || !shotFile) {
  console.error('usage: node player/check.mjs <scene.bin> <still.png> <screenshot.png> [port]');
  process.exit(2);
}

const listening = () =>
  new Promise(done => {
    const socket = createConnection({ host: '127.0.0.1', port: Number(port) });
    socket.once('connect', () => (socket.destroy(), done(true)));
    socket.once('error', () => done(false));
  });

if (await listening()) {
  console.error(`port ${port} is already in use`);
  process.exit(1);
}

const server = spawn(process.execPath, [join(dirname(fileURLToPath(import.meta.url)), 'serve.mjs'), sceneFile, stillFile, port], {
  stdio: ['ignore', 'pipe', 'inherit']
});
await new Promise((started, failed) => {
  server.stdout.once('data', words => (console.log(`server: ${String(words).trim()}`), started()));
  server.once('exit', code => failed(new Error(`the server stopped (${code})`)));
});

const messages = [];
let ready, plays;
const browser = await chromium.launch({
  headless: true,
  args: ['--enable-unsafe-webgpu', ...(process.platform === 'darwin' ? ['--use-angle=metal'] : [])]
});
try {
  const page = await browser.newPage({ viewport: { width: 1472, height: 1056 } });
  page.on('console', m => ['error', 'warning'].includes(m.type()) && messages.push(`${m.type()}: ${m.text()}`));
  page.on('pageerror', e => messages.push(`page error: ${e.message}`));
  const t0 = Date.now();
  await page.goto(`http://127.0.0.1:${port}/`);
  await page.waitForSelector('.stage[data-ready]', { timeout: 30000 });
  ready = await page.getAttribute('.stage', 'data-ready');
  console.log(`ready flag: "${ready}" after ${Date.now() - t0} ms`);
  const canvas = await page.evaluate(() => {
    const c = document.querySelector('canvas');
    return `${c.clientWidth} by ${c.clientHeight}, drawing buffer ${c.width} by ${c.height}`;
  });
  console.log(`canvas: ${canvas}`);
  await page.waitForTimeout(500); // past the canvas's fade in
  const stage = page.locator('.stage'),
    first = await stage.screenshot();
  await page.waitForTimeout(1000);
  plays = !first.equals(await stage.screenshot());
  console.log(`two pictures of the stage a second apart differ: ${plays}`);
  await page.screenshot({ path: shotFile });
  console.log(`screenshot: ${shotFile}`);
} finally {
  await browser.close();
  server.kill();
  await new Promise(stopped => (server.exitCode === null ? server.once('exit', stopped) : stopped()));
}
console.log(`console errors and warnings: ${messages.length}`);
for (const m of messages) console.log(`  ${m}`);
const stillListening = await listening();
console.log(`server stopped; port ${port} ${stillListening ? 'is still in use' : 'is free'}`);
process.exit(ready === 'true' && plays && !messages.length && !stillListening ? 0 : 1);

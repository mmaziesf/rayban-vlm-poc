// Local approximation of the Meta Ray-Ban Display Simulator QA checklist + perf scorecard.
// NOT a substitute for the real Chrome extension. Usage: node qa.mjs http://127.0.0.1:8765/
import puppeteer from 'puppeteer-core';
const url = process.argv[2] || 'http://127.0.0.1:8765/';
const results = []; const ok = (name, pass, info='') => results.push({ name, pass, info });
const browser = await puppeteer.launch({ executablePath: '/usr/bin/google-chrome', headless: 'new',
  args: ['--no-sandbox', '--enable-precise-memory-info'] });
const page = await browser.newPage();
await page.setViewport({ width: 600, height: 600 });
let bytes = 0; page.on('response', async r => { try { bytes += (await r.buffer()).length; } catch {} });
const errors = []; page.on('pageerror', e => errors.push(e.message));
const t0 = Date.now(); await page.goto(url, { waitUntil: 'load' }); const loadMs = Date.now() - t0;

const head = await page.evaluate(() => ({
  viewport: document.querySelector('meta[name=viewport]')?.content || '',
  icon: document.querySelector('link[rel~=icon]')?.href || '',
  mrbd: document.querySelector('meta[name=mrbd-web-app-capable]')?.content || '',
}));
ok('viewport meta', /width=600/.test(head.viewport), head.viewport);
const iconSize = await page.evaluate(async (u) => { if (!u) return null; const i = new Image(); i.src = u; await i.decode(); return [i.naturalWidth, i.naturalHeight, u.endsWith('.svg')]; }, head.icon);
ok('favicon PNG >=52px', !!iconSize && iconSize[0] >= 52 && !iconSize[2], JSON.stringify(iconSize));
ok('mrbd-web-app-capable meta', head.mrbd === 'yes');

const overflow = await page.evaluate(() => {
  const d = document.documentElement; const bad = [];
  document.querySelectorAll('body *').forEach(el => { const r = el.getBoundingClientRect(); if (r.right > 600.5 || r.left < -0.5) bad.push(el.tagName + '#' + el.id); });
  return { sw: d.scrollWidth, cw: d.clientWidth, bad };
});
ok('no horizontal overflow', overflow.sw <= overflow.cw && overflow.bad.length === 0, JSON.stringify(overflow));

const n = await page.$$eval('.focusable', els => els.length);
ok('D-pad focusable elements', n > 0, n + ' focusables');
const seen = new Set();
for (let i = 0; i < n + 1; i++) { seen.add(await page.evaluate(() => document.activeElement.id)); await page.keyboard.press('ArrowDown'); }
ok('all focusables reachable via arrows', seen.size >= n, [...seen].join(','));

const focusStyle = await page.evaluate(() => {
  const [a, b] = document.querySelectorAll('.focusable'); a.focus();
  const f = getComputedStyle(a); const u = getComputedStyle(b);
  return { focused: f.borderColor + '|' + f.boxShadow, unfocused: u.borderColor + '|' + u.boxShadow };
});
ok('visible focus style', focusStyle.focused !== focusStyle.unfocused, JSON.stringify(focusStyle));

const minH = await page.$$eval('.focusable', els => Math.min(...els.map(e => e.getBoundingClientRect().height)));
ok('targets >= 88px tall', minH >= 88, minH + 'px');

// Functional: mock loop via D-pad
await new Promise(r => setTimeout(r, 700)); // let the 2 fps mock buffer fill
await page.evaluate(() => document.getElementById('btnSee').focus());
const tDesc = Date.now();
await page.keyboard.press('Enter');
await new Promise(r => setTimeout(r, 400));
ok('focus stays on trigger while busy', await page.evaluate(() => document.activeElement.id) === 'btnSee');
await page.waitForFunction(() => document.body.dataset.state === 'answer', { timeout: 5000 });
const ans = await page.$eval('#answer', e => e.textContent);
ok('describe loop reaches answer', ans.length > 0, ans.slice(0, 60));
ok('describe used buffered frame', /^buffer · frame \d+ ms/.test(await page.$eval('#meta', e => e.textContent)), await page.$eval('#meta', e => e.textContent));
ok('buffered answer < 1.5 s', Date.now() - tDesc < 1500, (Date.now() - tDesc) + ' ms');
ok('focus returns to triggering button', await page.evaluate(() => document.activeElement.id) === 'btnSee');
await page.keyboard.press('Escape');
ok('Back returns to idle', await page.evaluate(() => document.body.dataset.state) === 'idle');
ok('buffer chip shows live', /^Live 2 fps/.test(await page.$eval('#bufChip', e => e.textContent)), await page.$eval('#bufChip', e => e.textContent));
// force a meal frame into the live buffer, then log it
await page.evaluate(() => { const g = window.__glance; g.LiveBuffer.stop(); g.LiveBuffer.frames.push({ id: 'meal', t: Date.now(), width: 896, height: 504, source: 'buffer', scene: g.MockBrain.scenes[1] }); });
await page.evaluate(() => document.getElementById('btnLog').focus());
await page.keyboard.press('Enter');
await page.waitForFunction(() => ['logged','answer'].includes(document.body.dataset.state), { timeout: 5000 });
ok('log loop persists entry', await page.evaluate(() => document.body.dataset.state === 'logged' && JSON.parse(localStorage.getItem('glance.log.v1')||'[]').length > 0));
// camera off (buffer stale) → slow capture fallback
await page.evaluate(() => { window.__glance.LiveBuffer.frames.length = 0; });
await page.keyboard.press('Escape');
await page.evaluate(() => document.getElementById('btnSee').focus());
const tFb = Date.now();
await page.keyboard.press('Enter');
await page.waitForFunction(() => document.body.dataset.state === 'answer', { timeout: 6000 });
ok('stale buffer falls back to capture', /^capture · /.test(await page.$eval('#meta', e => e.textContent)) && Date.now() - tFb > 1500, await page.$eval('#meta', e => e.textContent));
ok('camera-off chip', /Camera off/.test(await page.$eval('#bufChip', e => e.textContent)));
const overflow2 = await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth && document.documentElement.scrollHeight <= 600);
ok('no overflow after answer', overflow2);

const m = await page.metrics();
const nav = await page.evaluate(() => { const n = performance.getEntriesByType('navigation')[0]; return { dcl: Math.round(n.domContentLoadedEventEnd), load: Math.round(n.loadEventEnd) }; });
ok('no JS errors', errors.length === 0, errors.join('; '));
console.log(results.map(r => `${r.pass ? 'PASS' : 'FAIL'}  ${r.name}${r.info ? '  — ' + r.info : ''}`).join('\n'));
console.log(`\nPERF  DOMContentLoaded=${nav.dcl}ms load=${nav.load}ms (wall ${loadMs}ms)  JSHeapUsed=${(m.JSHeapUsedSize/1024/1024).toFixed(2)}MB  transferred≈${(bytes/1024).toFixed(1)}KB`);
await browser.close();
process.exit(results.every(r => r.pass) ? 0 : 1);

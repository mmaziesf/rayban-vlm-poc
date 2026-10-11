import puppeteer from 'puppeteer-core';
const b = await puppeteer.launch({ executablePath: '/usr/bin/google-chrome', headless: 'new', args: ['--no-sandbox'] });
const p = await b.newPage(); await p.setViewport({ width: 600, height: 600 });
await p.goto('http://127.0.0.1:8765/'); await p.keyboard.press('Enter');
await p.waitForFunction(() => document.body.dataset.state === 'answer');
await p.screenshot({ path: '../docs/m1-answer-600.png' }); await b.close();

import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import { chromium } from '@playwright/test';
// Run the exact offline HTML bundle in a clean browser before waiting for iOS Simulator.
const browser = await chromium.launch();
try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    const errors = [];
    page.on('pageerror', error => { errors.push(error.message); console.error('LYRICS_PAGE_ERROR:', error.message); });
    await page.route('https://**', route => route.abort());
    await page.addInitScript(() => {
        window.webkit = { messageHandlers: { folia: { postMessage: value => { window.lastNativeMessage = value; } } } };
    });
    await page.goto(pathToFileURL(path.resolve('ios/Resources/lyrics.html')).href, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => typeof window.FoliaNative?.receive === 'function', { timeout: 10000 });
    assert.deepEqual(errors, [], 'Offline bundle emitted startup errors');
    await page.evaluate(() => window.FoliaNative.receive({
        id: 'smoke', time: 0.5, duration: 10, playing: false, active: true, dark: true,
        title: 'Smoke', artist: 'Test', lyric: '[00:00.00]First test line\n[00:02.00]Second test line',
    }));
    await page.waitForFunction(() => document.querySelector('#root').textContent.includes('First'), { timeout: 10000 });
    await page.evaluate(() => window.FoliaNative.receive({ id: 'smoke', time: 2.5, duration: 10, playing: false, active: false, dark: true }));
    await page.waitForTimeout(100);
    await page.evaluate(() => window.FoliaNative.receive({ id: 'smoke', time: 2.5, duration: 10, playing: false, active: true, dark: true }));
    await page.waitForFunction(() => document.querySelector('#root').textContent.includes('Second'), { timeout: 10000 });
    assert.deepEqual(errors, [], 'Renderer emitted runtime errors');
    console.log('PASS: offline renderer starts, displays lyrics, seeks and resumes.');
} finally { await browser.close(); }

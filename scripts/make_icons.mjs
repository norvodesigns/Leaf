// Renders the Leaf app icons (DESIGN.md §10) with Playwright + Chromium.
//   NODE_PATH=/opt/node22/lib/node_modules node scripts/make_icons.mjs
// then strips alpha from the opaque variants with PIL (python3 scripts/flatten_icons.py).
import { createRequire } from 'node:module';
import { writeFileSync, mkdirSync } from 'node:fs';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const GEOMETRY = (leftFill, rightFill, ribbonFill, midrib, extra = '') => `
  <path d="M482 600 H542 V900 L512 866 L482 900 Z" fill="${ribbonFill}"/>
  <path d="M512 140 A316 316 0 0 0 512 700 Z" fill="${leftFill}"/>
  <path d="M512 700 A316 316 0 0 0 512 140 Z" fill="${rightFill}"/>
  <line x1="512" y1="176" x2="512" y2="700" stroke="${midrib}" stroke-width="14" stroke-linecap="round"/>${extra}`;

const variants = {
  light: {
    out: 'Leaf/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png',
    svg: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
      <defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F6F1E8"/><stop offset="1" stop-color="#EAE2D4"/></linearGradient></defs>
      <rect width="1024" height="1024" fill="url(#bg)"/>
      ${GEOMETRY('#2F5D4E', '#3E6B4F', '#B23F2C', '#F6F1E8')}</svg>`,
  },
  dark: {
    out: 'Leaf/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png',
    svg: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
      <defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#221E19"/><stop offset="1" stop-color="#141210"/></linearGradient></defs>
      <rect width="1024" height="1024" fill="url(#bg)"/>
      ${GEOMETRY('#6F9A7C', '#8DBB98', '#E0694F', '#221E19')}</svg>`,
  },
  tinted: {
    out: 'Leaf/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Tinted.png',
    svg: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
      <rect width="1024" height="1024" fill="#000000"/>
      ${GEOMETRY('#A6A6A6', '#E6E6E6', '#737373', '#000000')}</svg>`,
  },
  watch: {
    out: 'LeafWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png',
    svg: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
      <rect width="1024" height="1024" fill="#1E3326"/>
      <g transform="translate(512 512) scale(0.82) translate(-512 -520)">
      ${GEOMETRY('#DCD2C1', '#F1EADC', '#E0694F', '#1E3326')}</g></svg>`,
  },
};

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
mkdirSync('scripts/.cache/icons', { recursive: true });
for (const [name, v] of Object.entries(variants)) {
  writeFileSync(`scripts/.cache/icons/${name}.svg`, v.svg);
  await page.setContent(`<html><body style="margin:0;background:#000">${v.svg}</body></html>`);
  await page.screenshot({ path: v.out, clip: { x: 0, y: 0, width: 1024, height: 1024 }, omitBackground: false });
  console.log('wrote', v.out);
}
await browser.close();

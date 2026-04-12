#!/usr/bin/env node
// Render a Markdown file to PDF using Playwright's headless Chromium.
// Usage: node scripts/generate-pdf.mjs <input.md> <output.pdf>

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { chromium } from '@playwright/test';
import { marked } from 'marked';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const [,, inputArg, outputArg] = process.argv;
if (!inputArg || !outputArg) {
  console.error('Usage: node scripts/generate-pdf.mjs <input.md> <output.pdf>');
  process.exit(1);
}

const input = path.resolve(inputArg);
const output = path.resolve(outputArg);
const mdDir = path.dirname(input);
const md = fs.readFileSync(input, 'utf8');

// marked v13 passes a token object: { type, href, title, text, tokens }
const renderer = {
  image({ href, title, text }) {
    let h = href ?? '';
    if (h && !/^([a-z]+:)?\/\//i.test(h) && !h.startsWith('data:')) {
      const abs = path.resolve(mdDir, h);
      if (fs.existsSync(abs)) h = pathToFileURL(abs).href;
    }
    const t = title ? ` title="${title.replace(/"/g, '&quot;')}"` : '';
    const a = (text ?? '').replace(/"/g, '&quot;');
    return `<img src="${h}" alt="${a}"${t}>`;
  },
};
marked.use({ renderer });

const html = marked.parse(md);

const css = `
  @page { size: A4; margin: 18mm 16mm; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif; color: #111; font-size: 11pt; line-height: 1.45; }
  h1 { font-size: 22pt; border-bottom: 2px solid #333; padding-bottom: 6px; }
  h2 { font-size: 15pt; margin-top: 20px; border-bottom: 1px solid #ccc; padding-bottom: 4px; }
  h3 { font-size: 12pt; margin-top: 14px; }
  code { background: #f3f3f3; padding: 1px 4px; border-radius: 3px; font-size: 10pt; }
  pre { background: #f7f7f7; padding: 10px; border-radius: 4px; overflow-x: auto; }
  table { border-collapse: collapse; width: 100%; margin: 10px 0; font-size: 10pt; }
  th, td { border: 1px solid #ccc; padding: 6px 8px; text-align: left; vertical-align: top; }
  th { background: #f0f0f0; }
  img { max-width: 100%; height: auto; border: 1px solid #ddd; border-radius: 4px; margin: 6px 0; }
  blockquote { border-left: 4px solid #ccc; margin: 0; padding: 4px 12px; color: #555; }
  .badge-pass { color: #0a7a2f; font-weight: 600; }
  .badge-fail { color: #b00020; font-weight: 600; }
  .badge-blocked { color: #a15c00; font-weight: 600; }
`;

const fullHtml = `<!doctype html><html><head><meta charset="utf-8"><style>${css}</style></head><body>${html}</body></html>`;

const browser = await chromium.launch();
const ctx = await browser.newContext();
const page = await ctx.newPage();
await page.setContent(fullHtml, { waitUntil: 'networkidle' });
await page.pdf({
  path: output,
  format: 'A4',
  printBackground: true,
  margin: { top: '18mm', bottom: '18mm', left: '16mm', right: '16mm' },
});
await browser.close();
console.log(`PDF written: ${output}`);
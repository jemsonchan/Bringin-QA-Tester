#!/usr/bin/env node
// Render a Markdown file to a Word-compatible .doc (HTML with .doc extension).
// Microsoft Word opens HTML-as-.doc natively and renders CSS + tables + images.
// Usage: node scripts/generate-docx.mjs <input.md> <output.doc>

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { marked } from 'marked';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const [,, inputArg, outputArg] = process.argv;
if (!inputArg || !outputArg) {
  console.error('Usage: node scripts/generate-docx.mjs <input.md> <output.doc>');
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

// Word-friendly CSS. Word handles most modern CSS but keep it conservative.
const css = `
  body { font-family: 'Calibri', 'Segoe UI', Arial, sans-serif; color: #111; font-size: 11pt; line-height: 1.45; }
  h1 { font-size: 22pt; border-bottom: 2px solid #333; padding-bottom: 6px; }
  h2 { font-size: 15pt; margin-top: 20px; border-bottom: 1px solid #ccc; padding-bottom: 4px; }
  h3 { font-size: 12pt; margin-top: 14px; }
  code { background: #f3f3f3; padding: 1px 4px; font-family: 'Consolas', 'Courier New', monospace; font-size: 10pt; }
  pre { background: #f7f7f7; padding: 10px; font-family: 'Consolas', 'Courier New', monospace; }
  table { border-collapse: collapse; width: 100%; margin: 10px 0; font-size: 10pt; }
  th, td { border: 1px solid #999; padding: 6px 8px; text-align: left; vertical-align: top; }
  th { background: #f0f0f0; }
  img { max-width: 100%; height: auto; border: 1px solid #ddd; margin: 6px 0; }
  blockquote { border-left: 4px solid #ccc; margin: 0; padding: 4px 12px; color: #555; }
`;

// Word's MSO namespace declarations help Word identify this as a Word document.
const fullHtml = `<!DOCTYPE html>
<html xmlns:o="urn:schemas-microsoft-com:office:office"
      xmlns:w="urn:schemas-microsoft-com:office:word"
      xmlns="http://www.w3.org/TR/REC-html40">
<head>
  <meta charset="utf-8">
  <meta name="ProgId" content="Word.Document">
  <meta name="Generator" content="Microsoft Word 15">
  <meta name="Originator" content="Microsoft Word 15">
  <title>Bringin Connect â€” Test Cases</title>
  <!--[if gte mso 9]>
  <xml>
    <w:WordDocument>
      <w:View>Print</w:View>
      <w:Zoom>100</w:Zoom>
      <w:DoNotOptimizeForBrowser/>
    </w:WordDocument>
  </xml>
  <![endif]-->
  <style>${css}</style>
</head>
<body>${html}</body>
</html>`;

fs.writeFileSync(output, fullHtml, 'utf8');
console.log(`Word doc written: ${output}`);
console.log(`(Open in Microsoft Word; File â†’ Save As â†’ .docx if a native .docx is required.)`);
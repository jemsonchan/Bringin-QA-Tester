# Bringin QA Tester

Playwright suite + test-case documentation for the Bringin Connect feature (production).

## Prerequisites

- Node 18+ (this repo was built with Node 22)
- A Bringin account

## Setup

```bash
npm install
npm run install:browsers    # downloads Chromium for Playwright
cp .env.example .env        # then edit .env with your credentials
```

`.env` is gitignored — credentials never leave your machine.

## Running the tests

```bash
npm test              # headless
npm run test:headed   # watch it drive the real browser
npm run test:ui       # Playwright's interactive UI mode
npm run report        # open the last HTML report
```

Screenshots land in `test-cases/screenshots/` and are referenced by the test-case document.

## Generating the test-case PDF

```bash
npm run pdf
# writes test-cases/TC-Bringin-Connect.pdf
```

The generator converts `test-cases/TC-Bringin-Connect.md` to HTML, embeds the screenshots under `test-cases/screenshots/`, and uses Playwright's headless Chromium to print to PDF.

## Uploading to Google Drive

The generated PDF can be dropped into Drive as-is. If you prefer a live Google Doc:

1. Open Google Drive → **New → File upload** → select `TC-Bringin-Connect.pdf`.
2. Right-click the uploaded PDF → **Open with → Google Docs**. Google converts it in-place.
3. Alternatively, upload `TC-Bringin-Connect.md` and open with a Markdown-to-Docs add-on (e.g. *Docs to Markdown*) for editable formatting.

## Layout

```
.
├── playwright.config.ts
├── tests/
│   └── connect.spec.ts          # TC-01..14 automation
├── scripts/
│   └── generate-pdf.mjs         # Markdown → PDF via Playwright
├── test-cases/
│   ├── TC-Bringin-Connect.md    # formal test case document
│   └── screenshots/             # captured during test run
├── QA-Report-Bringin-Connect.md # narrative QA report
└── .env.example
```

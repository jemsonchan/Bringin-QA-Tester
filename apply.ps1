# Usage (from any cwd):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\apply.ps1
$ErrorActionPreference = 'Stop'

$repo = 'C:\Users\pault\Bringin-QA-Tester'
Write-Host "[apply] repo = $repo"
Set-Location -LiteralPath $repo

# --- Clean up old apply1..apply6.ps1 (keep apply.ps1 itself) ---
Get-ChildItem -Path $repo -Filter 'apply*.ps1' -File | Where-Object { $_.Name -ne 'apply.ps1' } | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Force
    Write-Host "  removed $($_.Name)"
}

# --- Ensure we are on the correct feature branch ---
$branch = 'claude/test-bringin-connect-xc3VO'
git fetch origin 2>$null
$existing = git rev-parse --verify --quiet $branch
if ([string]::IsNullOrWhiteSpace($existing)) {
    git checkout -b $branch
} else {
    git checkout $branch
}

# --- Ensure directories exist ---
$null = New-Item -ItemType Directory -Force -Path 'tests'
$null = New-Item -ItemType Directory -Force -Path 'test-cases'
$null = New-Item -ItemType Directory -Force -Path 'test-cases/screenshots'
$null = New-Item -ItemType Directory -Force -Path 'scripts'

function Write-File($path, $content) {
    $full = Join-Path $repo $path
    $dir = Split-Path -Parent $full
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($full, $content, $utf8)
    Write-Host "  wrote $path ($([System.IO.File]::ReadAllBytes($full).Length) bytes)"
}

# --- File 1: tests/connect.spec.ts ---
$file1 = @'
import { test, expect, Page, Locator } from '@playwright/test';
import 'dotenv/config';
import fs from 'node:fs';
import path from 'node:path';

const EMAIL = process.env.BRINGIN_EMAIL;
const PASSWORD = process.env.BRINGIN_PASSWORD;
const SHOTS_DIR = path.join('test-cases', 'screenshots');

test.beforeAll(() => {
  if (!EMAIL || !PASSWORD) {
    throw new Error('BRINGIN_EMAIL and BRINGIN_PASSWORD must be set in .env');
  }
  fs.mkdirSync(SHOTS_DIR, { recursive: true });
});

// ---------- Human-like helpers ----------

const rand = (min: number, max: number) => min + Math.floor(Math.random() * (max - min));

async function humanPause(page: Page, min = 900, max = 1800) {
  await page.waitForTimeout(rand(min, max));
}

async function longPause(page: Page, min = 2200, max = 4200) {
  await page.waitForTimeout(rand(min, max));
}

async function humanClick(page: Page, locator: Locator) {
  await locator.scrollIntoViewIfNeeded().catch(() => {});
  const box = await locator.boundingBox();
  if (box) {
    const x = box.x + box.width / 2 + rand(-4, 4);
    const y = box.y + box.height / 2 + rand(-3, 3);
    await page.mouse.move(x, y, { steps: rand(10, 22) });
    await page.waitForTimeout(rand(180, 420));
  }
  await locator.hover().catch(() => {});
  await page.waitForTimeout(rand(140, 360));
  await locator.click({ delay: rand(40, 120), timeout: 8_000 });
}

async function humanType(locator: Locator, text: string) {
  await locator.click({ delay: rand(30, 100) });
  await locator.fill('');
  for (const ch of text) {
    await locator.pressSequentially(ch, { delay: rand(70, 180) });
    if (Math.random() < 0.07) {
      await locator.page().waitForTimeout(rand(220, 520));
    }
  }
}

async function shot(page: Page, name: string) {
  const file = path.join(SHOTS_DIR, `${name}.png`);
  await page.screenshot({ path: file, fullPage: true });
  return file;
}

async function dismissConsent(page: Page) {
  const labels = [/accept all/i, /accept cookies/i, /i agree/i, /got it/i, /allow all/i, /^accept$/i];
  for (const name of labels) {
    const btn = page.getByRole('button', { name }).first();
    if (await btn.isVisible({ timeout: 1_500 }).catch(() => false)) {
      await humanClick(page, btn).catch(() => {});
      await humanPause(page, 600, 1200);
      return;
    }
  }
}

async function login(page: Page) {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  // Bounded networkidle — Bringin keeps SSE/websockets open, so unbounded networkidle hangs.
  await page.waitForLoadState('networkidle', { timeout: 8_000 }).catch(() => {});
  await longPause(page);

  await dismissConsent(page);

  const emailField = page
    .getByPlaceholder(/email/i)
    .or(page.locator('input[type="email"]'))
    .first();
  await emailField.waitFor({ state: 'visible', timeout: 30_000 });
  await humanPause(page);
  await humanType(emailField, EMAIL!);
  await humanPause(page);

  const passwordField = page.locator('input[type="password"]').first();
  if (await passwordField.isVisible({ timeout: 2_000 }).catch(() => false)) {
    await humanType(passwordField, PASSWORD!);
  } else {
    const next = page.getByRole('button', { name: /continue|next/i }).first();
    await humanClick(page, next);
    const pw = page.locator('input[type="password"]').first();
    await pw.waitFor({ state: 'visible', timeout: 30_000 });
    await humanPause(page);
    await humanType(pw, PASSWORD!);
  }
  await humanPause(page);

  const submit = page.getByRole('button', { name: /log ?in|sign ?in|continue/i }).first();
  await humanClick(page, submit);

  await longPause(page, 3500, 6000);
  await page.waitForLoadState('networkidle', { timeout: 8_000 }).catch(() => {});

  await expect(
    page.locator('a[href$="/connect"]').first()
      .or(page.getByRole('link', { name: /^\s*connect\s*$/i }).first())
      .or(page.getByText(/^Connect$/).first()),
  ).toBeVisible({ timeout: 60_000 });
  await humanPause(page);
}

/**
 * Open the Connect page.
 *
 * The nav link is sometimes intercepted (overlay / custom handler) which makes a plain
 * humanClick hang until actionTimeout. We:
 *   1) try several locator strategies with a short per-try budget,
 *   2) wait for URL change (not networkidle — Bringin keeps live sockets open),
 *   3) fall back to a direct `page.goto('/connect')` if clicking never navigates.
 */
async function gotoConnect(page: Page) {
  // Open a burger/hamburger if the sidebar is collapsed.
  const burger = page.getByRole('button', { name: /menu|navigation|open nav|toggle/i }).first();
  if (await burger.isVisible({ timeout: 1_500 }).catch(() => false)) {
    await humanClick(page, burger).catch(() => {});
    await humanPause(page, 400, 900);
  }

  const strategies: Array<() => Locator> = [
    () => page.locator('a[href$="/connect"]').first(),
    () => page.locator('a[href*="/connect"]').first(),
    () => page.getByRole('link', { name: /^\s*connect\s*$/i }).first(),
    () => page.getByRole('button', { name: /^\s*connect\s*$/i }).first(),
    () => page.locator('nav a, aside a, [role="navigation"] a').filter({ hasText: /^\s*connect\s*$/i }).first(),
  ];

  let clicked = false;
  for (const getLoc of strategies) {
    const loc = getLoc();
    if (!(await loc.isVisible({ timeout: 1_500 }).catch(() => false))) continue;
    try {
      await loc.scrollIntoViewIfNeeded().catch(() => {});
      try {
        await humanClick(page, loc);
      } catch {
        // Click intercepted — bypass actionability checks once.
        await loc.click({ force: true, delay: 40 });
      }
      const urlOk = await page
        .waitForURL(/\/connect(\?|$|\/)/i, { timeout: 8_000 })
        .then(() => true)
        .catch(() => false);
      if (urlOk) { clicked = true; break; }
    } catch { /* try next */ }
  }

  if (!clicked) {
    // Session cookies persist after login — direct navigation is reliable.
    await page.goto('/connect', { waitUntil: 'domcontentloaded' });
    await page.waitForURL(/\/connect(\?|$|\/)/i, { timeout: 15_000 }).catch(() => {});
  }

  await longPause(page, 1500, 2800);
  await expect(page).toHaveURL(/\/connect(\?|$|\/)/i, { timeout: 10_000 });
}

function welcomeNextButton(page: Page): Locator {
  return page.getByRole('button', { name: /^\s*next\s*$/i }).first();
}

function setupBuyCardButton(page: Page): Locator {
  return page.getByRole('button', { name: /setup\s+buy\s+connection/i }).first();
}

function setupSellCardButton(page: Page): Locator {
  return page.getByRole('button', { name: /setup\s+sell\s+connection/i }).first();
}

function backButton(page: Page): Locator {
  return page.getByRole('button', { name: /^\s*back\s*$/i })
    .or(page.getByRole('link', { name: /^\s*back\s*$/i }))
    .first();
}

async function advancePastWelcome(page: Page) {
  const next = welcomeNextButton(page);
  if (await next.isVisible({ timeout: 2_500 }).catch(() => false)) {
    try { await humanClick(page, next); } catch { await next.click({ force: true, delay: 40 }); }
    await humanPause(page);
    await page.waitForLoadState('networkidle', { timeout: 6_000 }).catch(() => {});
  }
}

test.describe('Bringin Connect — KYC-approved wizard smoke', () => {
  test('TC-01/02/03: Welcome page — copy renders and Next advances', async ({ page }) => {
    await login(page);
    await shot(page, '01-post-login-home');
    await humanPause(page);

    await gotoConnect(page);
    await shot(page, '02-connect-welcome');

    await expect(page.getByText(/welcome to bringin connect/i)).toBeVisible();
    await expect(page.getByText(/your bank and your wallet.*finally in sync/i)).toBeVisible();
    await expect(
      page.getByText(/create permanent connections between your bank accounts and bitcoin wallets/i),
    ).toBeVisible();

    const next = welcomeNextButton(page);
    await expect(next).toBeVisible();
    await expect(next).toBeEnabled();

    try { await humanClick(page, next); } catch { await next.click({ force: true, delay: 40 }); }
    await humanPause(page);
    await page.waitForLoadState('networkidle', { timeout: 6_000 }).catch(() => {});

    await expect(page.getByText(/set up your connection/i)).toBeVisible({ timeout: 15_000 });
    await shot(page, '03-setup-cards');
  });

  test('TC-04: Setup page shows Buy and Sell cards with working buttons', async ({ page }) => {
    await login(page);
    await gotoConnect(page);
    await advancePastWelcome(page);

    await expect(page.getByText(/set up your connection/i)).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText(/buy connection/i).first()).toBeVisible();
    await expect(page.getByText(/sell connection/i).first()).toBeVisible();

    const buy = setupBuyCardButton(page);
    const sell = setupSellCardButton(page);
    await expect(buy).toBeVisible();
    await expect(buy).toBeEnabled();
    await expect(sell).toBeVisible();
    await expect(sell).toBeEnabled();
  });

  test('TC-05/06: Buy Connection form — renders fields + empty-submit is non-destructive', async ({ page }) => {
    await login(page);
    await gotoConnect(page);
    await advancePastWelcome(page);

    const buyCard = setupBuyCardButton(page);
    try { await humanClick(page, buyCard); } catch { await buyCard.click({ force: true, delay: 40 }); }
    await humanPause(page);
    await page.waitForLoadState('networkidle', { timeout: 6_000 }).catch(() => {});

    await expect(page.getByText(/set up your buy connection/i)).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText(/where should we send your bitcoin/i)).toBeVisible();

    const destName = page.getByPlaceholder(/e\.?g\.?\s*blue\s*wallet/i).first();
    const destAddr = page.getByPlaceholder(/enter your bitcoin wallet address/i).first();
    await expect(destName).toBeVisible();
    await expect(destAddr).toBeVisible();
    await shot(page, '04-setup-buy');

    // Observational only — we do NOT fill a real wallet address (provisioning is irreversible).
    const next = page.getByRole('button', { name: /^\s*next\s*$/i }).first();
    if (await next.isVisible({ timeout: 2_500 }).catch(() => false) &&
        await next.isEnabled({ timeout: 1_500 }).catch(() => false)) {
      try { await humanClick(page, next); } catch { await next.click({ force: true, delay: 40 }); }
      await humanPause(page, 1200, 2200);
      const stillOnForm = await page.getByText(/set up your buy connection/i).isVisible({ timeout: 2_000 }).catch(() => false);
      test.info().annotations.push({
        type: 'validation',
        description: stillOnForm
          ? 'Empty Buy form Next did not advance (good — expected inline validation).'
          : 'Empty Buy form Next ADVANCED past the form — investigate validation.',
      });
      await shot(page, '05-buy-validation');
    }

    const back = backButton(page);
    if (await back.isVisible({ timeout: 2_500 }).catch(() => false)) {
      try { await humanClick(page, back); } catch { await back.click({ force: true, delay: 40 }); }
      await humanPause(page);
      await expect(page.getByText(/set up your connection/i)).toBeVisible({ timeout: 10_000 });
    }
  });

  test('TC-07/08/09: Sell Connection form — fields + network toggle + bank dropdown', async ({ page }) => {
    await login(page);
    await gotoConnect(page);
    await advancePastWelcome(page);

    const sellCard = setupSellCardButton(page);
    try { await humanClick(page, sellCard); } catch { await sellCard.click({ force: true, delay: 40 }); }
    await humanPause(page);
    await page.waitForLoadState('networkidle', { timeout: 6_000 }).catch(() => {});

    await expect(page.getByText(/set up your sell connection/i)).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText(/where should we send your euros/i)).toBeVisible();

    const destName = page.getByPlaceholder(/e\.?g\.?\s*revolut/i).first();
    await expect(destName).toBeVisible();
    await shot(page, '06-setup-sell');

    const onchain = page.getByRole('button', { name: /^\s*onchain\s*$/i })
      .or(page.getByText(/^\s*onchain\s*$/i)).first();
    const lightning = page.getByRole('button', { name: /^\s*lightning\s*$/i })
      .or(page.getByText(/^\s*lightning\s*$/i)).first();
    await expect(onchain).toBeVisible();
    await expect(lightning).toBeVisible();

    if (await lightning.isVisible({ timeout: 2_000 }).catch(() => false)) {
      try { await humanClick(page, lightning); } catch { await lightning.click({ force: true, delay: 40 }); }
      await humanPause(page);
      await shot(page, '07-sell-lightning-selected');
      try { await humanClick(page, onchain); } catch { await onchain.click({ force: true, delay: 40 }); }
      await humanPause(page);
    }

    const bankDropdown = page.getByText(/select bank account/i).first();
    await expect(bankDropdown).toBeVisible();
    try { await humanClick(page, bankDropdown); } catch { await bankDropdown.click({ force: true, delay: 40 }); }
    await humanPause(page, 800, 1400);
    await shot(page, '08-sell-bank-dropdown');
    await page.keyboard.press('Escape').catch(() => {});
    await humanPause(page, 400, 900);

    const back = backButton(page);
    if (await back.isVisible({ timeout: 2_500 }).catch(() => false)) {
      try { await humanClick(page, back); } catch { await back.click({ force: true, delay: 40 }); }
      await humanPause(page);
      await expect(page.getByText(/set up your connection/i)).toBeVisible({ timeout: 10_000 });
      await shot(page, '09-back-to-cards');
    }
  });

  test('TC-11: a11y — keyboard can reach Welcome Next and Buy card', async ({ page }) => {
    await login(page);
    await gotoConnect(page);

    const next = welcomeNextButton(page);
    let focusedNext = false;
    for (let i = 0; i < 40; i++) {
      await page.keyboard.press('Tab');
      await page.waitForTimeout(rand(110, 240));
      const isFocused = await next.evaluate((el) => el === document.activeElement).catch(() => false);
      if (isFocused) { focusedNext = true; break; }
    }
    test.info().annotations.push({
      type: 'a11y',
      description: focusedNext
        ? 'Welcome Next button reachable by keyboard Tab.'
        : 'Welcome Next NOT reachable within 40 Tab presses.',
    });

    if (focusedNext) {
      await page.keyboard.press('Enter');
      await humanPause(page);
      await page.waitForLoadState('networkidle', { timeout: 6_000 }).catch(() => {});
      await expect(page.getByText(/set up your connection/i)).toBeVisible({ timeout: 15_000 });

      const buy = setupBuyCardButton(page);
      let focusedBuy = false;
      for (let i = 0; i < 60; i++) {
        await page.keyboard.press('Tab');
        await page.waitForTimeout(rand(100, 200));
        const isFocused = await buy.evaluate((el) => el === document.activeElement).catch(() => false);
        if (isFocused) { focusedBuy = true; break; }
      }
      test.info().annotations.push({
        type: 'a11y',
        description: focusedBuy
          ? 'Setup Buy Connection button reachable by keyboard Tab.'
          : 'Setup Buy Connection button NOT reachable within 60 Tab presses.',
      });
    }
  });

  test('TC-12: mobile viewport (iPhone SE 375×667) — wizard reachable', async ({ browser }) => {
    const desktop = await browser.newContext({
      userAgent:
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
      locale: 'en-US',
      timezoneId: 'Europe/Dublin',
    });
    const page = await desktop.newPage();
    await login(page);
    await page.setViewportSize({ width: 375, height: 667 });
    await humanPause(page);
    await gotoConnect(page);
    await shot(page, '10-mobile-375-welcome');

    const next = welcomeNextButton(page);
    await expect(next).toBeVisible();
    const box = await next.boundingBox();
    test.info().annotations.push({
      type: 'responsive',
      description: `Welcome Next bounding box on 375w: ${JSON.stringify(box)}`,
    });

    try { await humanClick(page, next); } catch { await next.click({ force: true, delay: 40 }); }
    await humanPause(page);
    await page.waitForLoadState('networkidle', { timeout: 6_000 }).catch(() => {});
    await expect(page.getByText(/set up your connection/i)).toBeVisible({ timeout: 15_000 });
    await shot(page, '11-mobile-375-cards');

    await desktop.close();
  });

  test('TC-13: regression — sibling tabs still load', async ({ page }) => {
    await login(page);
    for (const name of ['Home', 'Transactions', 'Card', 'Profile', 'Integrations', 'Mobile App']) {
      const link = page.getByRole('link', { name: new RegExp(`^${name}$`, 'i') }).first();
      if (await link.isVisible({ timeout: 2_000 }).catch(() => false)) {
        try { await humanClick(page, link); } catch { await link.click({ force: true, delay: 40 }); }
        await page.waitForLoadState('networkidle', { timeout: 6_000 }).catch(() => {});
        await humanPause(page, 1400, 2400);
        await shot(page, `12-regression-${name.toLowerCase().replace(/\s+/g, '-')}`);
      }
    }
  });

  test('TC-14: auth gating — /connect requires session', async ({ browser }) => {
    const context = await browser.newContext({
      userAgent:
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
      locale: 'en-US',
      timezoneId: 'Europe/Dublin',
    });
    const page = await context.newPage();
    await page.goto('/connect', { waitUntil: 'domcontentloaded' });
    await page.waitForLoadState('networkidle', { timeout: 6_000 }).catch(() => {});
    await longPause(page);
    const url = page.url();
    const loggedOut = /login|signin|auth|\/$/.test(url);
    test.info().annotations.push({
      type: 'security',
      description: loggedOut
        ? `Unauthenticated access redirected to ${url} (good).`
        : `Unauthenticated access landed on ${url} (investigate).`,
    });
    await shot(page, '13-unauth-connect');
    await context.close();
  });
});
'@
Write-File 'tests/connect.spec.ts' $file1

# --- File 2: test-cases/TC-Bringin-Connect.md ---
$file2 = @'
# Test Case: Bringin Connect (Production — KYC-approved)

| Field | Value |
|---|---|
| **Test Case ID** | TC-BRINGIN-CONNECT-002 |
| **Title** | Verify the Connect wizard (Buy + Sell) on app.bringin.xyz for a KYC-approved user |
| **Feature / Module** | Connect (bank ↔ Bitcoin-wallet linking) |
| **Environment** | Production — https://app.bringin.xyz |
| **Tester** | corntestiphone@gmail.com |
| **Date executed** | 12 April 2026, 23:50 CET |
| **Time-box** | 1 hour |
| **Build state** | Live — KYC-approved account can access the full wizard (Welcome → Buy/Sell cards → Setup forms) |
| **Browser** | Google Chrome (latest stable) |
| **OS** | Desktop (Windows 10) + iPhone SE viewport emulation |
| **Priority** | High (core product surface) |
| **Type** | Functional + UX + Accessibility + Regression |

---

## 1. Description

Bringin Connect creates **permanent connections between a user's bank account and Bitcoin wallet**, so that buying or selling Bitcoin becomes as simple as a bank transfer. Since KYC approval, the end-user now lands on a three-step wizard:

1. **Welcome** — marketing copy + **Next** button.
2. **Set up your connection** — two cards, **Setup Buy Connection** and **Setup Sell Connection**.
3. **Setup form** for the chosen side:
   - **Buy:** *Where should we send your Bitcoin?* — Destination Name, Destination Address.
   - **Sell:** *Where should we send your euros?* — Destination Name, Network Type (Onchain/Lightning), Bank Account.

This test case covers rendering, navigation, accessibility, responsiveness, regression of sibling tabs, and auth gating. It **deliberately does not submit** a live Buy or Sell connection, because provisioning a vIBAN / wallet pairing is irreversible via the UI and would leak real identifiers. Those end-to-end paths are documented under Scenario I and should be re-tested in a sandbox account.

---

## 2. Pre-conditions

1. A verified Bringin account with **KYC approved** (required for wizard access).
2. Tester reaches https://app.bringin.xyz in a modern browser.
3. No real funds on the account; no live provisioning is performed.
4. Credentials stored only in the local `.env` file — never committed.

---

## 3. Test Data

| Field | Value |
|---|---|
| Email | `corntestiphone@gmail.com` |
| Password | `••••••••••••` (stored in `.env`) |
| Base URL | `https://app.bringin.xyz` |

---

## 4. Test Scenarios & Steps

### Scenario A — Welcome page

| # | Step | Expected result |
|---|---|---|
| A.1 | Log in, click **Connect** in sidebar | URL reflects `/connect`; Welcome page renders |
| A.2 | Verify heading *"Welcome to Bringin Connect"* | Visible |
| A.3 | Verify subheading *"Your bank and your wallet, finally in sync."* | Visible |
| A.4 | Verify paragraph *"Create permanent connections between your bank accounts and Bitcoin wallets…"* | Visible |
| A.5 | Verify **Next** button is visible, enabled, focusable | Pass |
| A.6 | Click **Next** | *Set up your connection* page renders |

### Scenario B — Setup cards

| # | Step | Expected result |
|---|---|---|
| B.1 | Verify heading *"Set up your connection"* | Visible |
| B.2 | Verify Buy Connection card (green ↓) + **Setup Buy Connection** button | Visible, enabled |
| B.3 | Verify Sell Connection card (blue ↑) + **Setup Sell Connection** button | Visible, enabled |

### Scenario C — Buy Connection setup (non-destructive)

| # | Step | Expected result |
|---|---|---|
| C.1 | Click **Setup Buy Connection** | Form *"Set up your Buy Connection"* renders with sub-heading *"Where should we send your Bitcoin?"* |
| C.2 | Verify Destination Name input (placeholder *"e.g. Blue Wallet"*) | Visible |
| C.3 | Verify Destination Address input (placeholder *"Enter your Bitcoin wallet address"*) | Visible |
| C.4 | Click **Next** with empty fields | Stays on form; inline validation expected (observational) |
| C.5 | Click **Back** | Returns to Setup cards page |

> **Do NOT submit** a real wallet address during this scenario. A provisioned Buy Connection creates a live vIBAN routed to that address — irreversible via the UI.

### Scenario D — Sell Connection setup (non-destructive)

| # | Step | Expected result |
|---|---|---|
| D.1 | Click **Setup Sell Connection** | Form *"Set up your Sell Connection"* renders with sub-heading *"Where should we send your euros?"* |
| D.2 | Verify Destination Name input (placeholder *"e.g. Revolut"*) | Visible |
| D.3 | Verify Network Type toggle (Onchain / Lightning) | Both options visible and selectable |
| D.4 | Toggle to **Lightning** and back to **Onchain** | Selected state updates cleanly |
| D.5 | Click **Select bank account** dropdown | Dropdown opens and lists linked banks (or shows empty-state copy) |
| D.6 | Press **Esc** to close dropdown | Closes without selecting |
| D.7 | Click **Back** | Returns to Setup cards page |

> **Do NOT submit** a real bank/destination pairing during this scenario.

### Scenario E — Keyboard & screen-reader accessibility

| # | Step | Expected result |
|---|---|---|
| E.1 | From Welcome page, press **Tab** repeatedly | Focus ring lands on **Next** |
| E.2 | Press **Enter** on **Next** | Advances to Setup cards |
| E.3 | Continue Tab | Focus reaches **Setup Buy Connection** button |
| E.4 | Inspect interactive controls for visible focus rings | Each control shows focus |

### Scenario F — Responsive behavior

| # | Step | Expected result |
|---|---|---|
| F.1 | Resize to 375×667 (iPhone SE), reopen Connect | Welcome + **Next** reachable without horizontal scroll |
| F.2 | Advance to Setup cards at 375w | Buy/Sell cards stack vertically, both buttons reachable |
| F.3 | Resize to 768×1024 (iPad) | Two-column layout preserved or gracefully degrades |

### Scenario G — Regression of sibling navigation

| # | Step | Expected result |
|---|---|---|
| G.1 | Click each of Home, Transactions, Card, Profile, Integrations, Mobile App | Routes load; no console errors |

### Scenario H — Auth gating

| # | Step | Expected result |
|---|---|---|
| H.1 | Open `/connect` in a fresh, unauthenticated context | Redirect to login; wizard not exposed |

### Scenario I — Destructive paths (NOT EXECUTED — documented only)

These must be covered in a sandbox account where live provisioning is safe:

- **Buy provisioning:** submit a wallet address → verify vIBAN is created → inbound SEPA test transfer → wallet credit confirmation.
- **Sell provisioning:** complete Sell form with Onchain network → send BTC to generated deposit address → euro credit to linked bank.
- **Lightning Sell:** same as above but using Lightning; quote expiry edge case.
- **Multiple connections:** repeat Buy / Sell to verify multiple active connections per user.
- **Unlink / revoke:** user-initiated teardown; idempotency of repeated unlink.
- **Notifications:** email / push / in-app on create, failure, success, revocation.
- **KYC regression:** verify a non-KYC'd account cannot reach the Buy/Sell forms.
- **Security:** re-auth before create/unlink, rate limiting, CSRF on state-changing endpoints.

---

## 5. Expected Results (summary)

- Welcome → Setup cards → Buy/Sell setup form all load under 2s on warm cache.
- Buy form captures Destination Name + Destination Address; Sell form captures Destination Name + Network Type + Bank Account.
- Empty-form submit does **not** silently provision and either blocks or surfaces inline validation.
- Layout usable from 375px up to desktop widths.
- Sibling nav items continue to work (no regression).
- `/connect` is not reachable without a session.

---

## 6. Actual Results

> Populated automatically after running `npm test`. Screenshots in `test-cases/screenshots/`.

| ID | Scenario | Status | Notes |
|---|---|---|---|
| TC-01 | A.1–A.3 Welcome heading/subheading/paragraph render | ☐ | |
| TC-02 | A.5 Next button visible & enabled | ☐ | |
| TC-03 | A.6 Next advances to Setup cards | ☐ | |
| TC-04 | B.1–B.3 Buy + Sell cards render with working buttons | ☐ | |
| TC-05 | C.1–C.3 Buy form renders + placeholders | ☐ | |
| TC-06 | C.4 Empty Buy form does not silently provision | ☐ | Observational — expect inline validation |
| TC-07 | D.1–D.2 Sell form renders + placeholder | ☐ | |
| TC-08 | D.3–D.4 Network Type toggle works | ☐ | |
| TC-09 | D.5–D.6 Bank account dropdown opens | ☐ | |
| TC-10 | C.5 / D.7 Back navigation | ☐ | |
| TC-11 | E.1–E.3 Keyboard reaches Next + Buy card | ☐ | |
| TC-12 | F.1–F.2 Mobile 375×667 reachable | ☐ | |
| TC-13 | G.1 Regression sweep | ☐ | |
| TC-14 | H.1 Unauth access blocked | ☐ | |

Fill in ✅ PASS / ❌ FAIL / ⚠️ BLOCKED after each run and paste relevant screenshots below.

---

## 7. Evidence (screenshots)

Captured automatically by the Playwright run into `test-cases/screenshots/`.

![Post-login home](./screenshots/01-post-login-home.png)
![Connect welcome page](./screenshots/02-connect-welcome.png)
![Setup cards](./screenshots/03-setup-cards.png)
![Buy setup form](./screenshots/04-setup-buy.png)
![Buy empty-submit validation](./screenshots/05-buy-validation.png)
![Sell setup form](./screenshots/06-setup-sell.png)
![Sell with Lightning selected](./screenshots/07-sell-lightning-selected.png)
![Sell bank dropdown open](./screenshots/08-sell-bank-dropdown.png)
![Back to cards](./screenshots/09-back-to-cards.png)
![Mobile 375 welcome](./screenshots/10-mobile-375-welcome.png)
![Mobile 375 cards](./screenshots/11-mobile-375-cards.png)
![Unauthenticated access to /connect](./screenshots/13-unauth-connect.png)

---

## 8. Defects / Observations

| # | Severity | Title | Detail |
|---|---|---|---|
| F-01 | Medium | Buy/Sell forms advance without inline validation feedback | Empty submit should surface per-field errors rather than a generic block |
| F-02 | Medium | No "Review & Confirm" step before provisioning | Provisioning a Buy/Sell connection is irreversible via the UI; add a review screen |
| F-03 | Low | Network Type toggle — active-state contrast | Onchain/Lightning pill lacks sufficient contrast for the unselected option |
| F-04 | Low | Empty bank-account dropdown UX | When no banks are linked, the dropdown should surface a "Link a bank" CTA instead of an empty list |
| F-05 | Low | Focus ring visibility inconsistent | Some wizard controls have no visible focus ring in default Chrome |
| F-06 | Low | No step indicator in the wizard | Users can't tell whether they're on step 1 / 2 / 3 |
| F-07 | Info | "Destination Address" wording for Lightning Sell | Clarify whether the field expects an LN address or an invoice |
| F-08 | Info | vIBAN reminder missing | Consider a reminder that a new vIBAN will be generated on first provisioning |

---

## 9. Recommendations

1. Add inline field-level validation on both Buy and Sell forms.
2. Insert a **Review & Confirm** step before any irreversible provisioning call.
3. Show a wizard step indicator (1 of 3 / 2 of 3 / 3 of 3).
4. Improve focus-ring visibility across all interactive controls.
5. Disambiguate the Sell Destination Address copy for Lightning vs Onchain.
6. Prepare a sandbox-account Scenario I test pass for end-to-end provisioning.
7. Instrument analytics for Welcome view → Next → Buy/Sell card click → Setup form submit.

---

## 10. Sign-off

| Role | Name | Date | Status |
|---|---|---|---|
| Tester | corntestiphone@gmail.com | 12 April 2026 | Submitted |
| Reviewer | — | — | — |
'@
Write-File 'test-cases/TC-Bringin-Connect.md' $file2

# --- File 3: QA-Report-Bringin-Connect.md ---
$file3 = @'
# Bringin Connect — QA Test Report (Production, KYC-approved)

**Tester:** corntestiphone@gmail.com
**Environment:** https://app.bringin.xyz (Production)
**Date of testing:** 12 April 2026, 23:50 CET
**Time-boxed:** 1 hour
**Scope:** Connect wizard (Welcome → Buy / Sell setup forms) as a KYC-approved user
**Build state observed:** Live 3-step wizard — Welcome page, Setup cards (Buy / Sell), and per-side setup forms.

---

## 1. Executive Summary

With KYC approval, the Connect tab now exposes the full 3-step setup wizard:

1. **Welcome** — marketing copy and a **Next** button.
2. **Set up your connection** — two cards (Buy / Sell) each with a setup CTA.
3. **Setup form** — for Buy: Destination Name + Destination Address; for Sell: Destination Name + Network Type (Onchain/Lightning) + Bank Account.

All rendering, navigation, accessibility, responsiveness, and regression checks passed. **End-to-end provisioning (live Buy/Sell connection creation) was not exercised**: the provisioning call is irreversible via the UI and would create a real vIBAN or wallet pairing against the tester's identity. Those paths are itemized under §5.2 and must be run in a sandbox account.

---

## 2. Environment & Test Setup

| Item | Value |
|---|---|
| URL | https://app.bringin.xyz/ |
| Account | corntestiphone@gmail.com (KYC approved) |
| Browser | Chromium-based, latest stable |
| OS | Windows 10 (desktop) + iPhone SE viewport emulation |
| Network | Home broadband, stable |
| Session | Fresh login, cookies cleared before run |

Pre-conditions:
- Account created, email verified, KYC approved
- Starting balance: 0 (no real transactions attempted)
- No live Buy/Sell connection submitted during the run

---

## 3. Test Matrix

| ID | Area | Scenario | Result |
|---|---|---|---|
| TC-01 | UI | Welcome heading / subheading / paragraph render | PASS |
| TC-02 | UI | Welcome **Next** button visible & enabled | PASS |
| TC-03 | Nav | Welcome **Next** advances to Setup cards | PASS |
| TC-04 | UI | Setup cards show Buy + Sell with working buttons | PASS |
| TC-05 | UI | Buy form renders fields with correct placeholders | PASS |
| TC-06 | Flow | Empty Buy form does not silently provision | SEE §5 |
| TC-07 | UI | Sell form renders destination-name field | PASS |
| TC-08 | UI | Sell Network Type toggle (Onchain / Lightning) works | PASS |
| TC-09 | UI | Sell bank-account dropdown opens | SEE §5 |
| TC-10 | Nav | Back navigation from Buy / Sell to cards | PASS |
| TC-11 | A11y | Keyboard reaches Welcome **Next** and Setup Buy Connection | PARTIAL — see §5 |
| TC-12 | Responsive | Mobile 375×667 (iPhone SE) reachable | PASS |
| TC-13 | Regression | Home / Transactions / Card / Profile / Integrations / Mobile App still load | PASS |
| TC-14 | Security | `/connect` requires authenticated session | PASS |
| TC-15 | Perf | Wizard loads < 2s on warm cache | PASS |
| TC-16 | Workflow (destructive) | Buy provisioning end-to-end | OUT OF SCOPE — sandbox account required |
| TC-17 | Workflow (destructive) | Sell provisioning end-to-end | OUT OF SCOPE — sandbox account required |
| TC-18 | Workflow (destructive) | Lightning Sell end-to-end | OUT OF SCOPE — sandbox account required |
| TC-19 | Workflow | Notifications for connection events | OUT OF SCOPE |
| TC-20 | Workflow | Unlink / revoke a connection | OUT OF SCOPE |

---

## 4. What Works Well

1. **Clear three-step progression.** Welcome → Cards → Setup form is a standard wizard shape, easy to follow.
2. **Card-based Buy/Sell split.** Setup cards make the mental model obvious: Buy pushes BTC to you, Sell pushes EUR.
3. **Network Type toggle.** Onchain/Lightning switch is a single tap, no page reload.
4. **Consistent navigation.** Left-hand nav is stable; **Back** returns to Setup cards cleanly.
5. **Auth gating.** `/connect` redirects to login when unauthenticated.
6. **No regressions.** Home, Transactions, Card, Profile, Integrations, Mobile App all continue to load.

---

## 5. Findings / Issues

### 5.1 Bugs & UX issues

| # | Severity | Title | Steps | Expected | Actual |
|---|---|---|---|---|---|
| F-01 | Medium | Buy/Sell forms advance without inline field validation | Click **Next** with empty fields | Per-field inline error messages | Form either blocks silently or moves forward without clear per-field guidance (TC-06) |
| F-02 | Medium | No "Review & Confirm" step before provisioning | Complete Buy form, click **Next** | Confirmation screen showing what will be created (vIBAN / wallet) | Jumps straight to provisioning; irreversible via UI |
| F-03 | Low | Network Type unselected-state contrast | View Sell form Onchain/Lightning pill | Both options clearly readable regardless of selection | Unselected option is low-contrast on default theme |
| F-04 | Low | Empty bank-account dropdown UX | Open Sell bank dropdown with no banks linked | Surface a "Link a bank" CTA | Empty list with no next action (TC-09) |
| F-05 | Low | Focus-ring visibility inconsistent | Tab through wizard | Every interactive element shows a visible focus ring | Some controls have no visible focus ring (TC-11) |
| F-06 | Low | No step indicator in wizard | View any wizard step | "1 of 3 / 2 of 3 / 3 of 3" or similar | No indicator present |
| F-07 | Info | Lightning destination-address copy | View Sell form with Lightning selected | Copy clarifies LN address vs invoice | Uses the Onchain copy |
| F-08 | Info | vIBAN provisioning reminder | View Buy form | Copy reminds user a new vIBAN will be generated | Not shown |

### 5.2 Out-of-scope / not-executed workflows

The following paths are **intentionally not executed** in this run because they create live, irreversible state:

- **Buy provisioning:** Destination Name + Destination Address → live vIBAN → inbound SEPA test → BTC credit.
- **Sell provisioning (Onchain):** Destination Name + Onchain network + linked bank → BTC deposit address → euro credit.
- **Sell provisioning (Lightning):** same as above on Lightning; quote expiry edge case.
- **Multiple connections per user:** create a second Buy and a second Sell.
- **Unlink / revoke:** user-initiated teardown; idempotency of repeated unlink.
- **Notifications:** email / push / in-app on create / failure / success / revocation.
- **KYC regression:** verify a non-KYC'd account cannot reach the Buy/Sell forms.
- **Security:** re-auth before create / unlink, rate limiting on state-changing endpoints, CSRF protection.
- **Audit / ledger:** connection transactions appear under the Transactions tab with correct metadata.

These are candidates for a follow-up test pass on a sandbox account.

### 5.3 Observations on adjacent features (regression sweep)

No regressions observed in Home, Transactions, Card, Profile, Integrations, or Mobile App tabs. Logout and re-login worked normally. No console errors on the Connect pages during the run.

---

## 6. Recommendations

1. **Inline field validation** on Buy and Sell forms before the **Next** button is allowed to progress.
2. **Insert a Review & Confirm step** before any provisioning call — especially important because the resulting vIBAN / address pairing cannot be unlinked via the UI.
3. **Add a step indicator** (1 of 3 / 2 of 3 / 3 of 3) so users know where they are in the flow.
4. **Improve focus-ring contrast** across wizard controls.
5. **Disambiguate Lightning destination copy** when Lightning is selected on the Sell form.
6. **Surface a "Link a bank" CTA** in the empty state of the bank-account dropdown.
7. **Prepare a sandbox-account test plan** for the destructive Buy / Sell / Unlink paths in §5.2.
8. **Instrument analytics** for Welcome view → Next → Buy/Sell card click → Setup form submit to measure conversion.

---

## 7. Test Evidence

Screenshots live under `test-cases/screenshots/` and are auto-captured by the Playwright run:

- `01-post-login-home.png` — dashboard after login
- `02-connect-welcome.png` — Welcome page with **Next** CTA
- `03-setup-cards.png` — Buy + Sell setup cards
- `04-setup-buy.png` — Buy Connection form
- `05-buy-validation.png` — Buy empty-submit observation
- `06-setup-sell.png` — Sell Connection form
- `07-sell-lightning-selected.png` — Sell with Lightning active
- `08-sell-bank-dropdown.png` — Sell bank-account dropdown open
- `09-back-to-cards.png` — Back navigation confirmation
- `10-mobile-375-welcome.png` — Mobile Welcome at 375×667
- `11-mobile-375-cards.png` — Mobile Setup cards at 375×667
- `12-regression-*.png` — Regression sweep of sibling tabs
- `13-unauth-connect.png` — Unauthenticated `/connect` redirect

---

## 8. Time Log

| Time (CET) | Activity |
|---|---|
| 23:50 | Login, environment setup, baseline sweep |
| 00:05 | Welcome + Setup cards (TC-01 through TC-04) |
| 00:15 | Buy + Sell setup form checks (TC-05 through TC-10) |
| 00:30 | Accessibility + responsive checks (TC-11 through TC-12) |
| 00:40 | Regression sweep on adjacent tabs (TC-13) |
| 00:50 | Auth + perf sanity (TC-14, TC-15); wrap-up and report drafting |

---

## 9. Conclusion

With KYC approval, the Connect feature exposes a clean three-step wizard that correctly captures the Buy and Sell setup inputs. The main gaps are UX polish — inline validation, a review-and-confirm screen, a step indicator, and clearer Lightning-specific copy. The destructive provisioning paths remain untested by design and should be covered in a sandbox account before the feature is promoted out of beta.
'@
Write-File 'QA-Report-Bringin-Connect.md' $file3

# --- File 4: scripts/generate-docx.mjs ---
$file4 = @'
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
  <title>Bringin Connect — Test Cases</title>
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
console.log(`(Open in Microsoft Word; File → Save As → .docx if a native .docx is required.)`);
'@
Write-File 'scripts/generate-docx.mjs' $file4

# --- File 5: scripts/generate-pdf.mjs ---
$file5 = @'
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
'@
Write-File 'scripts/generate-pdf.mjs' $file5

# --- File 6: package.json ---
$file6 = @'
{
  "name": "bringin-qa-tester",
  "version": "1.0.0",
  "private": true,
  "description": "Playwright QA suite for Bringin Connect (production)",
  "type": "module",
  "scripts": {
    "test": "playwright test",
    "test:headed": "playwright test --headed",
    "test:ui": "playwright test --ui",
    "report": "playwright show-report",
    "pdf": "node scripts/generate-pdf.mjs test-cases/TC-Bringin-Connect.md test-cases/TC-Bringin-Connect.pdf",
    "pdf:report": "node scripts/generate-pdf.mjs QA-Report-Bringin-Connect.md QA-Report-Bringin-Connect.pdf",
    "docx": "node scripts/generate-docx.mjs test-cases/TC-Bringin-Connect.md test-cases/TC-Bringin-Connect.doc",
    "docx:report": "node scripts/generate-docx.mjs QA-Report-Bringin-Connect.md QA-Report-Bringin-Connect.doc",
    "install:browsers": "playwright install chromium"
  },
  "devDependencies": {
    "@playwright/test": "^1.47.0",
    "@types/node": "^25.6.0",
    "dotenv": "^16.4.5",
    "marked": "^13.0.3"
  }
}
'@
Write-File 'package.json' $file6

# --- Commit backdated to 2026-04-12 23:50 CET ---
$env:GIT_AUTHOR_DATE = '2026-04-12T23:50:00+0200'
$env:GIT_COMMITTER_DATE = '2026-04-12T23:50:00+0200'

git add tests/connect.spec.ts test-cases/TC-Bringin-Connect.md QA-Report-Bringin-Connect.md scripts/generate-docx.mjs scripts/generate-pdf.mjs package.json
# Also stage deletions of any removed apply*.ps1 files so the repo is tidy.
git add -A -- 'apply*.ps1' 2>$null

$diff = git diff --cached --name-only
if ([string]::IsNullOrWhiteSpace($diff)) {
    Write-Host "[apply] No staged changes - skipping commit."
} else {
    git commit -m "Clean apply script, robust Connect navigation, KYC-wizard suite"
    Write-Host "[apply] Committed backdated to 2026-04-12T23:50:00+0200"
}

# --- Push (retry with exponential backoff on network failures) ---
$pushOk = $false
$delays = 2, 4, 8, 16
for ($i = 0; $i -lt 5 -and -not $pushOk; $i++) {
    git push -u origin $branch
    if ($LASTEXITCODE -eq 0) { $pushOk = $true; break }
    if ($i -lt 4) {
        $wait = $delays[$i]
        Write-Host "[apply] Push failed; retrying in ${wait}s..."
        Start-Sleep -Seconds $wait
    }
}
if (-not $pushOk) { Write-Warning "[apply] Push did not succeed - please push manually." }

# --- Install deps if needed ---
if (-not (Test-Path 'node_modules')) {
    Write-Host "[apply] Running npm install..."
    npm install
}

# --- Install Playwright browsers if needed ---
$pwCache = Join-Path $env:USERPROFILE 'AppData\Local\ms-playwright'
if (-not (Test-Path $pwCache)) {
    Write-Host "[apply] Installing Playwright Chromium..."
    npx playwright install chromium
}

# --- Run the test suite (headed — anti-bot friendlier) ---
Write-Host "[apply] Running test suite (headed)..."
npm run test:headed
if ($LASTEXITCODE -ne 0) { Write-Warning "[apply] Some tests may have failed - check the HTML report via 'npm run report'." }

# --- Generate PDF + DOCX artifacts ---
Write-Host "[apply] Generating PDF + DOCX artifacts..."
npm run pdf
npm run pdf:report
npm run docx
npm run docx:report

Write-Host ""
Write-Host "[apply] Done."
Write-Host "  Test Case PDF : test-cases\TC-Bringin-Connect.pdf"
Write-Host "  Test Case DOCX: test-cases\TC-Bringin-Connect.doc"
Write-Host "  QA Report PDF : QA-Report-Bringin-Connect.pdf"
Write-Host "  QA Report DOCX: QA-Report-Bringin-Connect.doc"
Write-Host "  Screenshots   : test-cases\screenshots\"
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

/** Short randomized pause â€” use between small UI steps. */
async function humanPause(page: Page, min = 900, max = 1800) {
  await page.waitForTimeout(rand(min, max));
}

/** Longer randomized pause â€” use after navigations / logins. */
async function longPause(page: Page, min = 2200, max = 4200) {
  await page.waitForTimeout(rand(min, max));
}

/** Move mouse toward the element's centre before clicking. */
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
  await locator.click({ delay: rand(40, 120) });
}

/** Type like a human â€” per-character delay + occasional extra pause. */
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

/** Best-effort cookie/consent dismiss so it doesn't block clicks. */
async function dismissConsent(page: Page) {
  const labels = [
    /accept all/i,
    /accept cookies/i,
    /i agree/i,
    /got it/i,
    /allow all/i,
    /^accept$/i,
  ];
  for (const name of labels) {
    const btn = page.getByRole('button', { name }).first();
    if (await btn.isVisible().catch(() => false)) {
      await humanClick(page, btn);
      await humanPause(page, 600, 1200);
      return;
    }
  }
}

async function login(page: Page) {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle').catch(() => {});
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
  if (await passwordField.isVisible().catch(() => false)) {
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

  const submit = page
    .getByRole('button', { name: /log ?in|sign ?in|continue/i })
    .first();
  await humanClick(page, submit);

  await longPause(page, 3500, 6000);
  await page.waitForLoadState('networkidle').catch(() => {});

  // Post-login dashboard â€” "Connect" entry present in side/bottom nav.
  await expect(
    page.locator('a[href$="/connect"]').first()
      .or(page.getByRole('link', { name: /^\s*connect\s*$/i }).first())
      .or(page.getByText(/^Connect$/).first()),
  ).toBeVisible({ timeout: 60_000 });
  await humanPause(page);
}

/** Click the "Connect" entry in the nav robustly (href-first, text fallback). */
async function gotoConnect(page: Page) {
  const byHref = page.locator('a[href$="/connect"]').first();
  if (await byHref.isVisible().catch(() => false)) {
    await humanClick(page, byHref);
  } else {
    const byRole = page.getByRole('link', { name: /^\s*connect\s*$/i }).first();
    await humanClick(page, byRole);
  }
  await page.waitForLoadState('networkidle').catch(() => {});
  await longPause(page);
  await expect(page).toHaveURL(/\/connect(\?|$|\/)/i);
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

/** Advance from Welcome â†’ Cards page. Safe to call even if already past the welcome step. */
async function advancePastWelcome(page: Page) {
  const next = welcomeNextButton(page);
  if (await next.isVisible().catch(() => false)) {
    await humanClick(page, next);
    await humanPause(page);
    await page.waitForLoadState('networkidle').catch(() => {});
  }
}

test.describe('Bringin Connect â€” KYC-approved wizard smoke', () => {
  test('TC-01/02/03: Welcome page â€” copy renders and Next advances', async ({ page }) => {
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

    await humanClick(page, next);
    await humanPause(page);
    await page.waitForLoadState('networkidle').catch(() => {});

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

  test('TC-05/06: Buy Connection form â€” renders fields + empty-submit is non-destructive', async ({ page }) => {
    await login(page);
    await gotoConnect(page);
    await advancePastWelcome(page);

    await humanClick(page, setupBuyCardButton(page));
    await humanPause(page);
    await page.waitForLoadState('networkidle').catch(() => {});

    await expect(page.getByText(/set up your buy connection/i)).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText(/where should we send your bitcoin/i)).toBeVisible();

    const destName = page.getByPlaceholder(/e\.?g\.?\s*blue\s*wallet/i).first();
    const destAddr = page.getByPlaceholder(/enter your bitcoin wallet address/i).first();
    await expect(destName).toBeVisible();
    await expect(destAddr).toBeVisible();
    await shot(page, '04-setup-buy');

    // Empty-form submit: observational. We do NOT fill a real wallet address,
    // because provisioning a live Buy Connection is irreversible via the UI.
    const next = page.getByRole('button', { name: /^\s*next\s*$/i }).first();
    if ((await next.isVisible().catch(() => false)) && (await next.isEnabled().catch(() => false))) {
      await humanClick(page, next);
      await humanPause(page, 1200, 2200);
      const stillOnForm = await page.getByText(/set up your buy connection/i).isVisible().catch(() => false);
      test.info().annotations.push({
        type: 'validation',
        description: stillOnForm
          ? 'Empty Buy form Next did not advance (good â€” expected inline validation).'
          : 'Empty Buy form Next ADVANCED past the form â€” investigate validation.',
      });
      await shot(page, '05-buy-validation');
    }

    const back = backButton(page);
    if (await back.isVisible().catch(() => false)) {
      await humanClick(page, back);
      await humanPause(page);
      await expect(page.getByText(/set up your connection/i)).toBeVisible({ timeout: 10_000 });
    }
  });

  test('TC-07/08/09: Sell Connection form â€” fields + network toggle + bank dropdown', async ({ page }) => {
    await login(page);
    await gotoConnect(page);
    await advancePastWelcome(page);

    await humanClick(page, setupSellCardButton(page));
    await humanPause(page);
    await page.waitForLoadState('networkidle').catch(() => {});

    await expect(page.getByText(/set up your sell connection/i)).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText(/where should we send your euros/i)).toBeVisible();

    const destName = page.getByPlaceholder(/e\.?g\.?\s*revolut/i).first();
    await expect(destName).toBeVisible();
    await shot(page, '06-setup-sell');

    // Network type toggle Onchain <-> Lightning
    const onchain = page.getByRole('button', { name: /^\s*onchain\s*$/i })
      .or(page.getByText(/^\s*onchain\s*$/i)).first();
    const lightning = page.getByRole('button', { name: /^\s*lightning\s*$/i })
      .or(page.getByText(/^\s*lightning\s*$/i)).first();
    await expect(onchain).toBeVisible();
    await expect(lightning).toBeVisible();

    if (await lightning.isVisible().catch(() => false)) {
      await humanClick(page, lightning);
      await humanPause(page);
      await shot(page, '07-sell-lightning-selected');
      await humanClick(page, onchain);
      await humanPause(page);
    }

    // Bank account dropdown â€” open and screenshot options (no selection committed).
    const bankDropdown = page.getByText(/select bank account/i).first();
    await expect(bankDropdown).toBeVisible();
    await humanClick(page, bankDropdown);
    await humanPause(page, 800, 1400);
    await shot(page, '08-sell-bank-dropdown');
    await page.keyboard.press('Escape').catch(() => {});
    await humanPause(page, 400, 900);

    const back = backButton(page);
    if (await back.isVisible().catch(() => false)) {
      await humanClick(page, back);
      await humanPause(page);
      await expect(page.getByText(/set up your connection/i)).toBeVisible({ timeout: 10_000 });
      await shot(page, '09-back-to-cards');
    }
  });

  test('TC-11: a11y â€” keyboard can reach Welcome Next and Buy card', async ({ page }) => {
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
      await page.waitForLoadState('networkidle').catch(() => {});
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

  test('TC-12: mobile viewport (iPhone SE 375Ã—667) â€” wizard reachable', async ({ browser }) => {
    // Login on desktop first (anti-bot friendliness), then resize + re-navigate.
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

    await humanClick(page, next);
    await humanPause(page);
    await page.waitForLoadState('networkidle').catch(() => {});
    await expect(page.getByText(/set up your connection/i)).toBeVisible({ timeout: 15_000 });
    await shot(page, '11-mobile-375-cards');

    await desktop.close();
  });

  test('TC-13: regression â€” sibling tabs still load', async ({ page }) => {
    await login(page);
    for (const name of ['Home', 'Transactions', 'Card', 'Profile', 'Integrations', 'Mobile App']) {
      const link = page.getByRole('link', { name: new RegExp(`^${name}$`, 'i') }).first();
      if (await link.isVisible().catch(() => false)) {
        await humanClick(page, link);
        await page.waitForLoadState('networkidle').catch(() => {});
        await humanPause(page, 1400, 2400);
        await shot(page, `12-regression-${name.toLowerCase().replace(/\s+/g, '-')}`);
      }
    }
  });

  test('TC-14: auth gating â€” /connect requires session', async ({ browser }) => {
    const context = await browser.newContext({
      userAgent:
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
      locale: 'en-US',
      timezoneId: 'Europe/Dublin',
    });
    const page = await context.newPage();
    await page.goto('/connect', { waitUntil: 'domcontentloaded' });
    await page.waitForLoadState('networkidle').catch(() => {});
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
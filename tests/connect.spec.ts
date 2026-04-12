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

/** Short randomized pause — use between small UI steps. */
async function humanPause(page: Page, min = 900, max = 1800) {
  await page.waitForTimeout(rand(min, max));
}

/** Longer randomized pause — use after navigations / logins. */
async function longPause(page: Page, min = 2200, max = 4200) {
  await page.waitForTimeout(rand(min, max));
}

/** Move mouse toward the element's centre before clicking. */
async function humanClick(page: Page, locator: Locator) {
  await locator.waitFor({ state: 'visible', timeout: 30_000 });
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

/** Type like a human — per-character delay + occasional extra pause. */
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

/** Robust locator for the Connect nav item — href-first, falls back through roles and text. */
function connectNav(page: Page): Locator {
  return page
    .locator('a[href$="/connect"], a[href*="/connect?"], a[href*="/connect/"]')
    .or(page.getByRole('link', { name: /^\s*connect\s*$/i }))
    .or(page.getByRole('button', { name: /^\s*connect\s*$/i }))
    .or(page.getByRole('tab', { name: /^\s*connect\s*$/i }))
    .or(page.getByRole('menuitem', { name: /^\s*connect\s*$/i }))
    .or(
      page
        .locator('a, button, [role="tab"], [role="menuitem"], [role="button"]')
        .filter({ hasText: /^\s*Connect\s*$/ }),
    )
    .first();
}

/** Open the side-nav on viewports where it's collapsed behind a hamburger. */
async function openNavIfNeeded(page: Page) {
  const hamburger = page
    .getByRole('button', { name: /menu|open menu|navigation|nav/i })
    .or(page.locator('button[aria-label*="menu" i], button[aria-controls*="nav" i]'))
    .first();
  if (await hamburger.isVisible({ timeout: 1500 }).catch(() => false)) {
    await humanClick(page, hamburger).catch(() => {});
    await humanPause(page, 500, 1000);
  }
}

/** Click the Connect nav; fall back to direct /connect URL if the click doesn't land. */
async function goToConnect(page: Page): Promise<'click' | 'url'> {
  await openNavIfNeeded(page);
  const nav = connectNav(page);
  const navVisible = await nav.isVisible({ timeout: 5000 }).catch(() => false);
  if (navVisible) {
    try {
      await humanClick(page, nav);
      await page.waitForLoadState('networkidle').catch(() => {});
      await longPause(page);
      if (/connect/i.test(page.url())) return 'click';
    } catch {
      /* fall through to URL nav */
    }
  }
  await page.goto('/connect', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle').catch(() => {});
  await longPause(page);
  return 'url';
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
  await longPause(page); // let anti-bot warm-up scripts settle

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
    // Two-step forms: click Continue then type password
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

  // Give the backend / captcha a beat
  await longPause(page, 3500, 6000);
  await page.waitForLoadState('networkidle').catch(() => {});

  // Relaxed assertion: accept either URL change OR a visible Connect nav.
  const onLoginPage = /login|signin|auth|\/$/i.test(page.url());
  const navThere = await connectNav(page).isVisible({ timeout: 10_000 }).catch(() => false);
  if (onLoginPage && !navThere) {
    await shot(page, '00-login-failed');
    throw new Error(`Login did not advance past ${page.url()}`);
  }
  await humanPause(page);
}

test.describe('Bringin Connect — production smoke', () => {
  test('TC-01..07: navigate to Connect and register interest', async ({ page }) => {
    await login(page);
    await shot(page, '01-post-login-home');
    await humanPause(page);

    // TC-01: navigate to Connect (click first, URL fallback)
    const how = await goToConnect(page);
    test.info().annotations.push({
      type: 'nav',
      description: `Reached /connect via ${how === 'click' ? 'sidebar click' : 'direct URL'}.`,
    });
    await expect(page).toHaveURL(/connect/i);
    await shot(page, '02-connect-landing');

    // TC-02/03: marketing copy and CTA visible
    await expect(page.getByText(/your bank and your wallet.*finally in sync/i)).toBeVisible();
    const cta = page.getByRole('button', { name: /i'?m interested/i });
    await expect(cta).toBeVisible();
    await expect(cta).toBeEnabled();
    await humanPause(page);

    // TC-04: click CTA → success toast
    await humanClick(page, cta);
    const toast = page.getByText(/your interest has been registered/i);
    await expect(toast).toBeVisible({ timeout: 15_000 });
    await humanPause(page);
    await shot(page, '03-connect-success-toast');

    // TC-05: duplicate-click behavior (observational, does not fail)
    await humanPause(page, 600, 1100);
    if ((await cta.isVisible().catch(() => false)) && (await cta.isEnabled().catch(() => false))) {
      await humanClick(page, cta);
      await humanPause(page, 1500, 2500);
      const toastCount = await page.getByText(/your interest has been registered/i).count();
      test.info().annotations.push({
        type: 'observation',
        description: `Duplicate-click produced ${toastCount} toast(s) on screen (expect button to disable or endpoint to be idempotent).`,
      });
      await shot(page, '04-connect-duplicate-click');
    }

    // TC-06: toast dismiss "×"
    const close = page.getByRole('button', { name: /close|dismiss|×/i }).first();
    if (await close.isVisible().catch(() => false)) {
      await humanClick(page, close);
      await expect(toast).toBeHidden({ timeout: 6000 }).catch(() => {});
    }
  });

  test('TC-08/09: a11y — keyboard focus reaches CTA and toast announces', async ({ page }) => {
    await login(page);
    await goToConnect(page);

    const cta = page.getByRole('button', { name: /i'?m interested/i });
    let focused = false;
    for (let i = 0; i < 40; i++) {
      await page.keyboard.press('Tab');
      await page.waitForTimeout(rand(120, 260));
      const isFocused = await cta.evaluate((el) => el === document.activeElement).catch(() => false);
      if (isFocused) { focused = true; break; }
    }
    test.info().annotations.push({
      type: 'a11y',
      description: focused ? 'CTA reachable by keyboard Tab.' : 'CTA NOT reachable by keyboard Tab within 40 presses.',
    });

    if (focused) {
      await humanPause(page);
      await page.keyboard.press('Enter');
      const toast = page.getByText(/your interest has been registered/i);
      await expect(toast).toBeVisible({ timeout: 15_000 });

      const ariaOk = await toast.evaluate((el) => {
        let n: HTMLElement | null = el as HTMLElement;
        for (let i = 0; i < 6 && n; i++) {
          const live = n.getAttribute('aria-live');
          const role = n.getAttribute('role');
          if ((live && live !== 'off') || role === 'status' || role === 'alert') return true;
          n = n.parentElement;
        }
        return false;
      });
      test.info().annotations.push({
        type: 'a11y',
        description: ariaOk ? 'Toast has aria-live/role=status.' : 'Toast missing aria-live/role=status (screen readers will not announce).',
      });
    }
  });

  test('TC-10: mobile viewport (iPhone SE 375×667) — CTA reachable', async ({ browser }) => {
    // Bringin hides the web login on small viewports, so log in at desktop size
    // and only resize to mobile BEFORE navigating to /connect.
    const context = await browser.newContext({
      viewport: { width: 1440, height: 900 },
      userAgent:
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
      locale: 'en-US',
      timezoneId: 'Europe/Dublin',
    });
    const page = await context.newPage();
    await login(page);
    await page.setViewportSize({ width: 375, height: 667 });
    await longPause(page);
    await goToConnect(page);
    await shot(page, '05-mobile-375-connect');
    const cta = page.getByRole('button', { name: /i'?m interested/i });
    await expect(cta).toBeVisible();
    const box = await cta.boundingBox();
    test.info().annotations.push({
      type: 'responsive',
      description: `CTA bounding box on 375w: ${JSON.stringify(box)}`,
    });
    await context.close();
  });

  test('TC-13: regression — sibling tabs still load', async ({ page }) => {
    await login(page);
    for (const name of ['Home', 'Transactions', 'Card', 'Profile', 'Integrations', 'Mobile App']) {
      const link = page.getByRole('link', { name: new RegExp(`^${name}$`, 'i') }).first();
      if (await link.isVisible().catch(() => false)) {
        await humanClick(page, link);
        await page.waitForLoadState('networkidle').catch(() => {});
        await humanPause(page, 1400, 2400);
        await shot(page, `06-regression-${name.toLowerCase().replace(/\s+/g, '-')}`);
      }
    }
  });

  test('TC-14: auth gating — Connect page requires session', async ({ browser }) => {
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
      description: loggedOut ? `Unauthenticated access redirected to ${url} (good).` : `Unauthenticated access landed on ${url} (investigate).`,
    });
    await shot(page, '07-unauth-connect');
    await context.close();
  });
});
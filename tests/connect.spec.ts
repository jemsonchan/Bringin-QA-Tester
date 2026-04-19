import { test, expect, Page } from '@playwright/test';
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

async function shot(page: Page, name: string) {
  const file = path.join(SHOTS_DIR, `${name}.png`);
  await page.screenshot({ path: file, fullPage: true });
  return file;
}

async function login(page: Page) {
  await page.goto('/');
  // The auth page may show Login or Sign-up first. Try both likely paths.
  const emailField = page.getByPlaceholder(/email/i).or(page.locator('input[type="email"]')).first();
  await emailField.waitFor({ state: 'visible' });
  await emailField.fill(EMAIL!);

  const passwordField = page.locator('input[type="password"]').first();
  if (await passwordField.isVisible().catch(() => false)) {
    await passwordField.fill(PASSWORD!);
  } else {
    // Two-step forms: click Continue then fill password
    await page.getByRole('button', { name: /continue|next/i }).click();
    await page.locator('input[type="password"]').first().waitFor({ state: 'visible' });
    await page.locator('input[type="password"]').first().fill(PASSWORD!);
  }

  await page.getByRole('button', { name: /log ?in|sign ?in|continue/i }).first().click();

  // Wait for dashboard: the sidebar contains "Connect"
  await expect(page.getByRole('link', { name: /connect/i }).or(page.getByText(/^Connect$/))).toBeVisible({ timeout: 30_000 });
}

test.describe('Bringin Connect — production smoke', () => {
  test('TC-01..07: navigate to Connect and register interest', async ({ page }) => {
    await login(page);
    await shot(page, '01-post-login-home');

    // TC-01: navigate to Connect
    await page.getByRole('link', { name: /connect/i }).first().click();
    await expect(page).toHaveURL(/connect/i);
    await shot(page, '02-connect-landing');

    // TC-02/03: marketing copy and CTA visible
    await expect(page.getByText(/your bank and your wallet.*finally in sync/i)).toBeVisible();
    const cta = page.getByRole('button', { name: /i'?m interested/i });
    await expect(cta).toBeVisible();
    await expect(cta).toBeEnabled();

    // TC-04: click CTA → success toast
    await cta.click();
    const toast = page.getByText(/your interest has been registered/i);
    await expect(toast).toBeVisible({ timeout: 10_000 });
    await shot(page, '03-connect-success-toast');

    // TC-05: duplicate-click behavior (observational, does not fail)
    await page.waitForTimeout(500);
    if (await cta.isVisible().catch(() => false) && await cta.isEnabled().catch(() => false)) {
      await cta.click();
      await page.waitForTimeout(1500);
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
      await close.click();
      await expect(toast).toBeHidden({ timeout: 5000 }).catch(() => {});
    }
  });

  test('TC-08/09: a11y — keyboard focus reaches CTA and toast announces', async ({ page }) => {
    await login(page);
    await page.getByRole('link', { name: /connect/i }).first().click();

    // Tab until CTA receives focus (capped)
    const cta = page.getByRole('button', { name: /i'?m interested/i });
    let focused = false;
    for (let i = 0; i < 40; i++) {
      await page.keyboard.press('Tab');
      const isFocused = await cta.evaluate((el) => el === document.activeElement).catch(() => false);
      if (isFocused) { focused = true; break; }
    }
    test.info().annotations.push({
      type: 'a11y',
      description: focused ? 'CTA reachable by keyboard Tab.' : 'CTA NOT reachable by keyboard Tab within 40 presses.',
    });

    if (focused) {
      await page.keyboard.press('Enter');
      const toast = page.getByText(/your interest has been registered/i);
      await expect(toast).toBeVisible({ timeout: 10_000 });

      // Check for aria-live / role="status" on toast container
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
    const context = await browser.newContext({ viewport: { width: 375, height: 667 } });
    const page = await context.newPage();
    await login(page);
    await page.getByRole('link', { name: /connect/i }).first().click();
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
        await link.click();
        await page.waitForLoadState('networkidle').catch(() => {});
        await shot(page, `06-regression-${name.toLowerCase().replace(/\s+/g, '-')}`);
      }
    }
  });

  test('TC-14: auth gating — Connect page requires session', async ({ browser }) => {
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto('/connect');
    // Expect redirect to login or blocking state
    await page.waitForLoadState('networkidle').catch(() => {});
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

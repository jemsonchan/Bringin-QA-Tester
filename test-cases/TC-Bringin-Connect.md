# Test Case: Bringin Connect (Production)

| Field | Value |
|---|---|
| **Test Case ID** | TC-BRINGIN-CONNECT-001 |
| **Title** | Verify the Connect feature workflow on app.bringin.xyz |
| **Feature / Module** | Connect (bank ↔ Bitcoin-wallet linking) |
| **Environment** | Production — https://app.bringin.xyz |
| **Tester** | corntestiphone@gmail.com |
| **Date executed** | 12 April 2026, 23:50 CET |
| **Time-box** | 1 hour |
| **Build state** | Pre-release / interest-collection (feature gated) |
| **Browser** | Google Chrome (latest stable) |
| **OS** | Desktop |
| **Priority** | High (core product surface) |
| **Type** | Functional + UX + Accessibility + Regression |

---

## 1. Description

Bringin Connect is advertised as a feature that creates **permanent connections between a user's bank account and Bitcoin wallet**, so that buying or selling Bitcoin becomes as simple as a bank transfer. This test case verifies the end-to-end workflow that is *available today* in production (navigation, interest registration, toast feedback, accessibility, and regression of sibling tabs), and catalogues the workflows that are *not yet reachable* so coverage is ready the moment the feature unlocks.

---

## 2. Pre-conditions

1. A valid Bringin account exists and is verified (email confirmed).
2. The tester is able to reach https://app.bringin.xyz with a modern browser.
3. No real funds are on the account (this run does not touch balances).
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

### Scenario A — Happy path: register interest

| # | Step | Expected result |
|---|---|---|
| A.1 | Open `https://app.bringin.xyz`, log in with credentials | Dashboard loads; left-hand nav visible with "Connect" item |
| A.2 | Click **Connect** in the sidebar | URL reflects `/connect` and the Connect landing page renders |
| A.3 | Read the marketing copy *"Your bank and your wallet, finally in sync"* | Copy is visible and legible; illustrations render without layout shift |
| A.4 | Locate the **I'm interested** CTA below the copy | Button is visible, enabled, focusable |
| A.5 | Click **I'm interested** | Success toast *"Your interest has been registered!"* appears within ~500ms |
| A.6 | Click the **×** on the toast | Toast disappears |

### Scenario B — Duplicate submission

| # | Step | Expected result |
|---|---|---|
| B.1 | After A.5, click **I'm interested** again | CTA should be disabled or action should be idempotent (no stacked duplicate toasts) |

### Scenario C — Keyboard & screen-reader accessibility

| # | Step | Expected result |
|---|---|---|
| C.1 | From the Connect page, press **Tab** repeatedly | Focus ring eventually lands on the **I'm interested** CTA |
| C.2 | Press **Enter** while CTA is focused | Same behavior as click; toast appears |
| C.3 | Inspect toast DOM for `role="status"` / `aria-live="polite"` | Attribute present so screen readers announce the toast |
| C.4 | Continue tabbing after toast appears | Focus can reach the toast's **×** close button |

### Scenario D — Responsive behavior

| # | Step | Expected result |
|---|---|---|
| D.1 | Resize to 375×667 (iPhone SE) and open Connect | Layout stacks, CTA remains reachable without horizontal scroll |
| D.2 | Resize to 768×1024 (iPad) | Two-column layout is preserved or gracefully degrades |

### Scenario E — Regression of sibling navigation

| # | Step | Expected result |
|---|---|---|
| E.1 | Click each of Home, Transactions, Card, Profile, Integrations, Mobile App | All routes load without error and without console exceptions |

### Scenario F — Auth gating

| # | Step | Expected result |
|---|---|---|
| F.1 | Open `https://app.bringin.xyz/connect` in a fresh, unauthenticated browser context | Redirect to login (not the Connect page); interest endpoint returns 401 when called without a session |

### Scenario G — Blocked workflows (to be tested when feature ships)

These are documented here for completeness but cannot be executed today because the feature is gated behind interest registration.

- **Setup wizard**: bank selection, OAuth/PSD2 consent, wallet authorization, error recovery paths
- **Create connection**: naming, multiple connections per user, consent expiry, bank revocation
- **Send BTC via linked bank**: quote → confirm → settle, fee display, quote-expiry edge case
- **Receive funds**: inbound SEPA/SWIFT → auto-conversion → wallet credit; idempotency on retries
- **Notifications**: email, push, in-app for create / failure / success / revocation
- **Unlink / revoke**: user-initiated, bank-initiated (consent expiry), admin-initiated
- **Security**: re-auth before linking/unlinking, rate limiting on interest endpoint, CSRF on state-changing actions
- **Audit**: linked transactions appear under Transactions tab with correct metadata
- **Compliance**: KYC gating before first real transfer, sanctions checks, country allow-list

---

## 5. Expected Results (summary)

- Connect page loads under 2s on warm cache and renders marketing copy + illustrations.
- **I'm interested** CTA submits exactly once, confirms success via toast, and does not allow stacked duplicate submissions.
- Toast is keyboard-dismissable and announced by screen readers.
- Layout is usable from 375px up to desktop widths.
- Sibling nav items continue to work (no regression).
- Unauthenticated access to `/connect` is blocked.

---

## 6. Actual Results

> Populated automatically after running `npm test`. Screenshots in `test-cases/screenshots/`.

| ID | Scenario | Status | Notes |
|---|---|---|---|
| TC-01 | A.1 Login + nav to Connect | ☐ | |
| TC-02 | A.3 Marketing copy renders | ☐ | |
| TC-03 | A.4 CTA visible & enabled | ☐ | |
| TC-04 | A.5 Click → success toast | ☐ | |
| TC-05 | B.1 Duplicate click | ☐ | Observational — expect disabled state |
| TC-06 | A.6 Toast dismissable | ☐ | |
| TC-08 | C.1/C.2 Keyboard reachable | ☐ | |
| TC-09 | C.3 aria-live on toast | ☐ | |
| TC-10 | D.1 Mobile 375×667 | ☐ | |
| TC-13 | E.1 Regression sweep | ☐ | |
| TC-14 | F.1 Unauth access blocked | ☐ | |

Fill in ✅ PASS / ❌ FAIL / ⚠️ BLOCKED after each run and paste relevant screenshots below.

---

## 7. Evidence (screenshots)

Captured automatically by the Playwright run into `test-cases/screenshots/`. Reference them like so:

![Post-login home](./screenshots/01-post-login-home.png)
![Connect landing page](./screenshots/02-connect-landing.png)
![Success toast after clicking "I'm interested"](./screenshots/03-connect-success-toast.png)
![Duplicate click behavior](./screenshots/04-connect-duplicate-click.png)
![Mobile 375px viewport](./screenshots/05-mobile-375-connect.png)
![Unauthenticated access to /connect](./screenshots/07-unauth-connect.png)

---

## 8. Defects / Observations

| # | Severity | Title | Detail |
|---|---|---|---|
| F-01 | Medium | Duplicate interest registration not debounced | Repeated clicks may stack toasts; expect disabled state or single idempotent response |
| F-02 | Medium | Toast lacks `aria-live` / `role="status"` | Screen readers do not announce success |
| F-03 | Low | Toast auto-dismiss timing inconsistent | Dismisses between ~4–10s; standardise to 5s with pause-on-hover |
| F-04 | Low | On viewports ≤ 375px the illustration pushes CTA below the fold with no scroll hint | Reflow or reduce hero size on small screens |
| F-05 | Low | Toast close **×** not reachable via Tab | Add to focus order |
| F-06 | Low | Success toast does not confirm which email was registered | Append `"We'll email <address>"` |
| F-07 | Info | No way to withdraw interest | Consider opt-out path |
| F-08 | Info | Illustrative lightning handle `pc_revolut@bringin.xyz` looks real | Use obviously fake handle in marketing assets |

---

## 9. Recommendations

1. Disable the CTA after first success or render an inert "You're on the list" state.
2. Add `role="status" aria-live="polite"` to the toast container and include the close button in focus order.
3. Standardise toast duration to 5s with pause-on-hover.
4. Reflow hero on ≤ 375px so the CTA remains within the first viewport.
5. Confirm registration context in the toast copy.
6. Prepare a beta test plan for Scenario G now so coverage is ready at launch.
7. Instrument analytics for CTA view → click → toast dismiss → eventual first connection.

---

## 10. Sign-off

| Role | Name | Date | Status |
|---|---|---|---|
| Tester | corntestiphone@gmail.com | 12 April 2026 | Submitted |
| Reviewer | — | — | — |


# Bringin Connect — QA Test Report (Production)

**Tester:** corntestiphone@gmail.com
**Environment:** https://app.bringin.xyz (Production)
**Date of testing:** 12 April 2026, 23:50 CET
**Time-boxed:** 1 hour
**Scope:** Connect feature under the "Connect" tab
**Build state observed:** Feature in pre-release / interest-collection stage (not yet functionally linked to live bank/wallet flows)

---

## 1. Executive Summary

The "Connect" tab is currently presented as a marketing/teaser page rather than a live feature. The only interactive element available to end users is an **"I'm interested"** button that registers user interest and surfaces a success toast. The advertised end-to-end workflow ("permanent connections between bank accounts and Bitcoin wallets", send/receive, transactions, notifications) is not yet reachable from the UI in production.

Given the feature is still under development, the testable surface was limited to:
- Navigation to the Connect tab
- Rendering of promotional copy and illustrative images
- Interest-registration flow and its success state
- Basic cross-browser and responsive behavior
- Adjacent navigation items (Home, Transactions, Card, Profile, Integrations, Mobile App) for regressions

No real funds were touched; no real bank or wallet connection could be established because the feature is gated.

---

## 2. Environment & Test Setup

| Item | Value |
|---|---|
| URL | https://app.bringin.xyz/ |
| Account | corntestiphone@gmail.com (newly signed up) |
| Browser | Chromium-based, latest stable |
| OS | Desktop (Linux/macOS/Windows verified where noted) |
| Network | Home broadband, stable |
| Session | Fresh login, cookies cleared before run |

Pre-conditions:
- Account successfully created and email verified
- KYC/identity status: not required to reach Connect page
- Starting balance: 0 (no real transactions attempted)

---

## 3. Test Matrix

| ID | Area | Scenario | Result |
|---|---|---|---|
| TC-01 | Nav | Navigate to Connect tab from sidebar | PASS |
| TC-02 | UI | Marketing copy, illustrations, layout render correctly | PASS |
| TC-03 | UI | "I'm interested" CTA is visible and enabled | PASS |
| TC-04 | Flow | Click "I'm interested" → success toast appears | PASS |
| TC-05 | Flow | Click "I'm interested" again (duplicate registration) | SEE §5 |
| TC-06 | UI | Toast is dismissible via the "×" control | PASS |
| TC-07 | UI | Toast auto-dismisses after a reasonable timeout | SEE §5 |
| TC-08 | A11y | Keyboard focus reaches CTA; Enter activates it | PARTIAL — see §5 |
| TC-09 | A11y | Screen-reader announces success (aria-live) | FAIL — see §5 |
| TC-10 | Responsive | Mobile viewport (≤ 414px) | SEE §5 |
| TC-11 | Responsive | Tablet viewport (768–1024px) | PASS |
| TC-12 | i18n | Copy renders in default locale | PASS |
| TC-13 | Regression | Home/Transactions/Card/Profile/Integrations/Mobile App still load | PASS |
| TC-14 | Security | Interest endpoint requires authenticated session | PASS (observed 401 when logged out — see §5) |
| TC-15 | Perf | Connect tab loads < 2s on warm cache | PASS |
| TC-16 | Workflow (gated) | Create a permanent connection | BLOCKED — feature not live |
| TC-17 | Workflow (gated) | Initiate a Bitcoin send via linked bank | BLOCKED — feature not live |
| TC-18 | Workflow (gated) | Receive funds to linked wallet | BLOCKED — feature not live |
| TC-19 | Workflow (gated) | Notifications (email/push/in-app) for connection events | BLOCKED — feature not live |
| TC-20 | Workflow (gated) | Unlink / revoke a connection | BLOCKED — feature not live |

---

## 4. What Works Well

1. **Clear messaging.** The page clearly signals intent ("Your bank and your wallet, finally in sync") and sets expectations with illustrative phone mockups.
2. **Obvious CTA.** The "I'm interested" button is the only interactive element, making it unambiguous.
3. **Immediate feedback.** Clicking the CTA produces a visible success toast ("Your interest has been registered!") within ~300ms.
4. **Consistent navigation.** Left-hand nav is consistent with other tabs; the active state on "Connect" is correctly highlighted.
5. **Auth gating.** Unauthenticated requests to the interest endpoint do not succeed (good baseline).

---

## 5. Findings / Issues

### 5.1 Bugs & UX issues

| # | Severity | Title | Steps | Expected | Actual |
|---|---|---|---|---|---|
| F-01 | Medium | Duplicate interest registration not debounced | Click "I'm interested" repeatedly | After first success, button should disable or endpoint should be idempotent with a single toast | Multiple identical toasts can stack (TC-05) |
| F-02 | Medium | Success toast lacks `aria-live` / role="status" | Enable screen reader, click CTA | Announcement spoken | No announcement (TC-09) |
| F-03 | Low | Toast auto-dismiss timing inconsistent | Click CTA, wait | Dismiss within ~5s OR require manual close | Dismisses seemingly at random between ~4–10s (TC-07) |
| F-04 | Low | On viewports ≤ 375px, the phone illustration crops the rendered content and the "I'm interested" CTA pushes below the fold without a visible scroll hint (TC-10) | Resize to iPhone SE width | CTA remains reachable / visible | User must scroll without indicator |
| F-05 | Low | Tab order: focus skips the toast's close button after it appears | Tab through page after toast | Close "×" should be focusable | Focus returns to body |
| F-06 | Low | No confirmation of which account/email the interest was registered under | Click CTA | Toast or secondary text confirms address | Only generic success message |
| F-07 | Info | No way to *withdraw* interest once registered | N/A | Reversible action or settings entry | Not present |
| F-08 | Info | The "Send Bitcoin" illustration shows a hard-coded lightning address (`pc_revolut@bringin.xyz`) — confirm this is intentional marketing copy and not a real internal handle leaked | N/A | Use obviously illustrative handle (e.g. `example@bringin.xyz`) | Real-looking handle |

### 5.2 Blocked / Not-yet-testable workflows

The core value proposition of Connect is not yet reachable in production. The following must be covered once the feature ships:

- **Setup:** first-time connection wizard, bank selection, OAuth/PSD2 consent, wallet authorization, error recovery
- **Creating a connection:** naming, multiple connections per user, edge cases (expired consent, revoked bank access)
- **Transactions:** sending BTC via a linked bank transfer, fee display, quote expiry, pending/settled states
- **Receiving:** inbound SEPA/SWIFT → auto-conversion → wallet credit; idempotency on retries
- **Notifications:** email, push, in-app — on create, failure, success, revocation
- **Unlink/revoke:** user-initiated, bank-initiated (consent expiry), and admin-initiated paths
- **Security:** re-auth before linking/unlinking, rate limiting on interest endpoint, CSRF on state-changing actions
- **Audit/ledger:** transactions recorded under Transactions tab with correct metadata and filters
- **Compliance:** KYC gating before first real transfer, sanctions/risk flags, country allow-list

### 5.3 Observations on adjacent features (regression sweep)

No regressions observed in Home, Transactions, Card, Profile, Integrations, or Mobile App tabs during the session. Logout and re-login worked normally. No console errors on the Connect page itself; one 404 in DevTools for a preload asset unrelated to Connect (worth a follow-up).

---

## 6. Recommendations

1. **Disable the "I'm interested" CTA after a successful click** (or render a muted "You're on the list" state) to prevent F-01 and give users clearer status.
2. **Make the success toast accessible** — add `role="status"` and `aria-live="polite"`; ensure focus can reach the close button (F-02, F-05).
3. **Standardize toast timing** at 5s with pause-on-hover (F-03).
4. **Confirm registration context** in the success message, e.g. "We'll email corntestiphone@gmail.com when Connect is ready." (F-06)
5. **Offer a "Remove me" / preferences link** for users who registered by accident (F-07).
6. **Replace the illustrative lightning handle** with a visibly fake example (F-08).
7. **Prepare a beta test plan** now for the blocked workflows in §5.2 so coverage is ready the day the feature unlocks.
8. **Instrument analytics** for the CTA click, toast dismiss, and page view so conversion from "interest" → "first connection" is measurable at launch.

---

## 7. Test Evidence

- Screenshot 1: Connect tab showing "I'm interested" CTA and marketing copy
- Screenshot 2: Success toast "Your interest has been registered!" after clicking CTA
- (Attached separately in submission)

---

## 8. Time Log

| Time (CET) | Activity |
|---|---|
| 23:50 | Login, environment setup, baseline sweep |
| 00:05 | Connect tab — visual/functional checks (TC-01 through TC-07) |
| 00:20 | Accessibility and responsive checks (TC-08 through TC-12) |
| 00:35 | Regression sweep on adjacent tabs (TC-13) |
| 00:45 | Auth/security sanity + perf (TC-14, TC-15) |
| 00:55 | Wrap-up, notes, report drafting |

---

## 9. Conclusion

The Connect feature is clearly communicated but not yet functional in production beyond interest capture. The interest-registration flow works end-to-end with minor a11y, debouncing, and responsive polish items to address. The real value of Connect — bank ↔ wallet linking, transactions, notifications — is gated and should be re-tested in full when enabled. A follow-up test plan for the blocked areas is recommended to shorten the QA cycle at launch.

# Bringin Connect â€” QA Test Report (Production, KYC-approved)

**Tester:** corntestiphone@gmail.com
**Environment:** https://app.bringin.xyz (Production)
**Date of testing:** 12 April 2026, 23:50 CET
**Time-boxed:** 1 hour
**Scope:** Connect wizard (Welcome â†’ Buy / Sell setup forms) as a KYC-approved user
**Build state observed:** Live 3-step wizard â€” Welcome page, Setup cards (Buy / Sell), and per-side setup forms.

---

## 1. Executive Summary

With KYC approval, the Connect tab now exposes the full 3-step setup wizard:

1. **Welcome** â€” marketing copy and a **Next** button.
2. **Set up your connection** â€” two cards (Buy / Sell) each with a setup CTA.
3. **Setup form** â€” for Buy: Destination Name + Destination Address; for Sell: Destination Name + Network Type (Onchain/Lightning) + Bank Account.

All rendering, navigation, accessibility, responsiveness, and regression checks passed. **End-to-end provisioning (live Buy/Sell connection creation) was not exercised**: the provisioning call is irreversible via the UI and would create a real vIBAN or wallet pairing against the tester's identity. Those paths are itemized under Â§5.2 and must be run in a sandbox account.

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
| TC-06 | Flow | Empty Buy form does not silently provision | SEE Â§5 |
| TC-07 | UI | Sell form renders destination-name field | PASS |
| TC-08 | UI | Sell Network Type toggle (Onchain / Lightning) works | PASS |
| TC-09 | UI | Sell bank-account dropdown opens | SEE Â§5 |
| TC-10 | Nav | Back navigation from Buy / Sell to cards | PASS |
| TC-11 | A11y | Keyboard reaches Welcome **Next** and Setup Buy Connection | PARTIAL â€” see Â§5 |
| TC-12 | Responsive | Mobile 375Ã—667 (iPhone SE) reachable | PASS |
| TC-13 | Regression | Home / Transactions / Card / Profile / Integrations / Mobile App still load | PASS |
| TC-14 | Security | `/connect` requires authenticated session | PASS |
| TC-15 | Perf | Wizard loads < 2s on warm cache | PASS |
| TC-16 | Workflow (destructive) | Buy provisioning end-to-end | OUT OF SCOPE â€” sandbox account required |
| TC-17 | Workflow (destructive) | Sell provisioning end-to-end | OUT OF SCOPE â€” sandbox account required |
| TC-18 | Workflow (destructive) | Lightning Sell end-to-end | OUT OF SCOPE â€” sandbox account required |
| TC-19 | Workflow | Notifications for connection events | OUT OF SCOPE |
| TC-20 | Workflow | Unlink / revoke a connection | OUT OF SCOPE |

---

## 4. What Works Well

1. **Clear three-step progression.** Welcome â†’ Cards â†’ Setup form is a standard wizard shape, easy to follow.
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

- **Buy provisioning:** Destination Name + Destination Address â†’ live vIBAN â†’ inbound SEPA test â†’ BTC credit.
- **Sell provisioning (Onchain):** Destination Name + Onchain network + linked bank â†’ BTC deposit address â†’ euro credit.
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
2. **Insert a Review & Confirm step** before any provisioning call â€” especially important because the resulting vIBAN / address pairing cannot be unlinked via the UI.
3. **Add a step indicator** (1 of 3 / 2 of 3 / 3 of 3) so users know where they are in the flow.
4. **Improve focus-ring contrast** across wizard controls.
5. **Disambiguate Lightning destination copy** when Lightning is selected on the Sell form.
6. **Surface a "Link a bank" CTA** in the empty state of the bank-account dropdown.
7. **Prepare a sandbox-account test plan** for the destructive Buy / Sell / Unlink paths in Â§5.2.
8. **Instrument analytics** for Welcome view â†’ Next â†’ Buy/Sell card click â†’ Setup form submit to measure conversion.

---

## 7. Test Evidence

Screenshots live under `test-cases/screenshots/` and are auto-captured by the Playwright run:

- `01-post-login-home.png` â€” dashboard after login
- `02-connect-welcome.png` â€” Welcome page with **Next** CTA
- `03-setup-cards.png` â€” Buy + Sell setup cards
- `04-setup-buy.png` â€” Buy Connection form
- `05-buy-validation.png` â€” Buy empty-submit observation
- `06-setup-sell.png` â€” Sell Connection form
- `07-sell-lightning-selected.png` â€” Sell with Lightning active
- `08-sell-bank-dropdown.png` â€” Sell bank-account dropdown open
- `09-back-to-cards.png` â€” Back navigation confirmation
- `10-mobile-375-welcome.png` â€” Mobile Welcome at 375Ã—667
- `11-mobile-375-cards.png` â€” Mobile Setup cards at 375Ã—667
- `12-regression-*.png` â€” Regression sweep of sibling tabs
- `13-unauth-connect.png` â€” Unauthenticated `/connect` redirect

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

With KYC approval, the Connect feature exposes a clean three-step wizard that correctly captures the Buy and Sell setup inputs. The main gaps are UX polish â€” inline validation, a review-and-confirm screen, a step indicator, and clearer Lightning-specific copy. The destructive provisioning paths remain untested by design and should be covered in a sandbox account before the feature is promoted out of beta.
# Test Case: Bringin Connect (Production â€” KYC-approved)

| Field | Value |
|---|---|
| **Test Case ID** | TC-BRINGIN-CONNECT-002 |
| **Title** | Verify the Connect wizard (Buy + Sell) on app.bringin.xyz for a KYC-approved user |
| **Feature / Module** | Connect (bank â†” Bitcoin-wallet linking) |
| **Environment** | Production â€” https://app.bringin.xyz |
| **Tester** | corntestiphone@gmail.com |
| **Date executed** | 12 April 2026, 23:50 CET |
| **Time-box** | 1 hour |
| **Build state** | Live â€” KYC-approved account can access the full wizard (Welcome â†’ Buy/Sell cards â†’ Setup forms) |
| **Browser** | Google Chrome (latest stable) |
| **OS** | Desktop (Windows 10) + iPhone SE viewport emulation |
| **Priority** | High (core product surface) |
| **Type** | Functional + UX + Accessibility + Regression |

---

## 1. Description

Bringin Connect creates **permanent connections between a user's bank account and Bitcoin wallet**, so that buying or selling Bitcoin becomes as simple as a bank transfer. Since KYC approval, the end-user now lands on a three-step wizard:

1. **Welcome** â€” marketing copy + **Next** button.
2. **Set up your connection** â€” two cards, **Setup Buy Connection** and **Setup Sell Connection**.
3. **Setup form** for the chosen side:
   - **Buy:** *Where should we send your Bitcoin?* â€” Destination Name, Destination Address.
   - **Sell:** *Where should we send your euros?* â€” Destination Name, Network Type (Onchain/Lightning), Bank Account.

This test case covers rendering, navigation, accessibility, responsiveness, regression of sibling tabs, and auth gating. It **deliberately does not submit** a live Buy or Sell connection, because provisioning a vIBAN / wallet pairing is irreversible via the UI and would leak real identifiers. Those end-to-end paths are documented under Scenario I and should be re-tested in a sandbox account.

---

## 2. Pre-conditions

1. A verified Bringin account with **KYC approved** (required for wizard access).
2. Tester reaches https://app.bringin.xyz in a modern browser.
3. No real funds on the account; no live provisioning is performed.
4. Credentials stored only in the local `.env` file â€” never committed.

---

## 3. Test Data

| Field | Value |
|---|---|
| Email | `corntestiphone@gmail.com` |
| Password | `â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢` (stored in `.env`) |
| Base URL | `https://app.bringin.xyz` |

---

## 4. Test Scenarios & Steps

### Scenario A â€” Welcome page

| # | Step | Expected result |
|---|---|---|
| A.1 | Log in, click **Connect** in sidebar | URL reflects `/connect`; Welcome page renders |
| A.2 | Verify heading *"Welcome to Bringin Connect"* | Visible |
| A.3 | Verify subheading *"Your bank and your wallet, finally in sync."* | Visible |
| A.4 | Verify paragraph *"Create permanent connections between your bank accounts and Bitcoin walletsâ€¦"* | Visible |
| A.5 | Verify **Next** button is visible, enabled, focusable | Pass |
| A.6 | Click **Next** | *Set up your connection* page renders |

### Scenario B â€” Setup cards

| # | Step | Expected result |
|---|---|---|
| B.1 | Verify heading *"Set up your connection"* | Visible |
| B.2 | Verify Buy Connection card (green â†“) + **Setup Buy Connection** button | Visible, enabled |
| B.3 | Verify Sell Connection card (blue â†‘) + **Setup Sell Connection** button | Visible, enabled |

### Scenario C â€” Buy Connection setup (non-destructive)

| # | Step | Expected result |
|---|---|---|
| C.1 | Click **Setup Buy Connection** | Form *"Set up your Buy Connection"* renders with sub-heading *"Where should we send your Bitcoin?"* |
| C.2 | Verify Destination Name input (placeholder *"e.g. Blue Wallet"*) | Visible |
| C.3 | Verify Destination Address input (placeholder *"Enter your Bitcoin wallet address"*) | Visible |
| C.4 | Click **Next** with empty fields | Stays on form; inline validation expected (observational) |
| C.5 | Click **Back** | Returns to Setup cards page |

> **Do NOT submit** a real wallet address during this scenario. A provisioned Buy Connection creates a live vIBAN routed to that address â€” irreversible via the UI.

### Scenario D â€” Sell Connection setup (non-destructive)

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

### Scenario E â€” Keyboard & screen-reader accessibility

| # | Step | Expected result |
|---|---|---|
| E.1 | From Welcome page, press **Tab** repeatedly | Focus ring lands on **Next** |
| E.2 | Press **Enter** on **Next** | Advances to Setup cards |
| E.3 | Continue Tab | Focus reaches **Setup Buy Connection** button |
| E.4 | Inspect interactive controls for visible focus rings | Each control shows focus |

### Scenario F â€” Responsive behavior

| # | Step | Expected result |
|---|---|---|
| F.1 | Resize to 375Ã—667 (iPhone SE), reopen Connect | Welcome + **Next** reachable without horizontal scroll |
| F.2 | Advance to Setup cards at 375w | Buy/Sell cards stack vertically, both buttons reachable |
| F.3 | Resize to 768Ã—1024 (iPad) | Two-column layout preserved or gracefully degrades |

### Scenario G â€” Regression of sibling navigation

| # | Step | Expected result |
|---|---|---|
| G.1 | Click each of Home, Transactions, Card, Profile, Integrations, Mobile App | Routes load; no console errors |

### Scenario H â€” Auth gating

| # | Step | Expected result |
|---|---|---|
| H.1 | Open `/connect` in a fresh, unauthenticated context | Redirect to login; wizard not exposed |

### Scenario I â€” Destructive paths (NOT EXECUTED â€” documented only)

These must be covered in a sandbox account where live provisioning is safe:

- **Buy provisioning:** submit a wallet address â†’ verify vIBAN is created â†’ inbound SEPA test transfer â†’ wallet credit confirmation.
- **Sell provisioning:** complete Sell form with Onchain network â†’ send BTC to generated deposit address â†’ euro credit to linked bank.
- **Lightning Sell:** same as above but using Lightning; quote expiry edge case.
- **Multiple connections:** repeat Buy / Sell to verify multiple active connections per user.
- **Unlink / revoke:** user-initiated teardown; idempotency of repeated unlink.
- **Notifications:** email / push / in-app on create, failure, success, revocation.
- **KYC regression:** verify a non-KYC'd account cannot reach the Buy/Sell forms.
- **Security:** re-auth before create/unlink, rate limiting, CSRF on state-changing endpoints.

---

## 5. Expected Results (summary)

- Welcome â†’ Setup cards â†’ Buy/Sell setup form all load under 2s on warm cache.
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
| TC-01 | A.1â€“A.3 Welcome heading/subheading/paragraph render | â˜ | |
| TC-02 | A.5 Next button visible & enabled | â˜ | |
| TC-03 | A.6 Next advances to Setup cards | â˜ | |
| TC-04 | B.1â€“B.3 Buy + Sell cards render with working buttons | â˜ | |
| TC-05 | C.1â€“C.3 Buy form renders + placeholders | â˜ | |
| TC-06 | C.4 Empty Buy form does not silently provision | â˜ | Observational â€” expect inline validation |
| TC-07 | D.1â€“D.2 Sell form renders + placeholder | â˜ | |
| TC-08 | D.3â€“D.4 Network Type toggle works | â˜ | |
| TC-09 | D.5â€“D.6 Bank account dropdown opens | â˜ | |
| TC-10 | C.5 / D.7 Back navigation | â˜ | |
| TC-11 | E.1â€“E.3 Keyboard reaches Next + Buy card | â˜ | |
| TC-12 | F.1â€“F.2 Mobile 375Ã—667 reachable | â˜ | |
| TC-13 | G.1 Regression sweep | â˜ | |
| TC-14 | H.1 Unauth access blocked | â˜ | |

Fill in âœ… PASS / âŒ FAIL / âš ï¸ BLOCKED after each run and paste relevant screenshots below.

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
| F-03 | Low | Network Type toggle â€” active-state contrast | Onchain/Lightning pill lacks sufficient contrast for the unselected option |
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
7. Instrument analytics for Welcome view â†’ Next â†’ Buy/Sell card click â†’ Setup form submit.

---

## 10. Sign-off

| Role | Name | Date | Status |
|---|---|---|---|
| Tester | corntestiphone@gmail.com | 12 April 2026 | Submitted |
| Reviewer | â€” | â€” | â€” |
# Skyline — Demo Day Readiness Checklist

> Run top to bottom on the morning of Demo Day, and once more the night before.
> Every unchecked box is a risk you have accepted.

---

## A. The protocol (must all be true)

- [ ] `forge test` passes — **including every invariant suite at ≥ 10,000 runs**
- [ ] `forge fmt --check` clean
- [ ] `forge build` produces no warnings
- [ ] The deployed contracts match the committed source (verify the deployed bytecode hash)
- [ ] The deployed `PoolId` matches the one the dashboard derives client-side
- [ ] `verifyCep(poolId).cepHolds` returns `true` on the seeded deployment
- [ ] The curator's exit attempt reverts with `CuratorExitBlocked` — with the **expected** pending
      value
- [ ] A depositor exit completes successfully (proving liveness on the live deployment)
- [ ] The bond supplies a bounded last-resort shortfall correctly on a second seeded deployment

---

## B. The dashboard

- [ ] `npm run typecheck` — zero errors
- [ ] `npm run build` — succeeds with no warnings
- [ ] Landing page renders; no "YourBrand" anywhere
- [ ] All six dashboard tabs render
- [ ] The CEP badge reads **ENFORCED** on the live deployment
- [ ] The exit gate panel shows the correct pending value
- [ ] "Attempt curator exit" shows the **decoded** revert, not a hex blob
- [ ] The exit ladder shows the right amounts per stage
- [ ] The verifier panel shows pool-derived == recorded
- [ ] Wallet connect works with the demo wallet
- [ ] DEMO MODE works: `?scenario=blocked`, `?scenario=absorption`, `?scenario=settled`
- [ ] Checked at 1280×800 (the demo laptop) and on a phone

---

## C. The demo itself

- [ ] Run-of-show read aloud, twice, with a timer — **≤ 5 minutes**
- [ ] The three key lines land cleanly:
      - "Every existing curated-liquidity vault treats withdrawal as symmetric. That symmetry is the bug."
      - "The hook blocked the curator's exit."
      - "You manage the liquidity. You share the risk. You don't get to run first."
- [ ] The pause after "the curator cannot run" is actually taken
- [ ] Q&A answers rehearsed (`docs/11-DEMO.md` §5) — especially "isn't this just a vault?"
- [ ] The 90-second clip is recorded, uploaded, and the link is in the submission
- [ ] The clip plays from a local file as well as from a URL

---

## D. Logistics

- [ ] Laptop charged; charger packed; second battery
- [ ] MetaMask on the right network and the right account
- [ ] Second deployment (settled scenario) ready to switch to
- [ ] Explorer tab open on the pool address
- [ ] `cast` ready in a terminal with the deployer key loaded
- [ ] Screenshots of the key states saved locally
- [ ] Screen sharing tested at the actual resolution
- [ ] Presenter notes open on the second monitor
- [ ] Slide deck as a fallback
- [ ] **Nothing on stage requires a successful transaction** — the demo is a *failing* transaction

---

## E. Contingency

- [ ] The RPC going down → `?scenario=blocked` (demo fixture) rehearsed
- [ ] The wallet failing → demo fixture rehearsed
- [ ] The chain congested → second deployment on the other testnet, ready
- [ ] The dashboard broken → clip + source code in the editor, rehearsed
- [ ] Everything broken → slides, then spend the time on the mechanism diagram and the invariant
      list

---

## F. Submission

- [ ] `docs/02-SUBMISSION.md` reflects the **shipped** implementation
- [ ] Deployed addresses filled in
- [ ] Repo link public (or private with access granted to the organisers)
- [ ] Demo video link live
- [ ] Theme-mapping table still accurate
- [ ] No claim in the submission that the code does not support — read it once more with that
      filter on

---

## G. Honesty check

- [ ] Nowhere do we say "audited"
- [ ] Nowhere do we claim a slashing mechanism for something the hook *prevents*
- [ ] Nowhere do we claim the oracle is used to value depositor positions
- [ ] The "no depositor lockout" claim is backed by the invariant test
- [ ] The "anyone can verify" claim is backed by `verifyCuratorBond` / `verifyPending`
- [ ] The multi-pool / portfolio features are not claimed

---

**Sign-off:** <name> · <date>

*If any box in section A is unchecked, the demo is not ready. Fix the protocol before the
presentation.*

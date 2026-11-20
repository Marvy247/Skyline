# 09 — Frontend: the Skyline Dashboard

> The dashboard is the demo. A judge who understands it in 90 seconds understands the protocol.
>
> Implementation lives in `dashboard/`. This document is the specification; the code is the
> truth. If they disagree, the code is right — fix this document.

---

## 1. What was in the template and what it became

The starting point was a generic Next.js dashboard template (Next.js 15, React 18, Tailwind 3,
shadcn/ui, framer-motion, recharts). Skyline kept the shell and the visual language and replaced
the substance.

| Template | Skyline |
|---|---|
| `YourBrand` placeholder logo | `components/Logo.tsx` — a bond mark: a subordinate amber ring around a dominant white disc |
| Static landing copy | Skyline narrative: problem → mechanism → features → demo |
| Static "Total Revenue" dashboard with no data | Live pool state, the CEP badge, the exit gate, the claim queue, the exit ladder |
| Fake login page (`app/login/page.tsx`) — no backend, "sign-in not configured yet" | **Removed.** Skyline has no accounts; wallet connect replaces it |
| `components/dashboard-overview.tsx` — static placeholder widgets | **Removed**, replaced by `components/dashboard/*` |
| `public/snapshot/` — 11 MB static capture of an unrelated "CityVigil" city-data API | **Removed** |
| No chain access | wagmi v2 + viem v2 + TanStack Query |
| No error decoding | Custom-error decoding into plain English |

### Why the login page was deleted

It was template filler with no backend: `handleGoogleSignIn` showed "Google sign-in not
configured yet" and `handleEmailSubmit` showed "Account created! (demo)". Skyline has no user
accounts — participants connect a wallet to write, and anyone can read without connecting.
Keeping a fake login would have implied a user model the protocol does not have.

### Why `public/snapshot/` was deleted

It was a static capture of the "CityVigil API" — an unrelated city-infrastructure API (Las Vegas
exposure surfaces, tract summary, supply layers). Nothing in Skyline reads it, and 11 MB of
irrelevant JSON in `public/` would have shipped with every deploy.

---

## 2. Stack

| Concern | Choice | Why |
|---|---|---|
| Framework | Next.js 15 (App Router), React 18 | Already in the template; static export works on Vercel |
| Styling | Tailwind 3 + shadcn/ui (new-york, neutral) | Already in the template |
| Animation | framer-motion | Already in the template |
| Chain access | wagmi v2.19 + viem v2.57 | Standard; `injected` connector only |
| Data fetching | TanStack Query v5 | Standard; `useMandate` polls on an 8 s interval |
| Icons | lucide-react | Already in the template |

**TypeScript target was raised from ES5 to ES2020** — `viem` returns `bigint`, and BigInt
literals require ES2020. This also matches what Foundry/viem ecosystems assume.

### Dependencies added

```bash
npm install wagmi@^2 viem@^2 @tanstack/react-query@^5
```

**And four transitive optional peers**, required because the `wagmi/connectors` barrel statically
imports the MetaMask SDK and WalletConnect logger:

```bash
npm install @x402/evm @x402/svm @x402/core @x402/extensions
```

Two further optional modules are aliased to `false` in `next.config.js`
(`@react-native-async-storage/async-storage`, `pino-pretty`) so the production build is
warning-free.

> **If you want a smaller bundle:** replace the `injected` connector with a hand-rolled
> `createConnector` and stop importing the `wagmi/connectors` barrel. Not worth the time before
> 3 December.

---

## 3. File map

```
dashboard/
├── app/
│   ├── layout.tsx                  # branding, metadata, Providers, ThemeProvider
│   ├── page.tsx                    # Skyline landing
│   └── dashboard/page.tsx          # the dashboard (tabbed)
├── components/
│   ├── providers.tsx               # WagmiProvider + QueryClientProvider
│   ├── wallet-button.tsx           # connect / address / disconnect
│   ├── Logo.tsx                    # the bond mark
│   ├── dashboard-layout.tsx        # template shell, adapted (headerAction slot)
│   ├── dashboard/
│   │   ├── primitives.tsx          # Panel, PanelHeader, StatTile, Pill, Meter, KeyValue
│   │   ├── cep-badge.tsx           # ★ the headline invariant badge
│   │   ├── exit-gate-panel.tsx     # ★ the demo centrepiece
│   │   ├── exit-ladder.tsx         # the three-stage waterfall
│   │   ├── claims-panel.tsx        # claim queue + request/settle (also exports VaultStatsPanel)
│   │   ├── curator-bond-panel.tsx  # bond value, skin %, shortfall absorbed
│   │   ├── mandate-panel.tsx       # mandate parameters + enforcement model
│   │   └── verifier-panel.tsx      # "anyone can check" panel
│   └── landing/                    # re-written for Skyline
│       ├── Navbar.tsx  HeroSection.tsx  AboutSection.tsx
│       ├── LayersSection.tsx  FeaturesSection.tsx  DemoSection.tsx  Footer.tsx
│       └── ShaderBackground.tsx    # kept from the template
├── hooks/
│   ├── use-mandate.ts              # all reads, batched into one multicall
│   └── use-mandate-actions.ts      # all writes + custom-error decoding
├── lib/
│   ├── contracts.ts                # addresses, ABIs, salts, PoolId derivation
│   ├── demo-data.ts                # the demo fixture (worked example from the economics doc)
│   ├── format.ts                   # display helpers
│   ├── web3.ts                     # wagmi config, chains, query client
│   └── utils.ts                    # cn()
└── .env.example                    # every configurable value
```

---

## 4. The data layer

### 4.1 One hook, one state object

`useMandate()` returns `{ state, derived, isLoading, error, refetch, demo }`. `state` is a flat
object with the same shape in live mode and in demo mode, so no component branches on the source.

All reads go through **one `client.multicall`** (23 calls) plus a second multicall for the
dynamic claim list. Polling interval: 8 s.

> **Implementation note.** The multicall contract objects are written **inline** rather than via a
> helper function. A helper that widens `functionName` to `string` breaks TypeScript's inference
> of the multicall result. This is a real trap — it cost an hour once.

### 4.2 PoolId derivation

The dashboard derives the v4 `PoolId` client-side:

```ts
keccak256(encodeAbiParameters(
  [{type:'address'},{type:'address'},{type:'uint24'},{type:'int24'},{type:'address'}],
  [currency0, currency1, fee, tickSpacing, hooks],
))
```

This matches v4's `PoolIdLibrary.toId` (`keccak256(abi.encode(poolKey))`) because `PoolKey` is a
struct of static types, so `abi.encode` is the concatenation of 32-byte words.

**If the derived PoolId does not match the on-chain pool, the dashboard reads zeros.** Verify it
against the deployment output before Demo Day. A cheap sanity check: `pendingLiquidity` should be
non-zero while a claim is open.

### 4.3 The salts

```ts
export const SALTS = {
  LP:      "0x...01",
  CURATOR: "0x...02",
}
```

These **must** match `src/libraries/SkylineTypes.sol`. They are display constants only — the
dashboard never derives a position key — but they appear in the demo narrative, so keep them in
sync.

### 4.4 DEMO MODE

`NEXT_PUBLIC_DEMO_MODE=true` renders the dashboard from `lib/demo-data.ts`, which reproduces the
worked example in `docs/04-ECONOMICS.md` §5 exactly.

Three scenarios, switchable by query parameter:

| URL | Scenario |
|---|---|
| `/dashboard?scenario=blocked` | A claim is outstanding; the curator's exit is **blocked** (default) |
| `/dashboard?scenario=absorption` | The curator's bond **absorbs** a 10,000-unit shortfall |
| `/dashboard?scenario=settled` | Obligations are settled; the curator's exit is **permitted** |

**This is the Demo Day contingency.** If the public RPC is slow, the wallet misbehaves, or the
chain is having a bad day, the presenter opens `?scenario=blocked` and the dashboard still tells
the story. Rehearse the contingency, not just the happy path.

In demo mode the curator-exit action **simulates the revert** and renders the decoded
`CuratorExitBlocked` message — the same code path that renders a real revert.

---

## 5. The dashboard tabs

| Tab | Contents | Why it exists |
|---|---|---|
| **Overview** | CEP badge · exit ladder · vault stats · claim queue | The 15-second read |
| **Exit gate** | CEP badge · **exit gate panel** · exit ladder | The demo |
| **Claims** | Vault stats · claim queue | The depositor's view |
| **Curator bond** | Bond value, skin meter, absorbed shortfall, top-up | The skin in the game |
| **Mandate** | Mandate parameters, enforcement model | The authority |
| **Verification** | Independent verification + raw hook state | "Anyone can check" |

### 5.1 The CEP badge (`cep-badge.tsx`)

The headline element. Reads `verifyCep(poolId)` and renders:

- **ENFORCED** (emerald) — with the live pending obligation and whether the curator may exit
- **BREACHED** (red)

It reports the protocol's own invariant, computed by the hook. It is a *reader*, not a
re-implementation. Say that on stage.

### 5.2 The exit gate panel (`exit-gate-panel.tsx`)

The demo centrepiece. Contains:

1. The live obligation and curator liquidity
2. The **actual source code of the gate**, verbatim from `beforeRemoveLiquidity`
3. An **"Attempt curator exit"** button
4. The decoded revert, in plain English, with the error name
5. A "Why is it blocked?" explainer

The decoded revert is the single most valuable frame in the whole project. It turns "a contract
reverted" into "**the hook blocked the curator's exit: 55,556 liquidity units of depositor
obligation are still unsettled.**"

### 5.3 The exit ladder (`exit-ladder.tsx`)

A three-stage visual: depositor liquidity → curator bond → pro-rata last resort, with the amount
each stage covers and a one-line explanation of who bears the loss at that stage.

### 5.4 The verifier panel (`verifier-panel.tsx`)

Three checks, each comparing a **pool-derived** value against a **hook-recorded** value:

- Curator bond: pool state vs. recorded
- Outstanding obligation: derived from the claim set vs. recorded
- Curator Exit Parity: holds or breached

This is the answer to "isn't this just a vault?" — the dashboard shows the protocol checking
itself, and the values come from the chain, not from the vault's books.

---

## 6. Error decoding

`hooks/use-mandate-actions.ts` turns a revert into a sentence:

1. Walk the viem error chain for 4-byte revert data.
2. `decodeErrorResult` against `mandateErrorsAbi` (a decode-only ABI listing every custom error).
3. Fall back to name matching across the error tables.
4. Fall back to the raw message.

Every custom error has a hand-written explanation in `describe()`. Read them before Demo Day —
if the wording is wrong on stage, it undermines the whole argument.

**Note:** `mandateErrorsAbi` must list every error the contracts can revert with. If you add an
error in Solidity, add it here.

---

## 7. Configuration

All via environment variables — see `dashboard/.env.example`.

| Variable | Purpose |
|---|---|
| `NEXT_PUBLIC_CHAIN_ID` | 84532 (Base Sepolia) or 1301 (Unichain Sepolia) |
| `NEXT_PUBLIC_RPC_URL` | RPC endpoint |
| `NEXT_PUBLIC_HOOK_ADDRESS` | SkylineHook |
| `NEXT_PUBLIC_VAULT_ADDRESS` | SkylineVault |
| `NEXT_PUBLIC_REGISTRY_ADDRESS` | CuratorRegistry |
| `NEXT_PUBLIC_CURRENCY0/1` | Pool currencies, **lower address first** |
| `NEXT_PUBLIC_POOL_FEE`, `NEXT_PUBLIC_TICK_SPACING` | Pool parameters |
| `NEXT_PUBLIC_ASSET_DECIMALS`, `NEXT_PUBLIC_ASSET_SYMBOL` | Vault asset |
| `NEXT_PUBLIC_DEMO_MODE` | `true` / `false` / unset (auto) |

**Never hard-code an address.** Never trust a value from this file for a financial decision.

---

## 8. Acceptance criteria

- [ ] `npm run typecheck` — zero errors
- [ ] `npm run build` — succeeds with **no warnings**
- [ ] Landing page renders with no "YourBrand" anywhere
- [ ] `/dashboard` renders all six tabs
- [ ] Demo mode works with no `.env` at all
- [ ] The curator-exit attempt shows a decoded revert, not a hex blob
- [ ] The CEP badge reflects a live `verifyCep` call
- [ ] The PoolId derived client-side matches the deployed pool
- [ ] Verified on a real wallet against a real testnet deployment
- [ ] Tested at 1280×800 (the demo laptop) and on a phone

---

## 9. Known limitations — state them honestly

| Limitation | Explanation for a judge |
|---|---|
| The dashboard is a **read-mostly view**; it does not run a strategy | The strategy is a keeper/operator concern; the dashboard's job is to make the protocol's state legible |
| Live mode needs **configured addresses** | Until deployment, the demo fixture runs the same components |
| **No chart of historical performance** | Deliberate. A strategy's performance chart is the curator's marketing; Skyline's job is ordering, not performance |
| **No multi-pool view** | Single-pool vaults are the MVP scope (`docs/01-PROJECT-BRIEF.md` §6) |
| Errors are decoded from a **static ABI list** | A new Solidity error must be added to `mandateErrorsAbi` |

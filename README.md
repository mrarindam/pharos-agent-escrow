<p align="center">
  <img src="logo.png" alt="Pharos Agent Escrow logo" width="220">
</p>

<h1 align="center">Pharos Agent Escrow</h1>

<p align="center">
  Trustless agent-to-agent <b>escrowed payments</b> on Pharos — the missing payment primitive for an
  autonomous agent economy, packaged as a reusable <b>Agent Skill</b> that any AI agent
  (Claude Code, Codex, Antigravity, Cursor) can install and call in plain language.
</p>

|                    |                                                                                                                                   |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| **Live testnet hub** | [`0x10B1A5680F95b81c9cC8E87a9780f7ceE32f36fB`](https://atlantic.pharosscan.xyz/address/0x10B1A5680F95b81c9cC8E87a9780f7ceE32f36fB) |
| **Source verified**  | on Pharosscan (Blockscout)                                                                                                        |
| **Tests**            | 22 / 22 passing (`forge test`)                                                                                                    |
| **Token**            | native **PHRS** (Atlantic testnet)                                                                                                 |
| **Standard**         | open `SKILL.md` Agent-Skill format — installable with `npx skills add`                                                            |
| **Engine**           | runs `cast` / `forge` (Foundry) under the hood                                                                                     |

---

## What it does

A **client** locks PHRS for a chosen **worker** against a delivery deadline. The worker delivers,
the client releases payment, and the smart contract guarantees neither side can cheat. One
`AgentEscrow` **hub** serves the whole ecosystem (many jobs, each keyed by `jobId`).

- **Create & fund** an escrow job that hires a worker for an agreed amount of PHRS (`createJob`).
- **Hold funds in the contract** — not in either party's wallet — until the job is settled.
- **Submit work** by recording an on-chain content hash of the deliverable (`submitWork`).
- **Approve & release** payment to the worker; irreversible once approved (`approve`).
- **Refund** the client automatically if the worker misses the deadline (`refund`).
- **Self-claim** for the worker if the client disappears after delivery, once a review window
  elapses (`claim`) — so a client can't take the work and never pay.
- **Query** a job's full status, state, time-to-deadline, and auto-release countdown (`getJob`,
  `stateOf`, `timeToDeadline`, `timeToAutoRelease`, `jobCount`) — no key needed.
- **Read history** of every job created / paid / refunded via on-chain events (`cast logs`).
- **Deploy your own hub** on Pharos in one command, or reuse the verified shared hub.

It is **two-sided**: the same skill serves both the hiring agent (client) and the working agent
(worker). In an agent economy one agent plays both roles at different times.

### State machine

```
   createJob              submitWork                 approve / claim
  ───────────►  Funded  ───────────►  Delivered  ───────────────────►  Released
                  │
       deadline   │ refund (worker never delivered)
       passed     ▼
              Refunded
```

---

## Installation

### Option A — one command (recommended)

The skill follows the open `SKILL.md` standard, so the [Vercel `skills` CLI](https://github.com/vercel-labs/skills)
installs it into whatever agent you have (Claude Code, Codex, Antigravity, Cursor).

It auto-detects your installed agents and copies the files to the right place:

```bash
npx skills add https://github.com/mrarindam/pharos-agent-escrow
```

### Option B — manual install (copy the folder)

A skill is just a folder: `SKILL.md` + `references/` + `assets/`. Copy it into your agent's skills
directory:

| Agent           | Global skills directory                                 | Invoke with                                       |
| --------------- | ------------------------------------------------------- | ------------------------------------------------- |
| **Claude Code** | `~/.claude/skills/pharos-agent-escrow/`                 | auto, or `/pharos-agent-escrow`                   |
| **Codex CLI**   | `~/.codex/skills/pharos-agent-escrow/`                  | auto, or `$pharos-agent-escrow` (restart session) |
| **Antigravity** | `~/.gemini/antigravity-cli/skills/pharos-agent-escrow/` | auto, or mention by name                          |

```bash
# example for Claude Code
git clone https://github.com/mrarindam/pharos-agent-escrow
mkdir -p ~/.claude/skills/pharos-agent-escrow
cp -r pharos-agent-escrow/SKILL.md pharos-agent-escrow/references pharos-agent-escrow/assets \
      ~/.claude/skills/pharos-agent-escrow/
```

### Prerequisites

The skill drives Foundry, so you need it once (the skill will also install it for you if missing):

```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup    # installs cast + forge
```

For **write** operations (create / approve / refund / claim / deploy) export a funded **testnet**
key. Read-only queries need nothing.

```bash
export PRIVATE_KEY=0xyour_testnet_private_key
```

---

## Usage

### Talk to it in plain language (after install)

Just describe what you want; the agent maps it to the right command via `references/escrow.md`:

```
Create an escrow job hiring 0x5d7Aaf…4494 for 0.01 PHRS with a 1 hour deadline on Pharos.
Submit work for job 4, deliverable ipfs://bafy…
Approve and release payment for job 4.
What's the status and countdown of job 4?
Refund my escrow for job 4 — the worker missed the deadline.
```

### Or run the underlying commands directly

```bash
RPC=https://atlantic.dplabs-internal.com
HUB=0x10B1A5680F95b81c9cC8E87a9780f7ceE32f36fB

# create & fund a job (client signs, locks 0.01 PHRS, 1h deadline, 1d review window)
DEADLINE=$(($(date +%s)+3600))
cast send $HUB "createJob(address,uint64,uint64)" 0xWORKER $DEADLINE 86400 \
  --value 0.01ether --private-key $PRIVATE_KEY --rpc-url $RPC

# check status — no key required
cast call $HUB "getJob(uint256)(address,address,uint256,uint64,uint64,uint64,uint8,bytes32)" 4 --rpc-url $RPC

# release payment to the worker (client signs)
cast send $HUB "approve(uint256)" 4 --private-key $PRIVATE_KEY --rpc-url $RPC
```

### Capability reference

| Capability                     | Command                                                            | Who    | Key? |
| ------------------------------ | ------------------------------------------------------------------ | ------ | ---- |
| Deploy a hub                   | `forge script DeployAgentEscrow`                                   | anyone | yes  |
| Create & fund a job            | `createJob(worker, deadline, reviewWindow)` `--value`              | client | yes  |
| Submit work                    | `submitWork(jobId, deliverableHash)`                               | worker | yes  |
| Release payment                | `approve(jobId)`                                                   | client | yes  |
| Refund after missed deadline   | `refund(jobId)`                                                    | client | yes  |
| Self-claim after review window | `claim(jobId)`                                                     | worker | yes  |
| Read job status / countdown    | `getJob` / `stateOf` / `timeToDeadline` / `timeToAutoRelease`      | anyone | no   |
| Read history                   | `cast logs` (JobCreated / WorkSubmitted / Released / Refunded)     | anyone | no   |

---

## Example — a real on-chain run

Live `createJob → submitWork → approve` on Atlantic testnet (full tx links in
[`examples/agent-to-agent-demo.md`](examples/agent-to-agent-demo.md)):

```
STEP 1  createJob   →  state 1 (Funded)    hub holds 0.001 PHRS, worker wallet UNCHANGED
STEP 2  submitWork  →  state 2 (Delivered) worker records deliverable hash
STEP 3  approve     →  state 3 (Released)  worker wallet +0.001 PHRS, hub balance 0
```

And the worker-protection path (client never approves):

```
submitWork  →  Delivered, review window starts
timeToAutoRelease: 35s → 24s …            (live countdown)
claim (too early)  →  reverted: "Review window open"
…window elapses…   →  timeToAutoRelease: 0
claim              →  state 3 (Released)  worker self-claims the payment
```

---

## Supported networks

| Network                        | name               | chainId  | native token | RPC                                    |
| ------------------------------ | ------------------ | -------- | ------------ | -------------------------------------- |
| **Atlantic testnet** (default) | `atlantic-testnet` | `688689` | **PHRS**     | `https://atlantic.dplabs-internal.com` |
| **Pharos mainnet**             | `mainnet`          | `1672`   | **PROS**     | `https://rpc.pharos.xyz`               |

Network config lives in [`assets/networks.json`](assets/networks.json). Testnet is used unless you
say `mainnet`; mainnet writes require an explicit re-confirmation.

## Dependencies

- **Foundry** (`cast` + `forge`) — the only hard dependency; auto-installed by the skill if missing.
- **A wallet private key** — only for write operations, supplied via `$PRIVATE_KEY`. Read/query
  operations need nothing.
- No npm packages, no SDK, no wallet browser extension.

---

## Security & Safety

This is a **payment** skill, so it is built to be auditable and to handle keys responsibly. It is
designed to pass the CertiK *Skill Scanner* (an official judging standard). Full self-audit in
[`SECURITY.md`](SECURITY.md).

- **Read vs write** — querying status/history needs **no key**. Only `create / approve / refund / claim / deploy` need a key.
- **Keys never leave your machine** — the key is read from `$PRIVATE_KEY`, passed straight to
  `cast`/`forge` to sign locally, and is **never printed, logged, committed, or sent to any server**.
  No wallet connection, no seed phrases, no browser automation.
- **The only network endpoints** are the Pharos RPC and the Pharos explorer's verification API
  (both declared in `assets/networks.json`). No telemetry, no third-party calls.
- **Contract safety** — Checks-Effects-Interactions + a reentrancy guard on every payout; no
  `owner`/admin, no `selfdestruct`, no `delegatecall`, no upgradeability. Funds can only ever go
  **back to the client** (refund) or **to the designated worker** (release/claim) — there is no path
  to any third party, and no admin withdrawal.
- **Network confirmation** — the agent always states the target network before a write, and warns
  prominently before any mainnet operation.

> Note: use a **dedicated testnet wallet** with only test funds. As with any agent skill, review the
> `SKILL.md` before installing — skills are instructions an agent will follow.

---

## Composability — what Phase 2 agents can build on this

Because the hub is a shared, deployed primitive, agents just point at its address:

- **Agent marketplace** — a broker agent posts jobs, escrows payment, pays on delivery.
- **Freelance / bounty agent** — humans or agents claim bounties; payout is trustless.
- **Pay-per-task data/compute agent** — pairs with Pharos `x402` (instant micro-payments) for the
  small calls, and uses this escrow for the larger, delivery-based jobs.
- **Milestone manager** — one client funds several workers across parallel jobs in a single hub.

## Repository layout

```
pharos-agent-escrow/
├── SKILL.md                     # agent entry point + Capability Index
├── references/escrow.md         # per-operation command specs (templates, params, errors)
├── assets/
│   ├── networks.json            # Pharos RPC / chainId / explorer
│   └── escrow/AgentEscrow.sol   # the skill's contract (source of truth)
├── src/escrow/AgentEscrow.sol   # build/test/deploy copy
├── script/DeployAgentEscrow.s.sol
├── test/AgentEscrow.t.sol       # 22 tests
├── examples/agent-to-agent-demo.md
├── SECURITY.md
└── foundry.toml
```

## Live deployment

- **Hub (verified):** [`0x10B1A5680F95b81c9cC8E87a9780f7ceE32f36fB`](https://atlantic.pharosscan.xyz/address/0x10B1A5680F95b81c9cC8E87a9780f7ceE32f36fB)
- **Network:** Pharos Atlantic testnet (chainId `688689`, native `PHRS`)
- Reuse it directly, or deploy your own with `forge script script/DeployAgentEscrow.s.sol`.

## License

MIT.

# 🤝 Agent Escrow — a Pharos Skill

> Trustless, agent-to-agent **escrowed payments** on Pharos. The missing payment primitive for an
> autonomous agent economy — packaged as a reusable Skill that any AI agent can call.

**Pharos "Skill-to-Agent Dual Cascade" Hackathon · Phase 1 (Skill Hackathon)**

| | |
|---|---|
| 🟢 **Live on Atlantic testnet** | [`0x10B1A5680F95b81c9cC8E87a9780f7ceE32f36fB`](https://atlantic.pharosscan.xyz/address/0x10B1A5680F95b81c9cC8E87a9780f7ceE32f36fB) |
| ✅ **Source verified** | on Pharosscan (Blockscout) |
| 🧪 **Tests** | 22 / 22 passing (`forge test`) |
| 🔐 **Token** | native **PHRS** |
| 📦 **Format** | official Pharos Skill Engine layout (`SKILL.md` + `references/` + `assets/`) |

---

## The problem

Pharos is built to power an **AI agent economy** — agents that transact, hire each other, and move
value autonomously. But agent-to-agent commerce has a trust gap: if agent A pays agent B upfront, B
can vanish; if B works first, A can refuse to pay. A simple transfer can't solve this.

**Escrow is the foundational primitive that closes that gap** — and it's exactly what a Phase 2
"agent marketplace" needs underneath it.

## The solution

`AgentEscrow` is a single on-chain **hub** that holds a client's PHRS until a job is done:

1. **Client** locks PHRS for a chosen **worker**, with a delivery **deadline**.
2. **Worker** delivers off-chain work and records a **content hash** on-chain (`submitWork`).
3. **Client** approves and the funds are **released** to the worker (`approve`).
4. Safety valves: if the worker misses the deadline the client can **refund**; if the client ghosts
   after delivery, the worker can **claim** once a review window passes. Neither side can trap the other.

It ships as a **Skill** — a folder (`SKILL.md` + `references/escrow.md` + `assets/`) that teaches an
AI agent (e.g. Claude Code) to deploy and operate the contract through Foundry (`cast`/`forge`),
driven entirely by natural language.

## What is a "Pharos Skill"?

Not an SDK or a framework — it's an **Agent Skill package** in the official
[`pharos-skill-engine`](https://github.com/PharosNetwork/pharos-skill-engine) format. The agent reads
`SKILL.md`, matches the user's intent in the **Capability Index**, opens the linked section of
`references/escrow.md`, and runs the documented `cast`/`forge` command. This skill follows that exact
standard, so it drops straight into the engine alongside the built-in capabilities.

## Architecture

```
        Natural language ("hire 0xBob for 0.1 PHRS, deadline 1h")
                              │
                              ▼
   ┌───────────────────────────────────────────────┐
   │  SKILL.md  →  Capability Index (intent → ref)  │
   └───────────────────────────────────────────────┘
                              │
                              ▼
   ┌───────────────────────────────────────────────┐
   │  references/escrow.md                          │
   │  command template · params · output · errors   │
   └───────────────────────────────────────────────┘
                              │  cast / forge
                              ▼
   ┌───────────────────────────────────────────────┐
   │  AgentEscrow hub  @ Pharos Atlantic testnet    │
   │  createJob · submitWork · approve · refund ·    │
   │  claim · getJob · events                        │
   └───────────────────────────────────────────────┘
```

### Escrow state machine

```
   createJob              submitWork                 approve
  ───────────►  Funded  ───────────►  Delivered  ───────────►  Released
                  │                       │
       deadline   │ refund          claim │ (after review window)
       passed,    ▼                       ▼
       no deliver Refunded            Released
```

## Contract API (`assets/escrow/AgentEscrow.sol`)

| Function | Who | Effect |
|---|---|---|
| `createJob(worker, deadline, reviewWindow) payable → jobId` | client | Lock PHRS, open a job |
| `submitWork(jobId, deliverableHash)` | worker | Record delivery, start review window |
| `approve(jobId)` | client | Release funds to worker (irreversible) |
| `refund(jobId)` | client | Reclaim funds after a missed deadline |
| `claim(jobId)` | worker | Self-claim after the review window if client ghosts |
| `getJob / stateOf / timeToDeadline / timeToAutoRelease / jobCount` | anyone | Read-only views |

Events (all indexed for `cast logs`): `JobCreated`, `WorkSubmitted`, `Released`, `Refunded`.

## Quickstart

### Use the skill with Claude Code
```bash
# 1. Install Foundry (the skill needs cast/forge)
curl -L https://foundry.paradigm.xyz | bash && foundryup

# 2. Fund a throwaway testnet wallet and export its key
cp .env.example .env        # then edit .env and set PRIVATE_KEY
export PRIVATE_KEY=0x...

# 3. Point Claude Code at this skill folder and just ask:
#   "Deploy the AgentEscrow hub on Pharos"
#   "Create an escrow job hiring 0xBob for 0.05 PHRS with a 2 hour deadline"
#   "Submit work for job 3, deliverable ipfs://bafy..."
#   "Approve and release payment for job 3"
#   "What's the status of job 3?"
```
The agent resolves each request to the correct `cast`/`forge` call via `references/escrow.md`.

### Build, test, deploy directly
```bash
forge install foundry-rs/forge-std
forge build
forge test -vv                                   # 22 passing

forge script script/DeployAgentEscrow.s.sol:DeployAgentEscrow \
  --rpc-url https://atlantic.dplabs-internal.com \
  --private-key $PRIVATE_KEY --broadcast
```

## Live deployment & demo

- **Hub (verified):** [`0x10B1A5680F95b81c9cC8E87a9780f7ceE32f36fB`](https://atlantic.pharosscan.xyz/address/0x10B1A5680F95b81c9cC8E87a9780f7ceE32f36fB)
- **Network:** Pharos Atlantic testnet (chainId `688689`, native `PHRS`)
- **Full on-chain run** (createJob → submitWork → approve, with tx links): see
  [`examples/agent-to-agent-demo.md`](examples/agent-to-agent-demo.md)

## Security

Built to pass the CertiK *Skill Scanner* (an official judging standard). Highlights: Checks-Effects-
Interactions + reentrancy guard, no owner/admin/`selfdestruct`/`delegatecall`, funds can only return
to the client or go to the designated worker, private keys never printed or committed. Full self-audit
in [`SECURITY.md`](SECURITY.md).

## Composability — what Phase 2 agents can build on this

Because the hub is a shared, deployed primitive, agents just point at its address:

- **Agent marketplace** — a broker agent posts jobs, escrows payment, and pays on delivery.
- **Freelance/bounty agent** — humans or agents claim bounties; payout is trustless.
- **Pay-per-task data/compute agent** — pairs naturally with Pharos `x402` for metered work.
- **Milestone manager** — one client funds several workers across parallel jobs in one hub.

## Repository layout

```
agent-escrow-skill/
├── SKILL.md                     # agent entry point + Capability Index
├── references/escrow.md         # per-operation command specs
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

## License

MIT.

---

*Built for the Pharos Skill-to-Agent Dual Cascade Hackathon. Follows the official
[pharos-skill-engine](https://github.com/PharosNetwork/pharos-skill-engine) skill standard.*

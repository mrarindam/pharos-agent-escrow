# Security Notes & Self-Audit

Security is an **official judging standard** for this hackathon (the CertiK *Skill Scanner*). This
document maps the skill against the scanner's risk categories and explains the smart-contract design
choices. The skill is intentionally minimal and "boring" so it is easy to audit.

## 1. Skill-package safety (CertiK Skill Scanner categories)

| Risk category | Status | Notes |
|---|---|---|
| **Malicious behavior** | ✅ None | The skill only instructs the agent to run `cast`/`forge` against Pharos. No hidden side effects, no obfuscation. |
| **Data leakage** | ✅ None | No telemetry, no analytics, nothing is sent anywhere. The only network endpoints are the Pharos RPC and the Pharos block-explorer verification API, both declared in `assets/networks.json`. |
| **Unauthorized network access** | ✅ None | No `curl`/`wget`/HTTP calls to arbitrary hosts. The Foundry install step (`foundry.paradigm.xyz`) is the standard, documented Foundry installer and is explicitly user-visible. |
| **Shell execution** | ✅ Constrained | The skill drives only `cast`, `forge`, and read-only helpers (`jq`, `date`). It never asks the agent to run arbitrary or remote scripts. |
| **File-system abuse** | ✅ Constrained | Reads `assets/networks.json` and the contract source; writes only standard Foundry artifacts (`script/`, `broadcast/`, `out/`) inside the user's project. No access outside the project. |

## 2. Private-key handling

- Keys are **never** printed, logged, echoed, or committed. The skill's Write Operation Pre-checks
  test only for *presence* (`[ -n "$PRIVATE_KEY" ]`) without revealing the value.
- Keys are passed explicitly as `--private-key $PRIVATE_KEY` (Foundry does not auto-read env vars).
- `.env` is git-ignored (`.gitignore`); `.env.example` documents the throwaway-testnet-key practice.
- `forge`/`cast` write a `cache/` copy of broadcast data that can contain sensitive values — `cache/`
  and `broadcast/` are git-ignored.

## 3. Smart-contract security — `AgentEscrow.sol`

### Threat model
A client locks PHRS for a worker. Neither party — nor any third party — should be able to take funds
they are not entitled to, and funds must never become permanently stuck while a legitimate path exists.

### Controls
- **Checks-Effects-Interactions**: every payout (`approve`, `refund`, `claim`) sets the terminal
  state **before** transferring value, so a re-entrant call hits an already-closed job.
- **Reentrancy guard**: a minimal `nonReentrant` mutex wraps every value-moving function. Proven by
  `test_ReentrantWorkerCannotDrain` — a malicious worker that re-enters on receive cannot drain the
  hub; the nested call reverts and funds stay safe.
- **Fund-flow invariant**: money can only ever leave a job to (a) the original `client` via `refund`,
  or (b) the designated `worker` via `approve`/`claim`. There is **no** function that sends to an
  arbitrary address, and no admin withdrawal.
- **Strict access control**: `approve`/`refund` are client-only; `submitWork`/`claim` are worker-only.
- **Liveness for both sides**: the client can `refund` after the deadline if the worker never
  delivered; the worker can `claim` after the review window if the client ghosts. Neither side can
  trap the other's funds indefinitely.
- **No dangerous primitives**: no `owner`/admin, no `selfdestruct`, no `delegatecall`, no `tx.origin`,
  no upgradeability, no external contract calls except the two native-value payouts.
- **Input validation** on `createJob`: rejects zero value, zero/`self` worker, past deadline, and a
  zero review window — each with an explicit revert string that matches the reference error tables.
- **Pinned compiler**: `pragma solidity ^0.8.20` (built-in overflow checks) with a fixed `solc` and
  `bytecode_hash = "none"` for reproducible verification.

### Known, accepted lint note
`forge build` emits `block-timestamp` warnings on the deadline/review comparisons. This is inherent
to any time-locked contract. The accepted risk is bounded: a validator can nudge `block.timestamp`
by at most a few seconds, which is irrelevant to deadlines measured in hours/days. (The official
Pharos "Piggy Bank" example carries the same warning.)

## 4. Test coverage

`test/AgentEscrow.t.sol` — **22 tests, all passing** — covers the happy path, both timeout paths,
all access-control reverts, every input-validation revert, double-spend protection, the reentrancy
attack, and the view functions. Run with `forge test -vv`.

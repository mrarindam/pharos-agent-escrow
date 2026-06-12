---
name: pharos-agent-escrow
description: >
  Trustless agent-to-agent ESCROW payments on the Pharos blockchain. Invoke whenever the user
  wants to escrow, hire, or pay another agent/worker on Pharos with funds held until work is done:
  "create an escrow", "hire an agent", "lock PHRS for a worker", "pay on delivery", "escrow a job",
  "release payment", "approve and pay the worker", "refund my escrow", "claim my escrow payment",
  "milestone payment", "agent-to-agent payment", or checking an escrow job's status/history. Deploys
  and drives the AgentEscrow hub contract via Foundry (cast/forge). Targets Pharos Atlantic testnet
  (PHRS) by default. Also reads RPC endpoints, chain IDs, and explorer URLs needed to run the
  commands. Use this skill for any Pharos escrow / conditional-payment task; do not guess network config.
version: 1.0.0
requires:
  anyBins:
  - cast
  - forge
---

# Pharos Agent Escrow Skill

Trustless, native-PHRS escrow for **agent-to-agent service payments** on Pharos. A *client* locks
PHRS for a chosen *worker* against a delivery deadline; the worker delivers (recording a content
hash on-chain) and the client releases payment. If the worker misses the deadline the client can
refund; if the client disappears after delivery, the worker can self-claim once a review window
elapses. One `AgentEscrow` hub contract serves the whole ecosystem (many jobs, keyed by `jobId`).

This skill teaches the agent to deploy and operate that hub through Foundry (`cast` / `forge`).

## Output Language

While this skill is active, **always respond to the user in English**, regardless of the language
the request is written in. This is an international developer tool; English keeps job details,
addresses, states, and error messages unambiguous for every user and reviewer.

## Prerequisites

1. **Install Foundry** (MANDATORY — MUST be done before ANY other action):
   - The Agent MUST first run `which cast` to check if Foundry is installed.
   - If `cast` is NOT found, install it. **Do NOT fall back to curl/JSON-RPC workarounds. Do NOT
     proceed with any other task until Foundry is installed.**
     ```bash
     curl -L https://foundry.paradigm.xyz | bash
     ```
     Then run:
     ```bash
     source ~/.bashrc 2>/dev/null; foundryup
     ```
     Then verify:
     ```bash
     cast --version && forge --version
     ```
   - If installation fails, inform the user and STOP. Do not attempt alternative approaches.
2. **Configure Private Key**: Write operations (create / approve / refund / claim, and deploying
   the hub) require a private key, provided via:
   - Command argument: `--private-key <your_private_key>`, or
   - Environment variable: `$PRIVATE_KEY` (recommended), referenced explicitly as `--private-key $PRIVATE_KEY`.

## Network Configuration

Network information is stored in `assets/networks.json` (Atlantic testnet + mainnet).

- **Default Network**: Atlantic testnet (`atlantic-testnet`). Used when the user does not specify a network.
- **Switching Networks**: When the user says `mainnet`, read that entry's `rpcUrl` from `assets/networks.json`.
- **Usage**: Read `assets/networks.json` and fill the target network's `rpcUrl` into each command's
  `--rpc-url`. Contract verification also needs `chainId` and `explorerApiUrl`.

```bash
# Example: read network configuration
RPC_URL=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' assets/networks.json)
```

| Network | chainId | rpcUrl | explorer |
|---------|---------|--------|----------|
| atlantic-testnet (default) | `688689` | `https://atlantic.dplabs-internal.com` | `https://atlantic.pharosscan.xyz/` |
| mainnet | `1672` | `https://rpc.pharos.xyz` | `https://www.pharosscan.xyz/` |

### Deployed reference hub (Atlantic testnet)

A verified `AgentEscrow` hub is already live. Agents may reuse it as `<hub>` instead of deploying a
new one (deploy a fresh hub only if the user explicitly wants their own):

```
AgentEscrow hub = 0x10B1A5680F95b81c9cC8E87a9780f7ceE32f36fB   (chainId 688689, verified)
```

## Capability Index

Load `references/escrow.md` (the section linked in each row) for full command templates.

| User Need | Capability | Detailed Instructions |
|-----------|------------|----------------------|
| Deploy the escrow hub / set up escrow / "deploy AgentEscrow" | `forge script` + built-in AgentEscrow template | → `references/escrow.md#1-deploy-the-agentescrow-hub` |
| Create an escrow job / hire an agent / lock PHRS for a worker / pay on delivery | `cast send createJob() --value` | → `references/escrow.md#2-create-an-escrow-job` |
| Submit work / deliver result / mark a job delivered | `cast send submitWork()` | → `references/escrow.md#3-submit-work-worker` |
| Approve and release payment / pay the worker / accept delivery | `cast send approve()` | → `references/escrow.md#4-approve--release-payment-client` |
| Refund an escrow / reclaim funds / worker missed the deadline | `cast send refund()` | → `references/escrow.md#5-refund-an-expired-job-client` |
| Claim payment / client ghosted / auto-release after review | `cast send claim()` | → `references/escrow.md#6-claim-after-review-window-worker` |
| Check escrow job status / time left / who is the worker | `cast call getJob()` / `timeToDeadline()` / `timeToAutoRelease()` | → `references/escrow.md#7-query-job-status` |
| Show escrow history / list events / which jobs were paid | `cast logs` | → `references/escrow.md#8-query-events-job-history` |

## General Error Handling

Before executing commands, perform the Write Operation Pre-checks. When commands fail, translate
`stderr` into a user-friendly message.

| Error Scenario | CLI Error Signature | Handling |
|---------------|--------------------|---------|
| Caller is not the client | `execution reverted: Not client` | Only the job's client can approve/refund; confirm the right wallet |
| Caller is not the worker | `execution reverted: Not worker` | Only the job's worker can submit/claim |
| Refund attempted too early | `execution reverted: Deadline not reached` | Refund is only possible after the deadline; show `timeToDeadline()` |
| Claim attempted too early | `execution reverted: Review window open` | Worker can only claim after the review window; show `timeToAutoRelease()` |
| Wrong job state | `execution reverted: Not active` / `Not funded` / `Not delivered` / `Not refundable` | Check the job's state via `stateOf()` first |
| Zero / invalid creation params | `execution reverted: No PHRS sent` / `Bad worker` / `Worker is client` / `Deadline in past` / `No review window` | Fix the offending `createJob` argument |
| Private key not configured | Command missing `--private-key` | Prompt user to set `$PRIVATE_KEY` |
| Insufficient balance | `insufficient funds` | Prompt insufficient balance; check via `cast balance` |
| Missing network config | `assets/networks.json` unreadable | Config file missing or malformed |

## Security Reminders

- **Private Key Protection**: Never expose private keys in logs, chat history, or version control.
  Store the private key in `$PRIVATE_KEY` and reference it via `--private-key $PRIVATE_KEY`.
  `forge` / `cast` do not auto-read environment variables — pass them explicitly.
- **Network Confirmation**: Before any write operation, clearly tell the user the target network
  (testnet or mainnet). Mainnet operations require a prominent warning and re-confirmation.
- **Escrow safety**: Releasing funds (`approve`) is irreversible. Before approving, confirm the
  deliverable hash with the user. Before refunding, confirm the worker truly missed the deadline.

## Write Operation Pre-checks (Required for All Write Operations)

For every operation needing a private key (create / approve / refund / claim / deploy), complete
these checks before executing:

### 1. Private Key Check
```bash
# Check the variable exists WITHOUT printing the key
[ -n "$PRIVATE_KEY" ] && echo "PRIVATE_KEY is set" || echo "PRIVATE_KEY is not set"
```
- If **not set**: prompt `export PRIVATE_KEY=<your_private_key>` and do not proceed.
- If **set**: continue.

### 2. Derive Public Address and Confirm with User
```bash
cast wallet address --private-key $PRIVATE_KEY
```

### 3. Network Confirmation (Must Clearly Inform User)
Read the target network from `assets/networks.json` and show name + type. Default is
`atlantic-testnet`; for `mainnet` show a prominent warning and require re-confirmation. Example:
```
Detected private key address: 0x1234...abcd
Target network: Atlantic Testnet (atlantic-testnet)
Proceed with this account on this network?
```

### 4. Automatic Balance Check
After confirming account + network, query balance and ensure it covers the value + gas:
```bash
cast balance <address> --rpc-url <rpc> --ether
```
If insufficient, inform the user directly and do not execute the operation.

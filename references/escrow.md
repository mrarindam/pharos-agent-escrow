# Agent Escrow — Operation Instructions

This file contains detailed instructions for every operation of the **AgentEscrow** hub on the
Pharos chain: deploy the hub, create an escrow job, submit work, approve & release, refund an
expired job, claim after the review window, query state, and query events.

> **Network Configuration**: The `<rpc>` in all commands is read from the target network's
> `rpcUrl` in `assets/networks.json` (defaults to Atlantic testnet
> `https://atlantic.dplabs-internal.com`). **`--rpc-url` MUST be passed explicitly**, otherwise
> `forge` / `cast` default to `localhost:8545` and fail to connect.
>
> **Private Key Configuration**: All write operations must pass the private key explicitly via
> `--private-key $PRIVATE_KEY`. `forge` / `cast` do not auto-read environment variables.
>
> **`<hub>`** below is the deployed `AgentEscrow` contract address (see section 1).

The contract lives at `assets/escrow/AgentEscrow.sol`. State machine:
`None(0) → Funded(1) → Delivered(2) → Released(3) | Refunded(4)`.

> **Already deployed:** a verified hub exists at
> `0x10B1A5680F95b81c9cC8E87a9780f7ceE32f36fB` on Atlantic testnet (chainId `688689`). Reuse it as
> `<hub>` unless the user wants their own deployment (section 1).

---

## 1. Deploy the AgentEscrow Hub

### Overview
Deploy the `AgentEscrow` hub once; it then serves unlimited jobs keyed by `jobId`. The constructor
takes **no arguments**. Copy `assets/escrow/AgentEscrow.sol` into the user's project (`src/escrow/`),
generate a deploy script, and run it.

### Command Template
```bash
forge script script/DeployAgentEscrow.s.sol:DeployAgentEscrow \
  --rpc-url <rpc> \
  --private-key $PRIVATE_KEY \
  --broadcast
```
The deploy script (generate it in the user's `script/` directory if absent):
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/escrow/AgentEscrow.sol";

contract DeployAgentEscrow is Script {
    function run() external {
        vm.startBroadcast();
        AgentEscrow escrow = new AgentEscrow();
        console.log("AgentEscrow hub:", address(escrow));
        console.log("Deployer:", msg.sender);
        vm.stopBroadcast();
    }
}
```

### Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `<rpc>` | string | Yes | RPC endpoint, read from `assets/networks.json` |
| `$PRIVATE_KEY` | string | Yes | Deployer private key |

### Output Parsing
| Field | Description |
|-------|-------------|
| `AgentEscrow hub:` | The deployed hub address — save this; every later command uses it as `<hub>` |
| `Deployer:` | The deploying account |

### Error Handling
| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| Command missing `--private-key` | Private key not provided | Pass `--private-key $PRIVATE_KEY` |
| `compiler error` | Compilation failed | Confirm `AgentEscrow.sol` is in `src/escrow/` and solc ≥ 0.8.20 |
| `insufficient funds` | Not enough PHRS for gas | Fund the deployer from the faucet |
| `connection refused` | Missing/unreachable `--rpc-url` | Pass `--rpc-url <rpc>` explicitly |

> **Agent Guidelines**:
> 1. Complete "Write Operation Pre-checks" (see SKILL.md).
> 2. Copy `assets/escrow/AgentEscrow.sol` → `src/escrow/AgentEscrow.sol` in the user's project.
> 3. Ensure `forge-std` is installed (`forge install foundry-rs/forge-std`).
> 4. Generate `script/DeployAgentEscrow.s.sol` if not present.
> 5. Run the command; extract the hub address; show `<explorerUrl>/address/<hub>`.
> 6. Offer to verify the source (no constructor args). **Wait ~10s after deploy** before
>    verifying so the explorer indexer catches up:
>    ```bash
>    forge verify-contract <hub> src/escrow/AgentEscrow.sol:AgentEscrow \
>      --chain-id 688689 \
>      --verifier-url https://api.socialscan.io/pharos-atlantic-testnet/v1/explorer/command_api/contract \
>      --verifier blockscout
>    ```

---

## 2. Create an Escrow Job

### Overview
The client locks PHRS for `worker` against a `deadline`, with a `reviewWindow` (seconds) the client
has to review after delivery. Returns a new `jobId`.

### Command Template
```bash
cast send <hub> "createJob(address,uint64,uint64)" <worker> <deadline> <reviewWindow> \
  --value <amount>ether \
  --private-key $PRIVATE_KEY \
  --rpc-url <rpc>
```
Compute an absolute `deadline` (unix seconds) from a human duration, e.g. 1 hour from now:
```bash
DEADLINE=$(($(date +%s) + 3600))      # +3600s = 1 hour;  86400 = 1 day
REVIEW=86400                           # worker can self-claim 1 day after delivery if client ghosts
```

### Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `<hub>` | address | Yes | Deployed AgentEscrow address |
| `<worker>` | address | Yes | Who performs the work and gets paid (must differ from caller) |
| `<deadline>` | uint64 | Yes | Absolute unix timestamp; must be in the future |
| `<reviewWindow>` | uint64 | Yes | Seconds the client has to review after delivery; must be > 0 |
| `--value <amount>ether` | — | Yes | PHRS to escrow (e.g. `--value 0.1ether`) |

### Output Parsing
`cast send` returns the receipt. The `jobId` is in the `JobCreated` event. Two ways to obtain it:
- **Simplest** — read the counter right after the tx (the new job is the latest):
  ```bash
  cast call <hub> "jobCount()(uint256)" --rpc-url <rpc>
  ```
- **From the receipt logs** — `JobCreated`'s first indexed topic (after the event signature) is the
  `jobId`. Decode topic[1] of the log emitted by `<hub>`.

| Field | Description |
|-------|-------------|
| `status` | `1` = success |
| `transactionHash` | Creation tx |
| `jobId` | From `jobCount()` or the `JobCreated` event |

### Error Handling
| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `execution reverted: No PHRS sent` | `--value` missing or zero | Pass `--value <amount>ether` |
| `execution reverted: Bad worker` | worker is the zero address | Provide a valid worker address |
| `execution reverted: Worker is client` | worker == caller | Worker must be a different address |
| `execution reverted: Deadline in past` | deadline ≤ now | Use a future unix timestamp |
| `execution reverted: No review window` | reviewWindow == 0 | Pass a positive review window |
| `insufficient funds` | Balance < value + gas | Check `cast balance` |

> **Agent Guidelines**:
> 1. Complete "Write Operation Pre-checks" (see SKILL.md) and confirm the target network.
> 2. Compute `deadline` from the user's duration with `date +%s`; default `reviewWindow` to `86400`
>    (1 day) unless specified.
> 3. Confirm worker address, amount, deadline, and review window with the user before sending.
> 4. After success, fetch `jobCount()` to report the new `jobId`, and show
>    `<explorerUrl>/tx/<transactionHash>`.

---

## 3. Submit Work (Worker)

### Overview
The worker marks the job delivered and records a `bytes32` hash/CID of the off-chain deliverable.
Allowed only while the job is `Funded`. Starts the review window.

### Command Template
```bash
cast send <hub> "submitWork(uint256,bytes32)" <jobId> <deliverableHash> \
  --private-key $PRIVATE_KEY \
  --rpc-url <rpc>
```
Derive a `bytes32` hash from any deliverable reference (URL, IPFS CID, result text):
```bash
DELIVERABLE_HASH=$(cast keccak "ipfs://bafy...your-cid")
```

### Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `<jobId>` | uint256 | Yes | The job to deliver |
| `<deliverableHash>` | bytes32 | Yes | `cast keccak` of the deliverable reference |

### Output Parsing
| Field | Description |
|-------|-------------|
| `status` | `1` = success; emits `WorkSubmitted(jobId, deliverableHash, deliveredAt)` |

### Error Handling
| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `execution reverted: Not funded` | Job is not in `Funded` state | Check `stateOf(jobId)`; it may already be delivered/closed |
| `execution reverted: Not worker` | Caller isn't the job's worker | Use the worker wallet |

> **Agent Guidelines**: Complete Write Operation Pre-checks. Generate the `deliverableHash` with
> `cast keccak` from whatever reference the user gives (IPFS CID, URL, or raw result). After
> success, tell the user the review window has started and show `timeToAutoRelease(jobId)`.

---

## 4. Approve & Release Payment (Client)

### Overview
The client approves the job and releases the full escrowed amount to the worker. Allowed from
`Funded` or `Delivered`. **Irreversible.**

### Command Template
```bash
cast send <hub> "approve(uint256)" <jobId> \
  --private-key $PRIVATE_KEY \
  --rpc-url <rpc>
```

### Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `<jobId>` | uint256 | Yes | The job to release |

### Output Parsing
| Field | Description |
|-------|-------------|
| `status` | `1` = success; emits `Released(jobId, worker, amount)` |

### Error Handling
| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `execution reverted: Not client` | Caller isn't the job's client | Use the client wallet |
| `execution reverted: Not active` | Job already Released/Refunded | Check `stateOf(jobId)` |
| `execution reverted: Pay failed` | Worker is a contract that rejects PHRS | The worker address cannot receive native PHRS |

> **Agent Guidelines**: Complete Write Operation Pre-checks. **Releasing is irreversible** — before
> sending, show the user the job's `getJob()` details (worker, amount, deliverableHash) and ask for
> explicit confirmation. After success, show `<explorerUrl>/tx/<transactionHash>`.

---

## 5. Refund an Expired Job (Client)

### Overview
The client reclaims the escrow when the worker missed the deadline. Allowed only while still
`Funded` (no delivery) and after `deadline`.

### Command Template
```bash
cast send <hub> "refund(uint256)" <jobId> \
  --private-key $PRIVATE_KEY \
  --rpc-url <rpc>
```

### Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `<jobId>` | uint256 | Yes | The expired job |

### Output Parsing
| Field | Description |
|-------|-------------|
| `status` | `1` = success; emits `Refunded(jobId, client, amount)` |

### Error Handling
| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `execution reverted: Not client` | Caller isn't the client | Use the client wallet |
| `execution reverted: Not refundable` | Job is delivered or already closed | Check `stateOf(jobId)`; delivered jobs cannot be refunded |
| `execution reverted: Deadline not reached` | Deadline hasn't passed | Show `timeToDeadline(jobId)`; wait until it returns 0 |

> **Agent Guidelines**: Complete Write Operation Pre-checks. First call `timeToDeadline(jobId)` and
> `stateOf(jobId)` to confirm the job is still `Funded` and the deadline has passed; only then refund.

---

## 6. Claim After Review Window (Worker)

### Overview
The worker self-claims payment when the client never approved after delivery. Allowed only while
`Delivered` and after `deliveredAt + reviewWindow`. Protects the worker from a ghosting client.

### Command Template
```bash
cast send <hub> "claim(uint256)" <jobId> \
  --private-key $PRIVATE_KEY \
  --rpc-url <rpc>
```

### Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `<jobId>` | uint256 | Yes | The delivered job past its review window |

### Output Parsing
| Field | Description |
|-------|-------------|
| `status` | `1` = success; emits `Released(jobId, worker, amount)` |

### Error Handling
| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `execution reverted: Not worker` | Caller isn't the worker | Use the worker wallet |
| `execution reverted: Not delivered` | Job not in `Delivered` state | Submit work first, or the job is already closed |
| `execution reverted: Review window open` | Review window hasn't elapsed | Show `timeToAutoRelease(jobId)`; wait until it returns 0 |

> **Agent Guidelines**: Complete Write Operation Pre-checks. First call `timeToAutoRelease(jobId)`;
> only claim when it returns 0. After success, show `<explorerUrl>/tx/<transactionHash>`.

---

## 7. Query Job Status

### Overview
Read-only inspection of a job — no gas, no private key.

### Command Template
```bash
# Full job details
cast call <hub> "getJob(uint256)(address,address,uint256,uint64,uint64,uint64,uint8,bytes32)" <jobId> --rpc-url <rpc>

# Just the numeric state (1=Funded 2=Delivered 3=Released 4=Refunded)
cast call <hub> "stateOf(uint256)(uint8)" <jobId> --rpc-url <rpc>

# Seconds until the delivery deadline (0 = passed)
cast call <hub> "timeToDeadline(uint256)(uint256)" <jobId> --rpc-url <rpc>

# Seconds until the worker may self-claim (0 unless in review)
cast call <hub> "timeToAutoRelease(uint256)(uint256)" <jobId> --rpc-url <rpc>

# Total jobs created
cast call <hub> "jobCount()(uint256)" --rpc-url <rpc>
```

### Output Parsing
`getJob` returns, in order: `client`, `worker`, `amount` (wei), `deadline`, `reviewWindow`,
`deliveredAt`, `state` (uint8), `deliverableHash`. Convert `amount` to ether with
`cast from-wei <amount>` for display.

### Error Handling
| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| All-zero return | Job id does not exist | Confirm the `jobId` (ids start at 1) |
| `connection refused` | Missing `--rpc-url` | Pass `--rpc-url <rpc>` |

> **Agent Guidelines**: Use these before any write to give the user an accurate status. Map the
> `state` number to a label and show `amount` in PHRS.

---

## 8. Query Events (Job History)

### Overview
Reconstruct a job's history from on-chain events. All key fields are indexed for filtering.

### Command Template
```bash
# All job creations
cast logs --rpc-url <rpc> --address <hub> "JobCreated(uint256,address,address,uint256,uint64,uint64)"

# Deliveries
cast logs --rpc-url <rpc> --address <hub> "WorkSubmitted(uint256,bytes32,uint64)"

# Payouts to workers
cast logs --rpc-url <rpc> --address <hub> "Released(uint256,address,uint256)"

# Refunds to clients
cast logs --rpc-url <rpc> --address <hub> "Refunded(uint256,address,uint256)"
```
Filter by a specific `jobId` (indexed topic 1) by appending the padded topic, e.g. job 1:
```bash
cast logs --rpc-url <rpc> --address <hub> \
  "Released(uint256,address,uint256)" \
  0x0000000000000000000000000000000000000000000000000000000000000001
```

### Output Parsing
Each log lists `topics` (indexed fields) and `data` (non-indexed fields). For `JobCreated`,
topic[1]=jobId, topic[2]=client, topic[3]=worker; `data` holds amount, deadline, reviewWindow.

### Error Handling
| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| Empty result | No matching events in range | Widen the block range (`--from-block 0`) or check the address |
| `connection refused` | Missing `--rpc-url` | Pass `--rpc-url <rpc>` |

> **Agent Guidelines**: Use `--from-block 0` on testnet for a full history. Present results as a
> timeline (created → delivered → released/refunded) per `jobId`.

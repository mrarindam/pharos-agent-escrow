# Live Demo — Agent-to-Agent Escrow on Pharos Atlantic Testnet

This is a **real, on-chain** end-to-end run of the Agent Escrow skill. Every transaction below is
live on the Pharos Atlantic testnet and viewable on the explorer.

## Actors

| Role | Address |
|------|---------|
| **AgentEscrow hub** (deployed + verified) | [`0x10B1A5680F95b81c9cC8E87a9780f7ceE32f36fB`](https://atlantic.pharosscan.xyz/address/0x10B1A5680F95b81c9cC8E87a9780f7ceE32f36fB) |
| **Client** (agent A — hires & pays) | [`0x62B7E982FBfC75de1778e172B200F68f73455bB3`](https://atlantic.pharosscan.xyz/address/0x62B7E982FBfC75de1778e172B200F68f73455bB3) |
| **Worker** (agent B — delivers & gets paid) | [`0x17E80F4b32cebe4ae13BE26deA2c3BD4e2D697a3`](https://atlantic.pharosscan.xyz/address/0x17E80F4b32cebe4ae13BE26deA2c3BD4e2D697a3) |

## The happy path: `createJob → submitWork → approve`

| # | Action | State after | Transaction |
|---|--------|-------------|-------------|
| 1 | **createJob** — client escrows `0.001 PHRS` for the worker (deadline +1h, review window 1d). Hub balance → `0.001 PHRS`. | `1` Funded | [`0x3e86f698…fc8da9`](https://atlantic.pharosscan.xyz/tx/0x3e86f6987035bbd7b6da7c0130fb37ede0ddd30ee4c5aa53a6fa6be859fc8da9) |
| 2 | **submitWork** — worker delivers, recording `keccak("ipfs://bafy-demo-deliverable")` on-chain. | `2` Delivered | [`0x0d677a1d…89d8d17`](https://atlantic.pharosscan.xyz/tx/0x0d677a1d5915c1acb1eba659dc6a6a4721f449ac8ce88266bc7a954af89d8d17) |
| 3 | **approve** — client accepts; the `0.001 PHRS` is released to the worker. Worker balance **+0.001 PHRS**, hub balance → `0`. | `3` Released | [`0xa506d0a3…055f7be`](https://atlantic.pharosscan.xyz/tx/0xa506d0a3f7e3cabfdbe72510ae0761115f34edcc49066bb6c3ba79bd8055f7be) |

> A setup transfer funded the freshly generated worker wallet with a little gas:
> [`0xec7c82d1…21c1b6f`](https://atlantic.pharosscan.xyz/tx/0xec7c82d15d8d4de14ad4991831c3076255318f51ef263ed70d270170421c1b6f).

### Final on-chain state — `getJob(1)`

```
client          0x62B7E982FBfC75de1778e172B200F68f73455bB3
worker          0x17E80F4b32cebe4ae13BE26deA2c3BD4e2D697a3
amount          1000000000000000  (0.001 PHRS)
deadline        1781283536
reviewWindow    86400
deliveredAt     1781279943
state           3  (Released)
deliverableHash 0x519e5ed3be49b4cde28fdeaccbdbbd6c883981158df47039835b489a446a6103
```

The escrow held the funds while the job was in progress and released exactly the locked amount to
the worker on the client's approval — no third party could touch the money at any point.

## What this proves

- **Funds are held by the contract**, not by either party, between `createJob` and the payout.
- **Only the client can release** (`approve`) and **only the worker can deliver** (`submitWork`).
- **State machine is enforced on-chain**: `Funded → Delivered → Released`.
- **The deliverable is anchored on-chain** via a content hash for auditability.

## Other paths (covered by the test suite, see `test/AgentEscrow.t.sol`)

- **Refund** — if the worker misses the deadline, the client calls `refund(jobId)` and gets the
  PHRS back. Blocked before the deadline (`Deadline not reached`) and after delivery (`Not refundable`).
- **Claim** — if the client disappears after delivery, the worker calls `claim(jobId)` once the
  review window elapses. Blocked during the window (`Review window open`).

## Reproduce it yourself

With Foundry installed and `PRIVATE_KEY` exported (a funded testnet key), point Claude Code at this
skill and ask, in plain English:

```
Deploy the AgentEscrow hub on Pharos.
Create an escrow job hiring 0x<worker> for 0.001 PHRS with a 1 hour deadline.
The worker delivered ipfs://<cid> — submit the work for job 1.
Approve and release payment for job 1.
Show me the status and history of job 1.
```

The skill resolves each request to the right `cast`/`forge` command using `references/escrow.md`.

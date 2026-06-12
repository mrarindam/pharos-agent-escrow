// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title AgentEscrow
/// @author Pharos Agent Escrow Skill (Skill-to-Agent Dual Cascade Hackathon, Phase 1)
/// @notice A trustless, native-PHRS escrow hub for agent-to-agent service payments on Pharos.
///         A client locks PHRS for a chosen worker against a delivery deadline. The worker
///         delivers off-chain work (referenced on-chain by a content hash) and the client
///         releases payment. If the worker misses the deadline the client can refund; if the
///         client disappears after delivery, the worker can claim once a review window elapses.
///
/// @dev    Design goals: deliberately minimal, dependency-free and easy to audit.
///         - No owner, no admin, no upgradeability, no `selfdestruct`, no `delegatecall`.
///         - Funds can only ever flow back to the original `client` (refund) or to the
///           designated `worker` (release / claim). There is no path to a third party.
///         - Checks-Effects-Interactions is followed on every payout and a minimal
///           reentrancy guard wraps every function that moves value.
contract AgentEscrow {
    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------

    /// @notice Lifecycle of an escrow job.
    /// None      0 - job does not exist
    /// Funded    1 - client funded the job, awaiting delivery
    /// Delivered 2 - worker submitted a deliverable, awaiting client approval
    /// Released  3 - terminal: paid out to the worker
    /// Refunded  4 - terminal: refunded to the client
    enum State {
        None,
        Funded,
        Delivered,
        Released,
        Refunded
    }

    struct Job {
        address client; // who funds and approves the job
        address worker; // who performs the work and gets paid
        uint256 amount; // PHRS held in escrow (wei)
        uint64 deadline; // unix time by which the worker must deliver
        uint64 reviewWindow; // seconds the client has to review after delivery
        uint64 deliveredAt; // unix time the worker delivered (0 until delivered)
        State state;
        bytes32 deliverableHash; // hash/CID of the off-chain deliverable
    }

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    /// @notice Total number of jobs ever created. The most recent job id equals `jobCount`.
    uint256 public jobCount;

    /// @dev jobId => Job. jobIds start at 1; id 0 is reserved for "does not exist".
    mapping(uint256 => Job) private _jobs;

    /// @dev Minimal reentrancy guard (1 = unlocked, 2 = locked) — cheaper than a bool toggle.
    uint256 private _lock = 1;

    modifier nonReentrant() {
        require(_lock == 1, "Reentrancy");
        _lock = 2;
        _;
        _lock = 1;
    }

    // ---------------------------------------------------------------------
    // Events  (all key fields indexed so agents can filter via `cast logs`)
    // ---------------------------------------------------------------------

    event JobCreated(
        uint256 indexed jobId,
        address indexed client,
        address indexed worker,
        uint256 amount,
        uint64 deadline,
        uint64 reviewWindow
    );
    event WorkSubmitted(uint256 indexed jobId, bytes32 deliverableHash, uint64 deliveredAt);
    event Released(uint256 indexed jobId, address indexed worker, uint256 amount);
    event Refunded(uint256 indexed jobId, address indexed client, uint256 amount);

    // ---------------------------------------------------------------------
    // Write operations
    // ---------------------------------------------------------------------

    /// @notice Create and fund a new escrow job for `worker`.
    /// @param worker        Address that will perform the work and receive payment.
    /// @param deadline      Unix timestamp by which the worker must deliver.
    /// @param reviewWindow  Seconds the client has to review after delivery before the
    ///                      worker may self-claim. Must be > 0.
    /// @return jobId        The id of the newly created job.
    function createJob(address worker, uint64 deadline, uint64 reviewWindow)
        external
        payable
        nonReentrant
        returns (uint256 jobId)
    {
        require(msg.value > 0, "No PHRS sent");
        require(worker != address(0), "Bad worker");
        require(worker != msg.sender, "Worker is client");
        require(deadline > block.timestamp, "Deadline in past");
        require(reviewWindow > 0, "No review window");

        jobId = ++jobCount;
        _jobs[jobId] = Job({
            client: msg.sender,
            worker: worker,
            amount: msg.value,
            deadline: deadline,
            reviewWindow: reviewWindow,
            deliveredAt: 0,
            state: State.Funded,
            deliverableHash: bytes32(0)
        });

        emit JobCreated(jobId, msg.sender, worker, msg.value, deadline, reviewWindow);
    }

    /// @notice Worker marks the job delivered, recording a hash/CID of the deliverable.
    /// @dev    Allowed only while the job is Funded. Records `block.timestamp` to start the
    ///         review window. The deliverable itself lives off-chain; only its hash is stored.
    function submitWork(uint256 jobId, bytes32 deliverableHash) external {
        Job storage j = _jobs[jobId];
        require(j.state == State.Funded, "Not funded");
        require(msg.sender == j.worker, "Not worker");

        j.deliverableHash = deliverableHash;
        j.deliveredAt = uint64(block.timestamp);
        j.state = State.Delivered;

        emit WorkSubmitted(jobId, deliverableHash, j.deliveredAt);
    }

    /// @notice Client approves the job and releases the escrowed PHRS to the worker.
    /// @dev    Allowed from Funded (release without a formal delivery) or Delivered.
    function approve(uint256 jobId) external nonReentrant {
        Job storage j = _jobs[jobId];
        require(msg.sender == j.client, "Not client");
        require(j.state == State.Funded || j.state == State.Delivered, "Not active");

        uint256 amount = j.amount;
        address worker = j.worker;
        j.state = State.Released; // effects before interaction

        (bool ok, ) = payable(worker).call{value: amount}("");
        require(ok, "Pay failed");

        emit Released(jobId, worker, amount);
    }

    /// @notice Client reclaims funds when the worker missed the delivery deadline.
    /// @dev    Allowed only while still Funded (no delivery) and after the deadline passed.
    function refund(uint256 jobId) external nonReentrant {
        Job storage j = _jobs[jobId];
        require(msg.sender == j.client, "Not client");
        require(j.state == State.Funded, "Not refundable");
        require(block.timestamp >= j.deadline, "Deadline not reached");

        uint256 amount = j.amount;
        address client = j.client;
        j.state = State.Refunded; // effects before interaction

        (bool ok, ) = payable(client).call{value: amount}("");
        require(ok, "Refund failed");

        emit Refunded(jobId, client, amount);
    }

    /// @notice Worker self-claims payment when the client never approved after delivery.
    /// @dev    Allowed only while Delivered and after `deliveredAt + reviewWindow`.
    ///         Protects the worker from a client that disappears after receiving the work.
    function claim(uint256 jobId) external nonReentrant {
        Job storage j = _jobs[jobId];
        require(msg.sender == j.worker, "Not worker");
        require(j.state == State.Delivered, "Not delivered");
        require(block.timestamp >= uint256(j.deliveredAt) + j.reviewWindow, "Review window open");

        uint256 amount = j.amount;
        address worker = j.worker;
        j.state = State.Released; // effects before interaction

        (bool ok, ) = payable(worker).call{value: amount}("");
        require(ok, "Pay failed");

        emit Released(jobId, worker, amount);
    }

    // ---------------------------------------------------------------------
    // Read-only views
    // ---------------------------------------------------------------------

    /// @notice Return every field of a job in one call.
    function getJob(uint256 jobId)
        external
        view
        returns (
            address client,
            address worker,
            uint256 amount,
            uint64 deadline,
            uint64 reviewWindow,
            uint64 deliveredAt,
            uint8 state,
            bytes32 deliverableHash
        )
    {
        Job storage j = _jobs[jobId];
        return (
            j.client,
            j.worker,
            j.amount,
            j.deadline,
            j.reviewWindow,
            j.deliveredAt,
            uint8(j.state),
            j.deliverableHash
        );
    }

    /// @notice Numeric state of a job (see the State enum).
    function stateOf(uint256 jobId) external view returns (uint8) {
        return uint8(_jobs[jobId].state);
    }

    /// @notice Seconds until the delivery deadline (0 if already passed or job missing).
    function timeToDeadline(uint256 jobId) external view returns (uint256) {
        uint64 d = _jobs[jobId].deadline;
        if (d == 0 || block.timestamp >= d) return 0;
        return d - block.timestamp;
    }

    /// @notice Seconds until the worker may self-claim (0 unless currently in review).
    function timeToAutoRelease(uint256 jobId) external view returns (uint256) {
        Job storage j = _jobs[jobId];
        if (j.state != State.Delivered) return 0;
        uint256 unlockAt = uint256(j.deliveredAt) + j.reviewWindow;
        if (block.timestamp >= unlockAt) return 0;
        return unlockAt - block.timestamp;
    }
}

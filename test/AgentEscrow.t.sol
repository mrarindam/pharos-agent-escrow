// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/escrow/AgentEscrow.sol";

/// @dev A malicious "worker" that attempts to re-enter the escrow when it is paid.
///      Used to prove the reentrancy guard + checks-effects-interactions keep funds safe.
contract ReentrantWorker {
    AgentEscrow public escrow;
    uint256 public jobId;

    constructor(AgentEscrow _escrow) {
        escrow = _escrow;
    }

    function setJob(uint256 _jobId) external {
        jobId = _jobId;
    }

    function submit(bytes32 h) external {
        escrow.submitWork(jobId, h);
    }

    function doClaim() external {
        escrow.claim(jobId);
    }

    // On receiving PHRS, try to re-enter claim(). The guard must make this revert,
    // which makes the outer payout's low-level call fail ("Pay failed").
    receive() external payable {
        escrow.claim(jobId);
    }
}

contract AgentEscrowTest is Test {
    AgentEscrow internal escrow;

    address internal client;
    address internal worker;
    address internal stranger;

    uint256 internal constant AMOUNT = 1 ether;
    uint64 internal constant REVIEW = 1 days;

    // Mirror the contract's events for expectEmit.
    event JobCreated(
        uint256 indexed jobId,
        address indexed client,
        address indexed worker,
        uint256 amount,
        uint64 deadline,
        uint64 reviewWindow
    );
    event Released(uint256 indexed jobId, address indexed worker, uint256 amount);
    event Refunded(uint256 indexed jobId, address indexed client, uint256 amount);

    function setUp() public {
        escrow = new AgentEscrow();
        client = makeAddr("client");
        worker = makeAddr("worker");
        stranger = makeAddr("stranger");
        vm.deal(client, 10 ether);
        // Ensure block.timestamp is well above 0 so deadlines are sane.
        vm.warp(1_700_000_000);
    }

    // ----- helpers -----

    function _createJob() internal returns (uint256 jobId) {
        uint64 deadline = uint64(block.timestamp + 1 hours);
        vm.prank(client);
        jobId = escrow.createJob{value: AMOUNT}(worker, deadline, REVIEW);
    }

    // ----- creation -----

    function test_CreateJob_HoldsFundsAndEmits() public {
        uint64 deadline = uint64(block.timestamp + 1 hours);

        vm.expectEmit(true, true, true, true);
        emit JobCreated(1, client, worker, AMOUNT, deadline, REVIEW);

        vm.prank(client);
        uint256 jobId = escrow.createJob{value: AMOUNT}(worker, deadline, REVIEW);

        assertEq(jobId, 1);
        assertEq(escrow.jobCount(), 1);
        assertEq(address(escrow).balance, AMOUNT);
        assertEq(escrow.stateOf(jobId), uint8(AgentEscrow.State.Funded));

        (address c, address w, uint256 amt, , , , uint8 st, ) = escrow.getJob(jobId);
        assertEq(c, client);
        assertEq(w, worker);
        assertEq(amt, AMOUNT);
        assertEq(st, uint8(AgentEscrow.State.Funded));
    }

    function test_CreateJob_RevertsOnZeroValue() public {
        vm.prank(client);
        vm.expectRevert("No PHRS sent");
        escrow.createJob{value: 0}(worker, uint64(block.timestamp + 1 hours), REVIEW);
    }

    function test_CreateJob_RevertsOnZeroWorker() public {
        vm.prank(client);
        vm.expectRevert("Bad worker");
        escrow.createJob{value: AMOUNT}(address(0), uint64(block.timestamp + 1 hours), REVIEW);
    }

    function test_CreateJob_RevertsWhenWorkerIsClient() public {
        vm.prank(client);
        vm.expectRevert("Worker is client");
        escrow.createJob{value: AMOUNT}(client, uint64(block.timestamp + 1 hours), REVIEW);
    }

    function test_CreateJob_RevertsOnPastDeadline() public {
        vm.prank(client);
        vm.expectRevert("Deadline in past");
        escrow.createJob{value: AMOUNT}(worker, uint64(block.timestamp), REVIEW);
    }

    function test_CreateJob_RevertsOnZeroReviewWindow() public {
        vm.prank(client);
        vm.expectRevert("No review window");
        escrow.createJob{value: AMOUNT}(worker, uint64(block.timestamp + 1 hours), 0);
    }

    // ----- happy paths -----

    function test_ApproveReleasesToWorker() public {
        uint256 jobId = _createJob();
        uint256 before = worker.balance;

        vm.expectEmit(true, true, false, true);
        emit Released(jobId, worker, AMOUNT);

        vm.prank(client);
        escrow.approve(jobId);

        assertEq(worker.balance, before + AMOUNT);
        assertEq(address(escrow).balance, 0);
        assertEq(escrow.stateOf(jobId), uint8(AgentEscrow.State.Released));
    }

    function test_SubmitThenApprove() public {
        uint256 jobId = _createJob();

        vm.prank(worker);
        escrow.submitWork(jobId, keccak256("ipfs://result"));
        assertEq(escrow.stateOf(jobId), uint8(AgentEscrow.State.Delivered));

        vm.prank(client);
        escrow.approve(jobId);
        assertEq(worker.balance, AMOUNT);
        assertEq(escrow.stateOf(jobId), uint8(AgentEscrow.State.Released));
    }

    // ----- refund (worker missed deadline) -----

    function test_Refund_RevertsBeforeDeadline() public {
        uint256 jobId = _createJob();
        vm.prank(client);
        vm.expectRevert("Deadline not reached");
        escrow.refund(jobId);
    }

    function test_Refund_SucceedsAfterDeadline() public {
        uint256 jobId = _createJob();
        uint256 before = client.balance;

        vm.warp(block.timestamp + 1 hours + 1);

        vm.expectEmit(true, true, false, true);
        emit Refunded(jobId, client, AMOUNT);

        vm.prank(client);
        escrow.refund(jobId);

        assertEq(client.balance, before + AMOUNT);
        assertEq(escrow.stateOf(jobId), uint8(AgentEscrow.State.Refunded));
    }

    function test_Refund_RevertsAfterDelivery() public {
        uint256 jobId = _createJob();
        vm.prank(worker);
        escrow.submitWork(jobId, keccak256("done"));

        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(client);
        vm.expectRevert("Not refundable");
        escrow.refund(jobId);
    }

    // ----- claim (client ghosted after delivery) -----

    function test_Claim_RevertsDuringReviewWindow() public {
        uint256 jobId = _createJob();
        vm.prank(worker);
        escrow.submitWork(jobId, keccak256("done"));

        vm.prank(worker);
        vm.expectRevert("Review window open");
        escrow.claim(jobId);
    }

    function test_Claim_SucceedsAfterReviewWindow() public {
        uint256 jobId = _createJob();
        vm.prank(worker);
        escrow.submitWork(jobId, keccak256("done"));

        vm.warp(block.timestamp + REVIEW + 1);

        vm.prank(worker);
        escrow.claim(jobId);

        assertEq(worker.balance, AMOUNT);
        assertEq(escrow.stateOf(jobId), uint8(AgentEscrow.State.Released));
    }

    function test_Claim_RevertsIfNotDelivered() public {
        uint256 jobId = _createJob();
        vm.warp(block.timestamp + REVIEW + 1);
        vm.prank(worker);
        vm.expectRevert("Not delivered");
        escrow.claim(jobId);
    }

    // ----- access control -----

    function test_OnlyClientCanApprove() public {
        uint256 jobId = _createJob();
        vm.prank(stranger);
        vm.expectRevert("Not client");
        escrow.approve(jobId);
    }

    function test_OnlyWorkerCanSubmit() public {
        uint256 jobId = _createJob();
        vm.prank(stranger);
        vm.expectRevert("Not worker");
        escrow.submitWork(jobId, keccak256("x"));
    }

    function test_OnlyClientCanRefund() public {
        uint256 jobId = _createJob();
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(stranger);
        vm.expectRevert("Not client");
        escrow.refund(jobId);
    }

    function test_OnlyWorkerCanClaim() public {
        uint256 jobId = _createJob();
        vm.prank(worker);
        escrow.submitWork(jobId, keccak256("done"));
        vm.warp(block.timestamp + REVIEW + 1);
        vm.prank(stranger);
        vm.expectRevert("Not worker");
        escrow.claim(jobId);
    }

    // ----- no double-spend -----

    function test_CannotApproveTwice() public {
        uint256 jobId = _createJob();
        vm.prank(client);
        escrow.approve(jobId);
        vm.prank(client);
        vm.expectRevert("Not active");
        escrow.approve(jobId);
    }

    function test_CannotRefundAfterRelease() public {
        uint256 jobId = _createJob();
        vm.prank(client);
        escrow.approve(jobId);
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(client);
        vm.expectRevert("Not refundable");
        escrow.refund(jobId);
    }

    // ----- reentrancy: a malicious worker cannot drain the escrow -----

    function test_ReentrantWorkerCannotDrain() public {
        ReentrantWorker attacker = new ReentrantWorker(escrow);

        uint64 deadline = uint64(block.timestamp + 1 hours);
        vm.prank(client);
        uint256 jobId = escrow.createJob{value: AMOUNT}(address(attacker), deadline, REVIEW);
        attacker.setJob(jobId);

        attacker.submit(keccak256("malicious"));
        vm.warp(block.timestamp + REVIEW + 1);

        // The attacker's receive() re-enters claim(); the guard reverts it, so the outer
        // payout's low-level call fails. Funds stay locked — nothing is drained.
        vm.expectRevert("Pay failed");
        attacker.doClaim();

        assertEq(address(escrow).balance, AMOUNT);
        assertEq(escrow.stateOf(jobId), uint8(AgentEscrow.State.Delivered));
    }

    // ----- views -----

    function test_TimeToDeadlineAndAutoRelease() public {
        uint256 jobId = _createJob();
        assertApproxEqAbs(escrow.timeToDeadline(jobId), 1 hours, 2);
        assertEq(escrow.timeToAutoRelease(jobId), 0); // not delivered yet

        vm.prank(worker);
        escrow.submitWork(jobId, keccak256("done"));
        assertApproxEqAbs(escrow.timeToAutoRelease(jobId), REVIEW, 2);

        vm.warp(block.timestamp + 1 hours + 1);
        assertEq(escrow.timeToDeadline(jobId), 0);
    }
}

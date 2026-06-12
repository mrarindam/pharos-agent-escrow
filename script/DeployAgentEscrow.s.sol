// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/escrow/AgentEscrow.sol";

/// @notice Deploys the AgentEscrow hub. The hub takes no constructor arguments and serves
///         the whole ecosystem — deploy once, then create jobs against it.
contract DeployAgentEscrow is Script {
    function run() external {
        vm.startBroadcast();

        AgentEscrow escrow = new AgentEscrow();

        console.log("=== Deploy Result ===");
        console.log("AgentEscrow hub:", address(escrow));
        console.log("Deployer:", msg.sender);
        console.log("Initial jobCount:", escrow.jobCount());

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/ProofManager.sol";

contract DeployEnhancedScript is Script {
    function run() external {
        // Retrieve private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the contract
        // Can initialize with zero addresses and set them later

        // address provingNetwork1 = address(0);
        // address provingNetwork2 = address(0);

        // ProofManager proofManager = new EnhancedProofManager(
        //     provingNetwork1,
        //     provingNetwork2
        // );

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log deployed contract address
        // console.log("EnhancedProofManager deployed at:", address(proofManager));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script, console } from "forge-std/Script.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProofManagerV1 } from "../../src/ProofManagerV1.sol";

/// @author Matter Labs
/// @notice Deploys the ProofManagerV1 contract behind UpgradeableProxy.
contract DeployProofManagerV1 is Script {
    function run() external {
        address FERMAH = vm.envAddress("FERMAH_ADDRESS");
        address LAGRANGE = vm.envAddress("LAGRANGE_ADDRESS");
        address USDC = vm.envAddress("USDC_ADDRESS");
        address PROOF_MANAGER_OWNER = vm.envAddress("PROOF_MANAGER_OWNER_ADDRESS");
        address PROXY_OWNER = vm.envAddress("PROXY_OWNER_ADDRESS");

        // PK & RPC expected to be passed as `--private-key` and `--rpc-url`
        vm.startBroadcast();

        ProofManagerV1 impl = new ProofManagerV1();

        ProxyAdmin admin = new ProxyAdmin(PROXY_OWNER);

        bytes memory init =
            abi.encodeCall(ProofManagerV1.initialize, (FERMAH, LAGRANGE, USDC, PROOF_MANAGER_OWNER));

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(admin), init);

        console.log("IMPLEMENTATION:", address(impl));
        console.log("PROXY:         ", address(proxy));
        console.log("PROXY_ADMIN:   ", address(admin));

        vm.stopBroadcast();
    }
}

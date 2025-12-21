// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script, console } from "forge-std/Script.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProofManagerV1 } from "../../src/ProofManagerV1.sol";

contract DeployProofManagerV1 is Script {
    // EIP-1967 admin slot:
    // bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1)
    bytes32 internal constant _ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function run() external {
        address FERMAH = vm.envAddress("FERMAH_ADDRESS");
        address LAGRANGE = vm.envAddress("LAGRANGE_ADDRESS");
        address USDC = vm.envAddress("USDC_ADDRESS");
        address PROOF_MANAGER_SUBMITTER = vm.envAddress("PROOF_MANAGER_SUBMITTER_ADDRESS");
        address PROXY_OWNER = vm.envAddress("PROXY_OWNER_ADDRESS");
        address ADMIN_ADDRESS = vm.envAddress("ADMIN_ADDRESS");

        vm.startBroadcast();

        ProofManagerV1 impl = new ProofManagerV1();

        bytes memory init = abi.encodeCall(
            ProofManagerV1.initialize,
            (FERMAH, LAGRANGE, USDC, PROOF_MANAGER_SUBMITTER, ADMIN_ADDRESS)
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), PROXY_OWNER, init);

        // Read the proxy's admin slot from the proxy's storage:
        address proxyAdmin = address(uint160(uint256(vm.load(address(proxy), _ADMIN_SLOT))));

        console.log("IMPLEMENTATION:", address(impl));
        console.log("PROXY:         ", address(proxy));
        console.log("PROXY_ADMIN:   ", proxyAdmin);
        console.log("PROXY_OWNER:   ", PROXY_OWNER);
        console.log("ADMIN:         ", ADMIN_ADDRESS);
        console.log("SUBMITTER:     ", PROOF_MANAGER_SUBMITTER);

        vm.stopBroadcast();
    }
}

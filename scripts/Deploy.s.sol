// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/ProofManagerV1.sol";

contract DeployProofManager is Script {
    address constant FERMAH = makeAddr("fermah");
    address constant LAGRANGE = makeAddr("lagrange");
    address constant USDC = address(0); // to be updated once deployment is ready
    address constant OWNER = address(0); // to be updated once deployment is ready & it is agreed with security

    function run() external {
        // PK & RPC expected to be passed as `--private-key` and `--rpc-url`
        vm.startBroadcast();

        ProofManagerV1 impl = new ProofManagerV1();

        ProxyAdmin admin = new ProxyAdmin();

        bytes memory init = abi.encodeCall(ProofManagerV1.initialize, (FERMAH, LAGRANGE, USDC));

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(admin), init);

        console.log("IMPLEMENTATION:", address(impl));
        console.log("PROXY:         ", address(proxy));
        console.log("PROXY_ADMIN:   ", address(admin));

        vm.stopBroadcast();
    }
}

// // SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "./Base.t.sol";

contract ProofManagerTest is Base {
    /// @dev Happy path for constructor.
    function testInit() public view {
        assertEq(proofManager.owner(), owner, "owner must be contract deployer");

        assertProvingNetworkInfo(
            ProvingNetwork.Fermah,
            ProofManagerStorage.ProvingNetworkInfo(
                fermah, ProvingNetworkStatus.Active, new ProofRequestIdentifier[](0), 0
            )
        );
        assertProvingNetworkInfo(
            ProvingNetwork.Lagrange,
            ProofManagerStorage.ProvingNetworkInfo(
                lagrange, ProvingNetworkStatus.Active, new ProofRequestIdentifier[](0), 0
            )
        );

        assertEq(
            uint8(proofManager.preferredNetwork()),
            uint8(ProvingNetwork.None),
            "preferred network should be None"
        );
    }

    /// @dev Happy path for constructor, checking events.
    function testConstructorEmitsEvents() public {
        vm.expectEmit(true, true, false, false);
        emit ProvingNetworkAddressChanged(ProvingNetwork.Fermah, fermah);
        vm.expectEmit(true, true, false, false);
        emit ProvingNetworkStatusChanged(ProvingNetwork.Fermah, ProvingNetworkStatus.Active);
        vm.expectEmit(true, true, false, false);
        emit ProvingNetworkAddressChanged(ProvingNetwork.Lagrange, lagrange);
        vm.expectEmit(true, true, false, false);
        emit ProvingNetworkStatusChanged(ProvingNetwork.Lagrange, ProvingNetworkStatus.Active);

        vm.expectEmit(true, false, false, false);
        emit PreferredNetworkSet(ProvingNetwork.None);
        new ProofManagerHarness(fermah, lagrange, address(usdc));
    }

    /// @dev Do not allow zero address for proving networks.
    function testInitFailsWithZeroProvingNetworkAddress() public {
        vm.expectRevert("proving network address cannot be zero");
        new ProofManagerV1(address(0), lagrange, address(this));
        vm.expectRevert("proving network address cannot be zero");
        new ProofManagerV1(fermah, address(0), address(this));
    }

    /// @dev Do not allow zero address for USDC contract.
    function testInitFailsWithZeroUSDCAddress() public {
        vm.expectRevert("usdc contract address cannot be zero");
        new ProofManagerV1(fermah, lagrange, address(0));
    }
}

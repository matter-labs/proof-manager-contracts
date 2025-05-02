// // SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "./Base.t.sol";

contract ProofManagerTest is Base {
    /// @dev Happy path for constructor.
    function testInit() public view {
        assertEq(proofManager.owner(), owner, "owner must be contract deployer");

        assertProvingNetworkInfo(
            ProofManagerStorage.ProvingNetwork.Fermah,
            ProofManagerStorage.ProvingNetworkInfo(
                fermah,
                ProofManagerStorage.ProvingNetworkStatus.Active,
                new ProofManager.ProofRequestIdentifier[](0),
                0
            )
        );
        assertProvingNetworkInfo(
            ProofManagerStorage.ProvingNetwork.Lagrange,
            ProofManagerStorage.ProvingNetworkInfo(
                lagrange,
                ProofManagerStorage.ProvingNetworkStatus.Active,
                new ProofManager.ProofRequestIdentifier[](0),
                0
            )
        );

        assertEq(
            uint8(proofManager.preferredNetwork()),
            uint8(ProofManagerStorage.ProvingNetwork.None),
            "preferred network should be None"
        );
    }

    /// @dev Happy path for constructor, checking events.
    function testConstructorEmitsEvents() public {
        vm.expectEmit(true, true, false, false);
        emit ProofManagerStorage.ProvingNetworkAddressChanged(
            ProofManagerStorage.ProvingNetwork.Fermah, fermah
        );
        vm.expectEmit(true, true, false, false);
        emit ProofManagerStorage.ProvingNetworkStatusChanged(
            ProofManagerStorage.ProvingNetwork.Fermah,
            ProofManagerStorage.ProvingNetworkStatus.Active
        );
        vm.expectEmit(true, true, false, false);
        emit ProofManagerStorage.ProvingNetworkAddressChanged(
            ProofManagerStorage.ProvingNetwork.Lagrange, lagrange
        );
        vm.expectEmit(true, true, false, false);
        emit ProofManagerStorage.ProvingNetworkStatusChanged(
            ProofManagerStorage.ProvingNetwork.Lagrange,
            ProofManagerStorage.ProvingNetworkStatus.Active
        );

        vm.expectEmit(true, false, false, false);
        emit ProofManagerStorage.PreferredNetworkSet(ProofManagerStorage.ProvingNetwork.None);
        new ProofManagerHarness(fermah, lagrange, address(usdc));
    }

    /// @dev Do not allow zero address for proving networks.
    function testInitFailsWithZeroProvingNetworkAddress() public {
        vm.expectRevert("proving network address cannot be zero");
        new ProofManager(address(0), lagrange, address(this));
        vm.expectRevert("proving network address cannot be zero");
        new ProofManager(fermah, address(0), address(this));
    }

    /// @dev Do not allow zero address for USDC contract.
    function testInitFailsWithZeroUSDCAddress() public {
        vm.expectRevert("usdc contract address cannot be zero");
        new ProofManager(fermah, lagrange, address(0));
    }
}

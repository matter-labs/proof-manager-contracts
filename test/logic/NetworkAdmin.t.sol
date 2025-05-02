// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "../Base.t.sol";

contract NetworkAdminTest is Base {
    /*//////////////////////////////////////////
            Change Proving Network Address
    //////////////////////////////////////////*/

    /// @dev Happy path for changing a proving network address.
    function testChangeProvingNetworkAddress() public {
        vm.expectEmit(true, true, false, true);
        emit ProofManagerStorage.ProvingNetworkAddressChanged(
            ProofManagerStorage.ProvingNetwork.Fermah, otherProvingNetwork
        );
        proofManager.changeProvingNetworkAddress(
            ProofManagerStorage.ProvingNetwork.Fermah, otherProvingNetwork
        );
        assertProvingNetworkInfo(
            ProofManagerStorage.ProvingNetwork.Fermah,
            ProofManagerStorage.ProvingNetworkInfo(
                otherProvingNetwork,
                ProofManagerStorage.ProvingNetworkStatus.Active,
                new ProofManager.ProofRequestIdentifier[](0),
                0
            )
        );
    }

    /// @dev Only owner can change proving network address.
    function testNonOwnerCannotChangeProvingNetworkAddress() public {
        vm.prank(nonOwner);
        expectOwnableRevert(nonOwner);
        proofManager.changeProvingNetworkAddress(
            ProofManagerStorage.ProvingNetwork.Fermah, otherProvingNetwork
        );
    }

    /// @dev Proving Network None is not a real network. As such, you can't add an address to it.
    function testCannotChangeProvingNetworkAddressForNone() public {
        vm.expectRevert("proving network cannot be None");
        proofManager.changeProvingNetworkAddress(
            ProofManagerStorage.ProvingNetwork.None, otherProvingNetwork
        );
    }

    /// @dev You can't set a proving network address to zero. This is a safety check.
    function testCannotChangeProvingNetworkAddressToZero() public {
        vm.expectRevert("cannot unset proving network address");
        proofManager.changeProvingNetworkAddress(
            ProofManagerStorage.ProvingNetwork.Fermah, address(0)
        );
    }

    /*////////////////////////
            Mark Network
    ////////////////////////*/

    /// @dev Happy path for marking a proving network.
    function testMarkNetwork() public {
        vm.expectEmit(true, true, false, true);
        emit ProofManagerStorage.ProvingNetworkStatusChanged(
            ProofManagerStorage.ProvingNetwork.Fermah,
            ProofManagerStorage.ProvingNetworkStatus.Inactive
        );
        proofManager.markNetwork(
            ProofManagerStorage.ProvingNetwork.Fermah,
            ProofManagerStorage.ProvingNetworkStatus.Inactive
        );
        assertProvingNetworkInfo(
            ProofManagerStorage.ProvingNetwork.Fermah,
            ProofManagerStorage.ProvingNetworkInfo(
                fermah,
                ProofManagerStorage.ProvingNetworkStatus.Inactive,
                new ProofManager.ProofRequestIdentifier[](0),
                0
            )
        );
    }

    /// @dev Only owner can mark a proving network.
    function testNonOwnerCannotMarkNetwork() public {
        vm.prank(nonOwner);
        expectOwnableRevert(nonOwner);
        proofManager.markNetwork(
            ProofManagerStorage.ProvingNetwork.Fermah,
            ProofManagerStorage.ProvingNetworkStatus.Inactive
        );
    }

    /// @dev Proving Network None is not a real network. As such, you can't mark it.
    function testCannotMarkNetworkForNone() public {
        vm.expectRevert("proving network cannot be None");
        proofManager.markNetwork(
            ProofManagerStorage.ProvingNetwork.None,
            ProofManagerStorage.ProvingNetworkStatus.Inactive
        );
    }

    /*/////////////////////////////////
            Set Preferred Network
    /////////////////////////////////*/

    /// @dev Happy path for setting the preferred network.
    function testSetPreferredNetwork() public {
        assertEq(
            uint8(proofManager.preferredNetwork()),
            uint8(ProofManagerStorage.ProvingNetwork.None),
            "preferred network should be None"
        );

        vm.expectEmit(true, true, false, true);
        emit ProofManagerStorage.PreferredNetworkSet(ProofManagerStorage.ProvingNetwork.Fermah);
        proofManager.setPreferredNetwork(ProofManagerStorage.ProvingNetwork.Fermah);
        assertEq(
            uint8(proofManager.preferredNetwork()),
            uint8(ProofManagerStorage.ProvingNetwork.Fermah),
            "preferred network should be Fermah"
        );
    }

    /// @dev Only owner can set the preferred network.
    function testNonOwnerCannotSetPreferredNetwork() public {
        vm.prank(nonOwner);
        expectOwnableRevert(nonOwner);
        proofManager.setPreferredNetwork(ProofManagerStorage.ProvingNetwork.Fermah);
    }
}

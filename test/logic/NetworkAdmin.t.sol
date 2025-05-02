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
        emit ProvingNetworkAddressChanged(ProvingNetwork.Fermah, otherProvingNetwork);
        vm.prank(owner);
        proofManager.updateProvingNetworkAddress(ProvingNetwork.Fermah, otherProvingNetwork);
        assertProvingNetworkInfo(
            ProvingNetwork.Fermah,
            ProofManagerStorage.ProvingNetworkInfo(
                otherProvingNetwork, ProvingNetworkStatus.Active, new ProofRequestIdentifier[](0), 0
            )
        );
    }

    /// @dev Only owner can change proving network address.
    function testNonOwnerCannotChangeProvingNetworkAddress() public {
        vm.prank(nonOwner);
        expectOwnableRevert(nonOwner);
        proofManager.updateProvingNetworkAddress(ProvingNetwork.Fermah, otherProvingNetwork);
    }

    /// @dev Proving Network None is not a real network. As such, you can't add an address to it.
    function testCannotChangeProvingNetworkAddressForNone() public {
        vm.expectRevert("proving network cannot be None");
        vm.prank(owner);
        proofManager.updateProvingNetworkAddress(ProvingNetwork.None, otherProvingNetwork);
    }

    /// @dev You can't set a proving network address to zero. This is a safety check.
    function testCannotChangeProvingNetworkAddressToZero() public {
        vm.expectRevert("cannot unset proving network address");
        vm.prank(owner);
        proofManager.updateProvingNetworkAddress(ProvingNetwork.Fermah, address(0));
    }

    /*////////////////////////
            Mark Network
    ////////////////////////*/

    /// @dev Happy path for marking a proving network.
    function testMarkNetwork() public {
        vm.expectEmit(true, true, false, true);
        emit ProvingNetworkStatusChanged(ProvingNetwork.Fermah, ProvingNetworkStatus.Inactive);
        vm.prank(owner);
        proofManager.updateProvingNetworkStatus(
            ProvingNetwork.Fermah, ProvingNetworkStatus.Inactive
        );
        assertProvingNetworkInfo(
            ProvingNetwork.Fermah,
            ProofManagerStorage.ProvingNetworkInfo(
                fermah, ProvingNetworkStatus.Inactive, new ProofRequestIdentifier[](0), 0
            )
        );
    }

    /// @dev Only owner can mark a proving network.
    function testNonOwnerCannotMarkNetwork() public {
        vm.prank(nonOwner);
        expectOwnableRevert(nonOwner);
        proofManager.updateProvingNetworkStatus(
            ProvingNetwork.Fermah, ProvingNetworkStatus.Inactive
        );
    }

    /// @dev Proving Network None is not a real network. As such, you can't mark it.
    function testCannotMarkNetworkForNone() public {
        vm.expectRevert("proving network cannot be None");
        vm.prank(owner);
        proofManager.updateProvingNetworkStatus(ProvingNetwork.None, ProvingNetworkStatus.Inactive);
    }

    /*/////////////////////////////////
            Set Preferred Network
    /////////////////////////////////*/

    /// @dev Happy path for setting the preferred network.
    function testSetPreferredNetwork() public {
        assertEq(
            uint8(proofManager.preferredNetwork()),
            uint8(ProvingNetwork.None),
            "preferred network should be None"
        );

        vm.expectEmit(true, true, false, true);
        emit PreferredNetworkSet(ProvingNetwork.Fermah);
        vm.prank(owner);
        proofManager.updatePreferredProvingNetwork(ProvingNetwork.Fermah);
        assertEq(
            uint8(proofManager.preferredNetwork()),
            uint8(ProvingNetwork.Fermah),
            "preferred network should be Fermah"
        );
    }

    /// @dev Only owner can set the preferred network.
    function testNonOwnerCannotSetPreferredNetwork() public {
        vm.prank(nonOwner);
        expectOwnableRevert(nonOwner);
        proofManager.updatePreferredProvingNetwork(ProvingNetwork.Fermah);
    }
}

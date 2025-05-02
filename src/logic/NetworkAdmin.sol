// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "../store/ProofManagerStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @author Matter Labs
/// @notice This contract is used for Proving Networks management.
abstract contract NetworkAdmin is ProofManagerStorage, Ownable {
    /*////////////////////////
            Modifiers
    ////////////////////////*/

    /// @dev None is an escape hatch (lack of Option<>) and should not be used in public API.
    modifier provingNetworkNotNone(ProvingNetwork provingNetwork) {
        require(provingNetwork != ProvingNetwork.None, "proving network cannot be None");
        _;
    }

    /*////////////////////////
            Public API
    ////////////////////////*/

    /// @dev Useful for key rotation or key compromise.
    function changeProvingNetworkAddress(ProvingNetwork provingNetwork, address addr)
        external
        onlyOwner
        provingNetworkNotNone(provingNetwork)
    {
        require(addr != address(0), "cannot unset proving network address");
        _provingNetworks[provingNetwork].addr = addr;
        emit ProvingNetworkAddressChanged(provingNetwork, addr);
    }

    /// @dev Useful for Proving Network outage (Active to Inactive) or recovery (Inactive to Active).
    function markNetwork(ProvingNetwork provingNetwork, ProvingNetworkStatus status)
        external
        onlyOwner
        provingNetworkNotNone(provingNetwork)
    {
        _provingNetworks[provingNetwork].status = status;
        emit ProvingNetworkStatusChanged(provingNetwork, status);
    }

    /// @dev Used once per month to direct more proofs to the network that scored best previous month.
    function setPreferredNetwork(ProvingNetwork provingNetwork) external onlyOwner {
        _preferredNetwork = provingNetwork;
        emit PreferredNetworkSet(provingNetwork);
    }
}

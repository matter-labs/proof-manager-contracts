// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "./store/ProofManagerStorage.sol";
import "./logic/RequestManager.sol";
import "./logic/NetworkAdmin.sol";
import "./logic/ProvingNetworkActions.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @author Matter Labs
/// @notice Entry point for Proof Manager.
contract ProofManager is
    ProofManagerStorage,
    RequestManager,
    NetworkAdmin,
    ProvingNetworkActions
{
    IERC20 public immutable USDC;

    /// @dev Constructor. Sets up the contract.
    constructor(address fermah, address lagrange, address usdc) Ownable(msg.sender) {
        require(
            fermah != address(0) && lagrange != address(0), "proving network address cannot be zero"
        );
        require(usdc != address(0), "usdc contract address cannot be zero");

        USDC = IERC20(usdc);

        initializeProvingNetwork(ProvingNetwork.Fermah, fermah);
        initializeProvingNetwork(ProvingNetwork.Lagrange, lagrange);

        _preferredNetwork = ProvingNetwork.None;
        emit PreferredNetworkSet(ProvingNetwork.None);
        _requestCounter = 0;
    }

    /*////////////////////////
            Helpers
    ////////////////////////*/

    /// @dev Initializes a proving network. Used in the constructor.
    function initializeProvingNetwork(ProvingNetwork provingNetwork, address addr)
        private
        onlyOwner
    {
        ProofManagerStorage.ProvingNetworkInfo storage info = _provingNetworks[provingNetwork];
        info.addr = addr;
        info.status = ProvingNetworkStatus.Active;
        delete info.unclaimedProofs;
        info.paymentDue = 0;

        emit ProvingNetworkAddressChanged(provingNetwork, addr);
        emit ProvingNetworkStatusChanged(provingNetwork, ProvingNetworkStatus.Active);
    }

    /// @dev Used as internal hook for ProvingNetworkActions.
    function _USDC() internal view override returns (IERC20) {
        return USDC;
    }

    /*////////////////////////
            Getters
    ////////////////////////*/

    /// @dev Getter for Proof Request.
    function proofRequest(uint256 chainId, uint256 blockNumber)
        external
        view
        returns (ProofRequest memory)
    {
        return _proofRequests[chainId][blockNumber];
    }

    /// @dev Getter for Proving Network Info.
    function provingNetworkInfo(ProvingNetwork provingNetwork)
        external
        view
        returns (ProvingNetworkInfo memory)
    {
        return _provingNetworks[provingNetwork];
    }

    /// @dev Getter for Preferred Proving Network.
    function preferredNetwork() external view returns (ProvingNetwork) {
        return _preferredNetwork;
    }
}

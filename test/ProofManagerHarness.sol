// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import { ProofManagerV1 } from "../../src/ProofManagerV1.sol";
import "../../src/interfaces/IProofManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Test‑only wrapper that bypasses internal checks for ease of testing.
contract ProofManagerV1Harness is ProofManagerV1 {
    /// @dev Changes status of a proof request, disregarding access rules.
    function forceSetProofRequestStatus(ProofRequestIdentifier memory id, ProofRequestStatus status)
        external
    {
        _proofRequests[id.chainId][id.blockNumber].status = status;
    }

    /// @dev Changes assignee of proof request, regardless of round robin.
    function forceSetProofRequestAssignee(ProofRequestIdentifier memory id, ProvingNetwork assignee)
        external
    {
        _proofRequests[id.chainId][id.blockNumber].assignedTo = assignee;
    }
}

/// @dev Mock USDC contract implementation.
contract MockUsdc is IERC20 {
    mapping(address => uint256) public balanceOf;
    string public constant name = "Mock USDC";
    uint8 public constant decimals = 6;

    /*////////////////////////
            Used
    ////////////////////////*/

    function transfer(address to, uint256 amt) external returns (bool) {
        balanceOf[msg.sender] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
    }

    /*/////////////////////////////////////////
            Implemented due to interface
    /////////////////////////////////////////*/

    /// @dev Not used, but required by interface.
    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }

    /// @dev Not used, but required by interface.
    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    /// @dev Not used, but required by interface.
    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    /// @dev Not used, but required by interface.
    function totalSupply() external pure returns (uint256) {
        return 0;
    }
}

/// @dev Broken USDC contract implementation -- fails on transfer.
contract BrokenUsdc is IERC20 {
    mapping(address => uint256) public balanceOf;
    string public constant name = "Broken USDC";
    uint8 public constant decimals = 6;

    /*////////////////////////
            Used
    ////////////////////////*/

    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
    }

    /*/////////////////////////////////////////
            Implemented due to interface
    /////////////////////////////////////////*/

    /// @dev Not used, but required by interface.
    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }

    /// @dev Not used, but required by interface.
    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    /// @dev Not used, but required by interface.
    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    /// @dev Not used, but required by interface.
    function totalSupply() external pure returns (uint256) {
        return 0;
    }
}

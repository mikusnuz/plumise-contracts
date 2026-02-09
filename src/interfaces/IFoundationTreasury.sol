// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IFoundationTreasury
 * @notice Interface for FoundationTreasury contract
 */
interface IFoundationTreasury {
    /**
     * @notice Emitted when tokens are released
     * @param amount Amount released
     */
    event Released(uint256 amount);

    /**
     * @notice Emitted when PLM is received
     * @param from Sender address
     * @param amount Amount received
     */
    event Received(address indexed from, uint256 amount);

    /**
     * @notice Release vested tokens to owner
     */
    function release() external;

    /**
     * @notice Get total vested amount at current timestamp
     * @return Amount that has vested
     */
    function vestedAmount() external view returns (uint256);

    /**
     * @notice Get releasable amount (vested - released)
     * @return Amount that can be released now
     */
    function releasableAmount() external view returns (uint256);
}

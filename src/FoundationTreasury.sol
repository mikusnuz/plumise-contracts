// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IFoundationTreasury.sol";

/**
 * @title FoundationTreasury
 * @notice Manages foundation funds with 6-month cliff + 36-month linear vesting
 * @dev Total allocation: 47,712,000 PLM
 */
contract FoundationTreasury is IFoundationTreasury, Ownable, ReentrancyGuard {
    /// @notice Total PLM allocated to foundation
    uint256 public totalAllocation;

    /// @notice Vesting start timestamp (set in genesis)
    uint256 public startTimestamp;

    /// @notice Amount already released
    uint256 public released;

    /// @notice Cliff duration (6 months = 180 days)
    uint256 public constant CLIFF_DURATION = 180 days;

    /// @notice Vesting duration (36 months = 1080 days)
    uint256 public constant VESTING_DURATION = 1080 days;

    /**
     * @notice Constructor
     * @dev In genesis deployment, state variables are set directly via storage slots
     */
    constructor() Ownable(msg.sender) {
        // These will be overridden by genesis storage slots
        totalAllocation = 47_712_000 ether;
        startTimestamp = block.timestamp;
        released = 0;
    }

    /**
     * @notice Release vested tokens to owner
     */
    function release() external override onlyOwner nonReentrant {
        uint256 releasable = releasableAmount();
        require(releasable > 0, "No tokens to release");

        released += releasable;

        (bool success, ) = owner().call{value: releasable}("");
        require(success, "Transfer failed");

        emit Released(releasable);
    }

    /**
     * @notice Get total vested amount at current timestamp
     * @return Amount that has vested
     */
    function vestedAmount() public view override returns (uint256) {
        return _vestedAmount(block.timestamp);
    }

    /**
     * @notice Get releasable amount (vested - released)
     * @return Amount that can be released now
     */
    function releasableAmount() public view override returns (uint256) {
        return vestedAmount() - released;
    }

    /**
     * @notice Calculate vested amount at a given timestamp
     * @param timestamp Time to check
     * @return Vested amount
     */
    function _vestedAmount(uint256 timestamp) internal view returns (uint256) {
        if (timestamp < startTimestamp + CLIFF_DURATION) {
            // Before cliff ends
            return 0;
        } else if (timestamp >= startTimestamp + CLIFF_DURATION + VESTING_DURATION) {
            // After vesting completes (42 months total)
            return totalAllocation;
        } else {
            // Linear vesting after cliff
            uint256 elapsedSinceCliff = timestamp - (startTimestamp + CLIFF_DURATION);
            return (totalAllocation * elapsedSinceCliff) / VESTING_DURATION;
        }
    }

    /**
     * @notice Receive PLM (for genesis allocation)
     */
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}

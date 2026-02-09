// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/ILiquidityDeployer.sol";

/**
 * @title LiquidityDeployer
 * @notice Manages liquidity deployment funds for DEX
 * @dev Total allocation: 31,808,000 PLM (immediately available)
 */
contract LiquidityDeployer is ILiquidityDeployer, Ownable, ReentrancyGuard {
    /// @notice Total PLM allocated for liquidity
    uint256 public totalAllocation;

    /**
     * @notice Constructor
     * @dev In genesis deployment, state variables are set directly via storage slots
     */
    constructor() Ownable(msg.sender) {
        totalAllocation = 31_808_000 ether;
    }

    /**
     * @notice Transfer funds for liquidity provision
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function transfer(address to, uint256 amount) external override onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be positive");
        require(address(this).balance >= amount, "Insufficient balance");

        (bool success,) = to.call{value: amount}("");
        require(success, "Transfer failed");

        emit Transfer(to, amount);
    }

    /**
     * @notice Get remaining balance
     * @return Current balance
     */
    function getBalance() external view override returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Receive PLM (for genesis allocation)
     */
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}

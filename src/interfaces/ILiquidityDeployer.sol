// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title ILiquidityDeployer
 * @notice Interface for LiquidityDeployer contract
 */
interface ILiquidityDeployer {
    /**
     * @notice Emitted when funds are transferred
     * @param to Recipient address
     * @param amount Amount transferred
     */
    event Transfer(address indexed to, uint256 amount);

    /**
     * @notice Emitted when PLM is received
     * @param from Sender address
     * @param amount Amount received
     */
    event Received(address indexed from, uint256 amount);

    /**
     * @notice Transfer funds for liquidity provision
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function transfer(address to, uint256 amount) external;

    /**
     * @notice Get remaining balance
     * @return Current balance
     */
    function getBalance() external view returns (uint256);
}

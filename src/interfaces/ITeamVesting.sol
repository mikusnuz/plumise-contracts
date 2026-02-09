// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title ITeamVesting
 * @notice Interface for TeamVesting contract
 */
interface ITeamVesting {
    /**
     * @notice Beneficiary data structure
     * @param allocation Total allocation for beneficiary
     * @param released Amount already released
     */
    struct Beneficiary {
        uint256 allocation;
        uint256 released;
    }

    /**
     * @notice Emitted when a beneficiary is added
     * @param beneficiary Beneficiary address
     * @param allocation Amount allocated
     */
    event BeneficiaryAdded(address indexed beneficiary, uint256 allocation);

    /**
     * @notice Emitted when a beneficiary is removed
     * @param beneficiary Beneficiary address
     * @param unreleased Amount not yet released
     */
    event BeneficiaryRemoved(address indexed beneficiary, uint256 unreleased);

    /**
     * @notice Emitted when tokens are released
     * @param beneficiary Beneficiary address
     * @param amount Amount released
     */
    event Released(address indexed beneficiary, uint256 amount);

    /**
     * @notice Emitted when PLM is received
     * @param from Sender address
     * @param amount Amount received
     */
    event Received(address indexed from, uint256 amount);

    /**
     * @notice Add a beneficiary
     * @param beneficiary Beneficiary address
     * @param allocation Amount allocated to beneficiary
     */
    function addBeneficiary(address beneficiary, uint256 allocation) external;

    /**
     * @notice Remove a beneficiary
     * @param beneficiary Beneficiary address
     */
    function removeBeneficiary(address beneficiary) external;

    /**
     * @notice Release vested tokens to a beneficiary
     * @param beneficiary Beneficiary address
     */
    function release(address beneficiary) external;

    /**
     * @notice Get vested amount for a beneficiary
     * @param beneficiary Beneficiary address
     * @return Amount vested
     */
    function vestedAmount(address beneficiary) external view returns (uint256);

    /**
     * @notice Get releasable amount for a beneficiary
     * @param beneficiary Beneficiary address
     * @return Amount that can be released now
     */
    function releasableAmount(address beneficiary) external view returns (uint256);

    /**
     * @notice Get number of beneficiaries
     * @return Number of beneficiaries
     */
    function getBeneficiaryCount() external view returns (uint256);

    /**
     * @notice Get beneficiary at index
     * @param index Index in beneficiaryList
     * @return Beneficiary address
     */
    function getBeneficiaryAt(uint256 index) external view returns (address);

    /**
     * @notice Get beneficiary data
     * @param beneficiary Beneficiary address
     * @return Beneficiary data
     */
    function getBeneficiary(address beneficiary) external view returns (Beneficiary memory);
}

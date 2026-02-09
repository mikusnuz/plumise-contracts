// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/ITeamVesting.sol";

/**
 * @title TeamVesting
 * @notice Manages team token vesting with 12-month cliff + 36-month linear vesting
 * @dev Total allocation: 23,856,000 PLM
 */
contract TeamVesting is ITeamVesting, Ownable, ReentrancyGuard {
    /// @notice Total PLM allocated to team
    uint256 public totalAllocation;

    /// @notice Vesting start timestamp (set in genesis)
    uint256 public startTimestamp;

    /// @notice Cliff duration (12 months = 365 days)
    uint256 public constant CLIFF_DURATION = 365 days;

    /// @notice Vesting duration (36 months = 1095 days)
    uint256 public constant VESTING_DURATION = 1095 days;

    /// @notice Beneficiary data
    mapping(address => Beneficiary) public beneficiaries;

    /// @notice List of all beneficiary addresses
    address[] public beneficiaryList;

    /// @notice Track if address is a beneficiary
    mapping(address => bool) public isBeneficiary;

    /// @notice Total allocated to all beneficiaries
    uint256 public totalAllocated;

    /**
     * @notice Constructor
     * @dev In genesis deployment, state variables are set directly via storage slots
     */
    constructor() Ownable(msg.sender) {
        totalAllocation = 23_856_000 ether;
        startTimestamp = block.timestamp;
        totalAllocated = 0;
    }

    /**
     * @notice Add a beneficiary
     * @param beneficiary Beneficiary address
     * @param allocation Amount allocated to beneficiary
     */
    function addBeneficiary(
        address beneficiary,
        uint256 allocation
    ) external override onlyOwner {
        require(beneficiary != address(0), "Invalid beneficiary");
        require(allocation > 0, "Allocation must be positive");
        require(!isBeneficiary[beneficiary], "Already a beneficiary");
        require(totalAllocated + allocation <= totalAllocation, "Exceeds total allocation");

        beneficiaries[beneficiary] = Beneficiary({
            allocation: allocation,
            released: 0
        });

        beneficiaryList.push(beneficiary);
        isBeneficiary[beneficiary] = true;
        totalAllocated += allocation;

        emit BeneficiaryAdded(beneficiary, allocation);
    }

    /**
     * @notice Remove a beneficiary (unreleased tokens returned to fund)
     * @param beneficiary Beneficiary address
     */
    function removeBeneficiary(address beneficiary) external override onlyOwner {
        require(isBeneficiary[beneficiary], "Not a beneficiary");

        Beneficiary memory b = beneficiaries[beneficiary];
        uint256 unreleased = b.allocation - b.released;

        delete beneficiaries[beneficiary];
        isBeneficiary[beneficiary] = false;
        totalAllocated -= b.allocation;

        // Remove from list (swap with last element)
        for (uint256 i = 0; i < beneficiaryList.length; i++) {
            if (beneficiaryList[i] == beneficiary) {
                beneficiaryList[i] = beneficiaryList[beneficiaryList.length - 1];
                beneficiaryList.pop();
                break;
            }
        }

        emit BeneficiaryRemoved(beneficiary, unreleased);
    }

    /**
     * @notice Release vested tokens to a beneficiary
     * @param beneficiary Beneficiary address
     */
    function release(address beneficiary) external override nonReentrant {
        require(isBeneficiary[beneficiary], "Not a beneficiary");

        uint256 releasable = releasableAmount(beneficiary);
        require(releasable > 0, "No tokens to release");

        beneficiaries[beneficiary].released += releasable;

        (bool success, ) = beneficiary.call{value: releasable}("");
        require(success, "Transfer failed");

        emit Released(beneficiary, releasable);
    }

    /**
     * @notice Get vested amount for a beneficiary
     * @param beneficiary Beneficiary address
     * @return Amount vested
     */
    function vestedAmount(address beneficiary) public view override returns (uint256) {
        if (!isBeneficiary[beneficiary]) {
            return 0;
        }

        return _vestedAmount(beneficiaries[beneficiary].allocation, block.timestamp);
    }

    /**
     * @notice Get releasable amount for a beneficiary
     * @param beneficiary Beneficiary address
     * @return Amount that can be released now
     */
    function releasableAmount(address beneficiary) public view override returns (uint256) {
        if (!isBeneficiary[beneficiary]) {
            return 0;
        }

        uint256 vested = vestedAmount(beneficiary);
        return vested - beneficiaries[beneficiary].released;
    }

    /**
     * @notice Calculate vested amount at a given timestamp
     * @param allocation Total allocation for beneficiary
     * @param timestamp Time to check
     * @return Vested amount
     */
    function _vestedAmount(uint256 allocation, uint256 timestamp) internal view returns (uint256) {
        if (timestamp < startTimestamp + CLIFF_DURATION) {
            // Before cliff ends
            return 0;
        } else if (timestamp >= startTimestamp + CLIFF_DURATION + VESTING_DURATION) {
            // After vesting completes (48 months total)
            return allocation;
        } else {
            // Linear vesting after cliff
            uint256 elapsedSinceCliff = timestamp - (startTimestamp + CLIFF_DURATION);
            return (allocation * elapsedSinceCliff) / VESTING_DURATION;
        }
    }

    /**
     * @notice Get number of beneficiaries
     * @return Number of beneficiaries
     */
    function getBeneficiaryCount() external view override returns (uint256) {
        return beneficiaryList.length;
    }

    /**
     * @notice Get beneficiary at index
     * @param index Index in beneficiaryList
     * @return Beneficiary address
     */
    function getBeneficiaryAt(uint256 index) external view override returns (address) {
        require(index < beneficiaryList.length, "Index out of bounds");
        return beneficiaryList[index];
    }

    /**
     * @notice Get beneficiary data
     * @param beneficiary Beneficiary address
     * @return Beneficiary data
     */
    function getBeneficiary(address beneficiary) external view override returns (Beneficiary memory) {
        require(isBeneficiary[beneficiary], "Not a beneficiary");
        return beneficiaries[beneficiary];
    }

    /**
     * @notice Receive PLM (for genesis allocation)
     */
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}

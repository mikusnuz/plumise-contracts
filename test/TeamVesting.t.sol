// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/TeamVesting.sol";

contract TeamVestingTest is Test {
    TeamVesting public vesting;
    address public owner;
    address public beneficiary1;
    address public beneficiary2;

    uint256 constant TOTAL_ALLOCATION = 23_856_000 ether;
    uint256 constant CLIFF_DURATION = 365 days;
    uint256 constant VESTING_DURATION = 1095 days;

    function setUp() public {
        owner = address(this);
        beneficiary1 = address(0x1);
        beneficiary2 = address(0x2);

        vesting = new TeamVesting();
        vm.deal(address(vesting), TOTAL_ALLOCATION);
    }

    function testInitialState() public view {
        assertEq(vesting.totalAllocation(), TOTAL_ALLOCATION);
        assertEq(vesting.totalAllocated(), 0);
        assertEq(vesting.owner(), owner);
        assertEq(vesting.getBeneficiaryCount(), 0);
    }

    function testAddBeneficiary() public {
        uint256 allocation = 1_000_000 ether;

        vesting.addBeneficiary(beneficiary1, allocation);

        assertTrue(vesting.isBeneficiary(beneficiary1));
        assertEq(vesting.getBeneficiaryCount(), 1);
        assertEq(vesting.getBeneficiaryAt(0), beneficiary1);
        assertEq(vesting.totalAllocated(), allocation);

        ITeamVesting.Beneficiary memory b = vesting.getBeneficiary(beneficiary1);
        assertEq(b.allocation, allocation);
        assertEq(b.released, 0);
    }

    function testAddMultipleBeneficiaries() public {
        vesting.addBeneficiary(beneficiary1, 1_000_000 ether);
        vesting.addBeneficiary(beneficiary2, 2_000_000 ether);

        assertEq(vesting.getBeneficiaryCount(), 2);
        assertEq(vesting.totalAllocated(), 3_000_000 ether);
    }

    function testAddBeneficiaryRevertsInvalidAddress() public {
        vm.expectRevert("Invalid beneficiary");
        vesting.addBeneficiary(address(0), 1_000_000 ether);
    }

    function testAddBeneficiaryRevertsZeroAllocation() public {
        vm.expectRevert("Allocation must be positive");
        vesting.addBeneficiary(beneficiary1, 0);
    }

    function testAddBeneficiaryRevertsAlreadyExists() public {
        vesting.addBeneficiary(beneficiary1, 1_000_000 ether);

        vm.expectRevert("Already a beneficiary");
        vesting.addBeneficiary(beneficiary1, 1_000_000 ether);
    }

    function testAddBeneficiaryRevertsExceedsTotal() public {
        vm.expectRevert("Exceeds total allocation");
        vesting.addBeneficiary(beneficiary1, TOTAL_ALLOCATION + 1);
    }

    function testRemoveBeneficiary() public {
        vesting.addBeneficiary(beneficiary1, 1_000_000 ether);
        vesting.addBeneficiary(beneficiary2, 2_000_000 ether);

        vesting.removeBeneficiary(beneficiary1);

        assertFalse(vesting.isBeneficiary(beneficiary1));
        assertEq(vesting.getBeneficiaryCount(), 1);
        assertEq(vesting.totalAllocated(), 2_000_000 ether);
    }

    function testRemoveBeneficiaryRevertsNotBeneficiary() public {
        vm.expectRevert("Not a beneficiary");
        vesting.removeBeneficiary(beneficiary1);
    }

    function testVestedAmountBeforeCliff() public {
        vesting.addBeneficiary(beneficiary1, 1_000_000 ether);

        assertEq(vesting.vestedAmount(beneficiary1), 0);
        assertEq(vesting.releasableAmount(beneficiary1), 0);

        vm.warp(block.timestamp + CLIFF_DURATION - 1 days);
        assertEq(vesting.vestedAmount(beneficiary1), 0);
    }

    function testVestedAmountMidVesting() public {
        uint256 allocation = 1_000_000 ether;
        vesting.addBeneficiary(beneficiary1, allocation);

        // 50% of vesting period after cliff
        vm.warp(block.timestamp + CLIFF_DURATION + (VESTING_DURATION / 2));

        uint256 expectedVested = allocation / 2;
        assertEq(vesting.vestedAmount(beneficiary1), expectedVested);
        assertEq(vesting.releasableAmount(beneficiary1), expectedVested);
    }

    function testVestedAmountAfterVesting() public {
        uint256 allocation = 1_000_000 ether;
        vesting.addBeneficiary(beneficiary1, allocation);

        vm.warp(block.timestamp + CLIFF_DURATION + VESTING_DURATION);

        assertEq(vesting.vestedAmount(beneficiary1), allocation);
        assertEq(vesting.releasableAmount(beneficiary1), allocation);
    }

    function testRelease() public {
        uint256 allocation = 1_000_000 ether;
        vesting.addBeneficiary(beneficiary1, allocation);

        vm.warp(block.timestamp + CLIFF_DURATION + (VESTING_DURATION / 2));

        uint256 expectedRelease = allocation / 2;
        uint256 balanceBefore = beneficiary1.balance;

        vesting.release(beneficiary1);

        assertEq(beneficiary1.balance, balanceBefore + expectedRelease);

        ITeamVesting.Beneficiary memory b = vesting.getBeneficiary(beneficiary1);
        assertEq(b.released, expectedRelease);
        assertEq(vesting.releasableAmount(beneficiary1), 0);
    }

    function testReleaseMultipleTimes() public {
        uint256 allocation = 1_000_000 ether;
        vesting.addBeneficiary(beneficiary1, allocation);

        uint256 startTime = block.timestamp;

        // Release at 25% of vesting (after cliff)
        vm.warp(startTime + CLIFF_DURATION + (VESTING_DURATION / 4));
        vesting.release(beneficiary1);
        uint256 firstRelease = vesting.getBeneficiary(beneficiary1).released;

        // Release at 75% of vesting (after cliff)
        vm.warp(startTime + CLIFF_DURATION + (3 * VESTING_DURATION / 4));
        vesting.release(beneficiary1);
        uint256 secondRelease = vesting.getBeneficiary(beneficiary1).released;

        assertGt(secondRelease, firstRelease);
        assertApproxEqAbs(secondRelease, (3 * allocation) / 4, 1 ether);
    }

    function testReleaseRevertsNotBeneficiary() public {
        vm.expectRevert("Not a beneficiary");
        vesting.release(beneficiary1);
    }

    function testReleaseRevertsNoTokens() public {
        vesting.addBeneficiary(beneficiary1, 1_000_000 ether);

        vm.expectRevert("No tokens to release");
        vesting.release(beneficiary1);
    }

    function testReleaseCanBeCalledByAnyone() public {
        uint256 allocation = 1_000_000 ether;
        vesting.addBeneficiary(beneficiary1, allocation);

        vm.warp(block.timestamp + CLIFF_DURATION + VESTING_DURATION);

        // Called by beneficiary2
        vm.prank(beneficiary2);
        vesting.release(beneficiary1);

        assertEq(beneficiary1.balance, allocation);
    }

    function testVestedAmountForNonBeneficiary() public view {
        assertEq(vesting.vestedAmount(beneficiary1), 0);
        assertEq(vesting.releasableAmount(beneficiary1), 0);
    }

    function testGetBeneficiaryAtRevertsOutOfBounds() public {
        vm.expectRevert("Index out of bounds");
        vesting.getBeneficiaryAt(0);
    }

    function testGetBeneficiaryRevertsNotBeneficiary() public {
        vm.expectRevert("Not a beneficiary");
        vesting.getBeneficiary(beneficiary1);
    }

    function testReceive() public {
        uint256 amount = 1 ether;

        vm.deal(beneficiary1, amount);
        vm.prank(beneficiary1);
        (bool success, ) = address(vesting).call{value: amount}("");
        assertTrue(success);

        assertEq(address(vesting).balance, TOTAL_ALLOCATION + amount);
    }

    function testFuzzVesting(uint256 timeElapsed, uint256 allocation) public {
        allocation = bound(allocation, 1 ether, TOTAL_ALLOCATION);
        timeElapsed = bound(timeElapsed, 0, CLIFF_DURATION + VESTING_DURATION + 365 days);

        vesting.addBeneficiary(beneficiary1, allocation);

        vm.warp(block.timestamp + timeElapsed);

        uint256 vested = vesting.vestedAmount(beneficiary1);

        if (timeElapsed < CLIFF_DURATION) {
            assertEq(vested, 0);
        } else if (timeElapsed >= CLIFF_DURATION + VESTING_DURATION) {
            assertEq(vested, allocation);
        } else {
            uint256 elapsedSinceCliff = timeElapsed - CLIFF_DURATION;
            uint256 expectedVested = (allocation * elapsedSinceCliff) / VESTING_DURATION;
            assertEq(vested, expectedVested);
        }
    }
}

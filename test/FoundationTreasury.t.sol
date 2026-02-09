// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/FoundationTreasury.sol";

contract FoundationTreasuryTest is Test {
    FoundationTreasury public treasury;
    address public owner;
    address public other;

    // Add receive function to accept PLM
    receive() external payable {}

    uint256 constant TOTAL_ALLOCATION = 47_712_000 ether;
    uint256 constant CLIFF_DURATION = 180 days;
    uint256 constant VESTING_DURATION = 1080 days;

    function setUp() public {
        owner = address(this);
        other = address(0x1);

        treasury = new FoundationTreasury();

        // Fund the contract
        vm.deal(address(treasury), TOTAL_ALLOCATION);
    }

    function testInitialState() public view {
        assertEq(treasury.totalAllocation(), TOTAL_ALLOCATION);
        assertEq(treasury.released(), 0);
        assertEq(treasury.owner(), owner);
        assertEq(address(treasury).balance, TOTAL_ALLOCATION);
    }

    function testVestedAmountBeforeCliff() public {
        // Before cliff, nothing vested
        assertEq(treasury.vestedAmount(), 0);
        assertEq(treasury.releasableAmount(), 0);

        // Fast forward to 1 day before cliff
        vm.warp(block.timestamp + CLIFF_DURATION - 1 days);
        assertEq(treasury.vestedAmount(), 0);
        assertEq(treasury.releasableAmount(), 0);
    }

    function testVestedAmountAtCliff() public {
        // At cliff, nothing vested yet (linear vesting starts after cliff)
        vm.warp(block.timestamp + CLIFF_DURATION);
        assertEq(treasury.vestedAmount(), 0);
        assertEq(treasury.releasableAmount(), 0);
    }

    function testVestedAmountMidVesting() public {
        // 6 months after cliff (50% of vesting duration)
        vm.warp(block.timestamp + CLIFF_DURATION + (VESTING_DURATION / 2));

        uint256 expectedVested = TOTAL_ALLOCATION / 2;
        assertEq(treasury.vestedAmount(), expectedVested);
        assertEq(treasury.releasableAmount(), expectedVested);
    }

    function testVestedAmountAfterVesting() public {
        // After full vesting period (42 months)
        vm.warp(block.timestamp + CLIFF_DURATION + VESTING_DURATION);

        assertEq(treasury.vestedAmount(), TOTAL_ALLOCATION);
        assertEq(treasury.releasableAmount(), TOTAL_ALLOCATION);
    }

    function testRelease() public {
        // Fast forward to 50% vesting
        vm.warp(block.timestamp + CLIFF_DURATION + (VESTING_DURATION / 2));

        uint256 expectedRelease = TOTAL_ALLOCATION / 2;
        uint256 balanceBefore = owner.balance;

        treasury.release();

        assertEq(treasury.released(), expectedRelease);
        assertEq(owner.balance, balanceBefore + expectedRelease);
        assertEq(treasury.releasableAmount(), 0);
    }

    function testReleaseMultipleTimes() public {
        uint256 startTime = block.timestamp;

        // Release at 25% of vesting (after cliff)
        vm.warp(startTime + CLIFF_DURATION + (VESTING_DURATION / 4));
        treasury.release();
        uint256 firstRelease = treasury.released();

        // Release at 50% of vesting (after cliff)
        vm.warp(startTime + CLIFF_DURATION + (VESTING_DURATION / 2));
        treasury.release();
        uint256 secondRelease = treasury.released();

        assertGt(secondRelease, firstRelease);
        assertEq(secondRelease, TOTAL_ALLOCATION / 2);
    }

    function testReleaseRevertsWhenNoTokens() public {
        vm.expectRevert("No tokens to release");
        treasury.release();
    }

    function testReleaseRevertsNonOwner() public {
        vm.warp(block.timestamp + CLIFF_DURATION + VESTING_DURATION);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", other));
        treasury.release();
    }

    function testReceive() public {
        uint256 amount = 1 ether;

        vm.deal(other, amount);
        vm.prank(other);
        (bool success, ) = address(treasury).call{value: amount}("");
        assertTrue(success);

        assertEq(address(treasury).balance, TOTAL_ALLOCATION + amount);
    }

    function testFuzzVesting(uint256 timeElapsed) public {
        // Bound time to reasonable range
        timeElapsed = bound(timeElapsed, 0, CLIFF_DURATION + VESTING_DURATION + 365 days);

        vm.warp(block.timestamp + timeElapsed);

        uint256 vested = treasury.vestedAmount();

        if (timeElapsed < CLIFF_DURATION) {
            assertEq(vested, 0);
        } else if (timeElapsed >= CLIFF_DURATION + VESTING_DURATION) {
            assertEq(vested, TOTAL_ALLOCATION);
        } else {
            uint256 elapsedSinceCliff = timeElapsed - CLIFF_DURATION;
            uint256 expectedVested = (TOTAL_ALLOCATION * elapsedSinceCliff) / VESTING_DURATION;
            assertEq(vested, expectedVested);
        }
    }
}

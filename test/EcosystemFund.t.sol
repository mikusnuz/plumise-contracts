// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/EcosystemFund.sol";

contract EcosystemFundTest is Test {
    EcosystemFund public fund;
    address public owner;
    address public recipient1;
    address public recipient2;

    uint256 constant TOTAL_ALLOCATION = 55_664_000 ether;
    uint256 constant RATE_LIMIT_PERCENT = 5;
    uint256 constant MAX_TRANSFER = (TOTAL_ALLOCATION * RATE_LIMIT_PERCENT) / 100;
    uint256 constant TIMELOCK_DURATION = 24 hours;

    function setUp() public {
        owner = address(this);
        recipient1 = address(0x1);
        recipient2 = address(0x2);

        fund = new EcosystemFund();
        vm.deal(address(fund), TOTAL_ALLOCATION);
    }

    function testInitialState() public view {
        assertEq(fund.totalAllocation(), TOTAL_ALLOCATION);
        assertEq(fund.getBalance(), TOTAL_ALLOCATION);
        assertEq(fund.owner(), owner);
        assertEq(fund.emergencyMode(), false);
        assertEq(fund.lastTransferTimestamp(), 0);
    }

    function testTransferSuccess() public {
        uint256 amount = 1_000_000 ether;
        assertTrue(amount <= MAX_TRANSFER);

        uint256 balanceBefore = recipient1.balance;

        fund.transfer(recipient1, amount);

        assertEq(recipient1.balance, balanceBefore + amount);
        assertEq(fund.getBalance(), TOTAL_ALLOCATION - amount);
        assertEq(fund.lastTransferTimestamp(), block.timestamp);
    }

    function testTransferRevertsExceedsRateLimit() public {
        uint256 amount = MAX_TRANSFER + 1;

        vm.expectRevert("Exceeds rate limit");
        fund.transfer(recipient1, amount);
    }

    function testTransferRevertsTimelock() public {
        fund.transfer(recipient1, 1_000_000 ether);

        vm.expectRevert("Timelock active");
        fund.transfer(recipient2, 1_000_000 ether);
    }

    function testTransferAfterTimelockExpires() public {
        fund.transfer(recipient1, 1_000_000 ether);

        vm.warp(block.timestamp + TIMELOCK_DURATION);

        fund.transfer(recipient2, 1_000_000 ether);
        assertEq(recipient2.balance, 1_000_000 ether);
    }

    function testTransferRevertsInvalidRecipient() public {
        vm.expectRevert("Invalid recipient");
        fund.transfer(address(0), 1_000_000 ether);
    }

    function testTransferRevertsZeroAmount() public {
        vm.expectRevert("Amount must be positive");
        fund.transfer(recipient1, 0);
    }

    function testTransferRevertsInsufficientBalance() public {
        uint256 balance = fund.getBalance();

        vm.expectRevert("Insufficient balance");
        fund.transfer(recipient1, balance + 1);
    }

    function testTransferBatchSuccess() public {
        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 500_000 ether;
        amounts[1] = 500_000 ether;

        fund.transferBatch(recipients, amounts);

        assertEq(recipient1.balance, 500_000 ether);
        assertEq(recipient2.balance, 500_000 ether);
    }

    function testTransferBatchRevertsLengthMismatch() public {
        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500_000 ether;

        vm.expectRevert("Length mismatch");
        fund.transferBatch(recipients, amounts);
    }

    function testTransferBatchRevertsEmptyArrays() public {
        address[] memory recipients = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.expectRevert("Empty arrays");
        fund.transferBatch(recipients, amounts);
    }

    function testTransferBatchRevertsExceedsRateLimit() public {
        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = MAX_TRANSFER / 2 + 1;
        amounts[1] = MAX_TRANSFER / 2 + 1;

        vm.expectRevert("Exceeds rate limit");
        fund.transferBatch(recipients, amounts);
    }

    function testEmergencyModeBypassesRateLimit() public {
        fund.setEmergencyMode(true);

        uint256 largeAmount = MAX_TRANSFER + 1_000_000 ether;

        fund.transfer(recipient1, largeAmount);
        assertEq(recipient1.balance, largeAmount);
    }

    function testEmergencyModeBypassesTimelock() public {
        fund.transfer(recipient1, 1_000_000 ether);

        fund.setEmergencyMode(true);

        // Should not revert despite timelock
        fund.transfer(recipient2, 1_000_000 ether);
        assertEq(recipient2.balance, 1_000_000 ether);
    }

    function testSetEmergencyMode() public {
        fund.setEmergencyMode(true);
        assertTrue(fund.emergencyMode());

        fund.setEmergencyMode(false);
        assertFalse(fund.emergencyMode());
    }

    function testSetEmergencyModeRevertsNonOwner() public {
        vm.prank(recipient1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", recipient1));
        fund.setEmergencyMode(true);
    }

    function testGetTimeUntilUnlock() public {
        // Initially 0
        assertEq(fund.getTimeUntilUnlock(), 0);

        fund.transfer(recipient1, 1_000_000 ether);

        // Should be TIMELOCK_DURATION
        assertEq(fund.getTimeUntilUnlock(), TIMELOCK_DURATION);

        vm.warp(block.timestamp + 12 hours);
        assertEq(fund.getTimeUntilUnlock(), 12 hours);

        vm.warp(block.timestamp + TIMELOCK_DURATION);
        assertEq(fund.getTimeUntilUnlock(), 0);
    }

    function testGetTimeUntilUnlockInEmergencyMode() public {
        fund.transfer(recipient1, 1_000_000 ether);

        fund.setEmergencyMode(true);
        assertEq(fund.getTimeUntilUnlock(), 0);
    }

    function testReceive() public {
        uint256 amount = 1 ether;

        vm.deal(recipient1, amount);
        vm.prank(recipient1);
        (bool success,) = address(fund).call{value: amount}("");
        assertTrue(success);

        assertEq(fund.getBalance(), TOTAL_ALLOCATION + amount);
    }

    function testFuzzTransfer(uint256 amount) public {
        amount = bound(amount, 1, MAX_TRANSFER);

        fund.transfer(recipient1, amount);
        assertEq(recipient1.balance, amount);
    }
}

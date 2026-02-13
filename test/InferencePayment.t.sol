// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/InferencePayment.sol";

/**
 * @title InferencePaymentTest
 * @notice Test suite for InferencePayment contract
 */
contract InferencePaymentTest is Test {
    InferencePayment public payment;

    address public owner;
    address public gateway;
    address public treasury;
    address public user1;
    address public user2;

    event Deposited(address indexed user, uint256 amount, uint256 newBalance);
    event CreditUsed(address indexed user, uint256 tokens, uint256 cost);
    event Withdrawn(address indexed user, uint256 amount);
    event TierChanged(address indexed user, uint256 oldTier, uint256 newTier);
    event GatewayUpdated(address indexed oldGateway, address indexed newGateway);
    event CostUpdated(uint256 oldCost, uint256 newCost);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    function setUp() public {
        owner = address(this);
        gateway = makeAddr("gateway");
        treasury = makeAddr("treasury");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy payment contract
        payment = new InferencePayment(gateway, treasury);

        // Fund users
        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);
    }

    function test_Constructor() public view {
        assertEq(payment.gateway(), gateway);
        assertEq(payment.treasury(), treasury);
        assertEq(payment.costPer1000Tokens(), 0.001 ether);
        assertEq(payment.PRO_TIER_MINIMUM(), 100 ether);
    }

    function test_Deposit() public {
        vm.startPrank(user1);

        uint256 depositAmount = 50 ether;

        vm.expectEmit(true, true, true, true);
        emit Deposited(user1, depositAmount, depositAmount);

        payment.deposit{value: depositAmount}();

        assertEq(payment.getUserBalance(user1), depositAmount);
        assertEq(payment.getUserTier(user1), 0); // Still Free tier

        vm.stopPrank();
    }

    function test_Deposit_AutoUpgradeToProTier() public {
        vm.startPrank(user1);

        uint256 depositAmount = 150 ether;

        vm.expectEmit(true, true, true, true);
        emit TierChanged(user1, 0, 1);

        vm.expectEmit(true, true, true, true);
        emit Deposited(user1, depositAmount, depositAmount);

        payment.deposit{value: depositAmount}();

        assertEq(payment.getUserBalance(user1), depositAmount);
        assertEq(payment.getUserTier(user1), 1); // Pro tier
        assertTrue(payment.isProTier(user1));

        vm.stopPrank();
    }

    function test_Deposit_ZeroAmount() public {
        vm.startPrank(user1);

        vm.expectRevert("Zero deposit");
        payment.deposit{value: 0}();

        vm.stopPrank();
    }

    function test_UseCredits() public {
        // User deposits
        vm.prank(user1);
        payment.deposit{value: 10 ether}();

        // Gateway uses credits
        uint256 tokenCount = 1000; // 1000 tokens
        uint256 expectedCost = (tokenCount * payment.costPer1000Tokens()) / 1000; // 0.001 ether

        vm.startPrank(gateway);

        uint256 treasuryBalanceBefore = treasury.balance;

        vm.expectEmit(true, true, true, true);
        emit CreditUsed(user1, tokenCount, expectedCost);

        payment.useCredits(user1, tokenCount);

        assertEq(payment.getUserBalance(user1), 10 ether - expectedCost);
        assertEq(treasury.balance, treasuryBalanceBefore + expectedCost);

        vm.stopPrank();
    }

    function test_UseCredits_OnlyGateway() public {
        vm.startPrank(user1);
        payment.deposit{value: 10 ether}();

        vm.expectRevert("Only gateway");
        payment.useCredits(user1, 1000);

        vm.stopPrank();
    }

    function test_UseCredits_InsufficientBalance() public {
        vm.prank(user1);
        payment.deposit{value: 0.0005 ether}(); // Not enough for 1000 tokens

        vm.startPrank(gateway);

        vm.expectRevert("Insufficient balance");
        payment.useCredits(user1, 1000);

        vm.stopPrank();
    }

    function test_UseCredits_ZeroTokens() public {
        vm.prank(user1);
        payment.deposit{value: 10 ether}();

        vm.startPrank(gateway);

        vm.expectRevert("Zero tokens");
        payment.useCredits(user1, 0);

        vm.stopPrank();
    }

    function test_UseCredits_TierDowngrade() public {
        // User deposits to become Pro
        vm.prank(user1);
        payment.deposit{value: 100 ether}();

        assertTrue(payment.isProTier(user1));

        // Use credits until balance drops below Pro minimum
        uint256 tokensToUse = 50_000_000; // 50M tokens = 50 ether cost
        // Balance after: 100 - 50 = 50 ether (< 100 ether Pro minimum)

        vm.startPrank(gateway);

        vm.expectEmit(true, true, true, true);
        emit TierChanged(user1, 1, 0);

        payment.useCredits(user1, tokensToUse);

        assertEq(payment.getUserTier(user1), 0); // Downgraded to Free
        assertFalse(payment.isProTier(user1));

        vm.stopPrank();
    }

    function test_Withdraw() public {
        // User deposits
        vm.startPrank(user1);
        payment.deposit{value: 50 ether}();

        uint256 withdrawAmount = 20 ether;
        uint256 balanceBefore = user1.balance;

        vm.expectEmit(true, true, true, true);
        emit Withdrawn(user1, withdrawAmount);

        payment.withdraw(withdrawAmount);

        assertEq(payment.getUserBalance(user1), 30 ether);
        assertEq(user1.balance, balanceBefore + withdrawAmount);

        vm.stopPrank();
    }

    function test_Withdraw_InsufficientBalance() public {
        vm.startPrank(user1);
        payment.deposit{value: 10 ether}();

        vm.expectRevert("Insufficient balance");
        payment.withdraw(20 ether);

        vm.stopPrank();
    }

    function test_Withdraw_ZeroAmount() public {
        vm.startPrank(user1);
        payment.deposit{value: 10 ether}();

        vm.expectRevert("Zero amount");
        payment.withdraw(0);

        vm.stopPrank();
    }

    function test_Withdraw_TierDowngrade() public {
        // User deposits to become Pro
        vm.startPrank(user1);
        payment.deposit{value: 150 ether}();

        assertTrue(payment.isProTier(user1));

        // Withdraw to drop below Pro minimum
        vm.expectEmit(true, true, true, true);
        emit TierChanged(user1, 1, 0);

        payment.withdraw(100 ether); // Balance becomes 50 ether

        assertEq(payment.getUserTier(user1), 0);
        assertFalse(payment.isProTier(user1));

        vm.stopPrank();
    }

    function test_SetGateway() public {
        address newGateway = makeAddr("newGateway");

        vm.expectEmit(true, true, true, true);
        emit GatewayUpdated(gateway, newGateway);

        payment.setGateway(newGateway);

        assertEq(payment.gateway(), newGateway);
    }

    function test_SetGateway_InvalidAddress() public {
        vm.expectRevert("Invalid gateway");
        payment.setGateway(address(0));
    }

    function test_SetGateway_OnlyOwner() public {
        address newGateway = makeAddr("newGateway");

        vm.startPrank(user1);
        vm.expectRevert();
        payment.setGateway(newGateway);
        vm.stopPrank();
    }

    function test_SetCostPer1000Tokens() public {
        uint256 newCost = 0.002 ether;

        vm.expectEmit(true, true, true, true);
        emit CostUpdated(0.001 ether, newCost);

        payment.setCostPer1000Tokens(newCost);

        assertEq(payment.costPer1000Tokens(), newCost);
    }

    function test_SetCostPer1000Tokens_InvalidCost() public {
        vm.expectRevert("Cost too low");
        payment.setCostPer1000Tokens(0);
    }

    function test_SetCostPer1000Tokens_OnlyOwner() public {
        vm.startPrank(user1);
        vm.expectRevert();
        payment.setCostPer1000Tokens(0.002 ether);
        vm.stopPrank();
    }

    function test_SetTreasury() public {
        address newTreasury = makeAddr("newTreasury");

        vm.expectEmit(true, true, true, true);
        emit TreasuryUpdated(treasury, newTreasury);

        payment.setTreasury(newTreasury);

        assertEq(payment.treasury(), newTreasury);
    }

    function test_SetTreasury_InvalidAddress() public {
        vm.expectRevert("Invalid treasury");
        payment.setTreasury(address(0));
    }

    function test_SetTreasury_OnlyOwner() public {
        address newTreasury = makeAddr("newTreasury");

        vm.startPrank(user1);
        vm.expectRevert();
        payment.setTreasury(newTreasury);
        vm.stopPrank();
    }

    function test_GetUserCredit() public {
        vm.prank(user1);
        payment.deposit{value: 150 ether}();

        IInferencePayment.UserCredit memory credit = payment.getUserCredit(user1);

        assertEq(credit.balance, 150 ether);
        assertEq(credit.usedCredits, 0);
        assertEq(credit.tier, 1);
        assertEq(credit.lastDeposit, block.timestamp);
    }

    function test_ComplexScenario() public {
        // User1 deposits and becomes Pro
        vm.prank(user1);
        payment.deposit{value: 200 ether}();

        assertTrue(payment.isProTier(user1));

        // User2 deposits but stays Free
        vm.prank(user2);
        payment.deposit{value: 50 ether}();

        assertFalse(payment.isProTier(user2));

        // Gateway uses credits for both users
        vm.startPrank(gateway);

        payment.useCredits(user1, 50_000); // 0.05 ether
        payment.useCredits(user2, 10_000); // 0.01 ether

        vm.stopPrank();

        assertEq(payment.getUserBalance(user1), 199.95 ether);
        assertEq(payment.getUserBalance(user2), 49.99 ether);

        // User1 withdraws some
        vm.prank(user1);
        payment.withdraw(100 ether);

        // User1 still Pro (balance = 99.95 ether < 100, so downgraded)
        assertFalse(payment.isProTier(user1));
    }

    function testFuzz_Deposit(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000 ether);

        vm.prank(user1);
        payment.deposit{value: amount}();

        assertEq(payment.getUserBalance(user1), amount);

        if (amount >= payment.PRO_TIER_MINIMUM()) {
            assertTrue(payment.isProTier(user1));
        } else {
            assertFalse(payment.isProTier(user1));
        }
    }

    function testFuzz_UseCredits(uint256 depositAmount, uint256 tokenCount) public {
        depositAmount = bound(depositAmount, 1 ether, 1000 ether);

        vm.prank(user1);
        payment.deposit{value: depositAmount}();

        uint256 maxTokens = (depositAmount * 1000) / payment.costPer1000Tokens();
        tokenCount = bound(tokenCount, 1, maxTokens);

        uint256 expectedCost = (tokenCount * payment.costPer1000Tokens()) / 1000;

        vm.prank(gateway);
        payment.useCredits(user1, tokenCount);

        assertEq(payment.getUserBalance(user1), depositAmount - expectedCost);
    }

    // ========== CT-02: Extended Fuzz Tests ==========

    /**
     * @notice Fuzz test: Zero token payment should revert
     */
    function testFuzz_ZeroTokenPayment() public {
        vm.prank(user1);
        payment.deposit{value: 10 ether}();

        vm.startPrank(gateway);
        vm.expectRevert("Zero tokens");
        payment.useCredits(user1, 0);
        vm.stopPrank();
    }

    /**
     * @notice Fuzz test: Overflow attempt in token cost calculation
     * @dev Tests extreme token counts to ensure no overflow
     */
    function testFuzz_TokenCostOverflowAttempt(uint256 tokenCount) public {
        // Bound to reasonable but large values
        tokenCount = bound(tokenCount, 1, type(uint128).max);

        uint256 depositAmount = 100000 ether; // Very large deposit
        vm.deal(user1, depositAmount);

        vm.prank(user1);
        payment.deposit{value: depositAmount}();

        // Calculate expected cost (should not overflow)
        uint256 expectedCost = (tokenCount * payment.costPer1000Tokens()) / 1000;

        if (expectedCost <= depositAmount) {
            vm.prank(gateway);
            payment.useCredits(user1, tokenCount);

            assertEq(payment.getUserBalance(user1), depositAmount - expectedCost);
        } else {
            vm.startPrank(gateway);
            vm.expectRevert("Insufficient balance");
            payment.useCredits(user1, tokenCount);
            vm.stopPrank();
        }
    }

    /**
     * @notice Fuzz test: Tier transition boundaries
     * @dev Tests automatic tier upgrades and downgrades at various thresholds
     */
    function testFuzz_TierTransitionBoundaries(uint256 depositAmount, uint256 withdrawAmount) public {
        uint256 proMinimum = payment.PRO_TIER_MINIMUM();

        depositAmount = bound(depositAmount, 1 ether, 1000 ether);
        vm.deal(user1, depositAmount);

        vm.prank(user1);
        payment.deposit{value: depositAmount}();

        // Check initial tier
        bool shouldBePro = depositAmount >= proMinimum;
        assertEq(payment.isProTier(user1), shouldBePro, "Initial tier incorrect");

        // Try to withdraw
        if (depositAmount > 0) {
            withdrawAmount = bound(withdrawAmount, 1, depositAmount);

            vm.prank(user1);
            payment.withdraw(withdrawAmount);

            uint256 remainingBalance = depositAmount - withdrawAmount;
            bool shouldBeProAfter = remainingBalance >= proMinimum;

            assertEq(payment.isProTier(user1), shouldBeProAfter, "Tier after withdrawal incorrect");
            assertEq(payment.getUserBalance(user1), remainingBalance, "Balance after withdrawal incorrect");
        }
    }

    /**
     * @notice Fuzz test: Multiple deposits accumulation
     * @dev Tests that multiple deposits correctly accumulate and handle tier transitions
     */
    function testFuzz_MultipleDeposits(uint256 deposit1, uint256 deposit2, uint256 deposit3) public {
        deposit1 = bound(deposit1, 0.01 ether, 50 ether);
        deposit2 = bound(deposit2, 0.01 ether, 50 ether);
        deposit3 = bound(deposit3, 0.01 ether, 50 ether);

        uint256 totalDeposit = deposit1 + deposit2 + deposit3;
        vm.deal(user1, totalDeposit);

        vm.startPrank(user1);

        payment.deposit{value: deposit1}();
        uint256 balance1 = payment.getUserBalance(user1);
        assertEq(balance1, deposit1);

        payment.deposit{value: deposit2}();
        uint256 balance2 = payment.getUserBalance(user1);
        assertEq(balance2, deposit1 + deposit2);

        payment.deposit{value: deposit3}();
        uint256 balance3 = payment.getUserBalance(user1);
        assertEq(balance3, totalDeposit);

        vm.stopPrank();

        // Final tier should match total
        bool shouldBePro = totalDeposit >= payment.PRO_TIER_MINIMUM();
        assertEq(payment.isProTier(user1), shouldBePro);
    }

    /**
     * @notice Fuzz test: Credit usage exactly at balance
     * @dev Tests using credits when balance exactly equals cost (edge case)
     */
    function testFuzz_ExactBalanceUsage(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 0.001 ether, 10 ether);

        vm.prank(user1);
        payment.deposit{value: depositAmount}();

        // Calculate token count that exactly depletes balance
        uint256 tokenCount = (depositAmount * 1000) / payment.costPer1000Tokens();
        uint256 exactCost = (tokenCount * payment.costPer1000Tokens()) / 1000;

        vm.prank(gateway);
        payment.useCredits(user1, tokenCount);

        // Balance should be deposit minus exact cost (may have dust due to rounding)
        uint256 remainingBalance = payment.getUserBalance(user1);
        assertLe(remainingBalance, depositAmount - exactCost);
    }

    /**
     * @notice Fuzz test: Withdrawal at exact balance
     */
    function testFuzz_WithdrawExactBalance(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1 ether, 100 ether);

        vm.startPrank(user1);
        payment.deposit{value: depositAmount}();

        uint256 balanceBefore = user1.balance;

        payment.withdraw(depositAmount);

        assertEq(payment.getUserBalance(user1), 0, "Balance should be zero after full withdrawal");
        assertEq(user1.balance, balanceBefore + depositAmount, "User should receive full deposit back");
        assertEq(payment.getUserTier(user1), 0, "Tier should be Free after full withdrawal");

        vm.stopPrank();
    }

    receive() external payable {}
}

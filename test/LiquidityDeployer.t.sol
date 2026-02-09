// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/LiquidityDeployer.sol";

contract LiquidityDeployerTest is Test {
    LiquidityDeployer public deployer;
    address public owner;
    address public recipient;
    address public router;
    address public token;

    uint256 constant TOTAL_ALLOCATION = 31_808_000 ether;

    function setUp() public {
        owner = address(this);
        recipient = address(0x1);
        router = address(0x2);
        token = address(0x3);

        deployer = new LiquidityDeployer();
        vm.deal(address(deployer), TOTAL_ALLOCATION);
    }

    function testInitialState() public view {
        assertEq(deployer.totalAllocation(), TOTAL_ALLOCATION);
        assertEq(deployer.getBalance(), TOTAL_ALLOCATION);
        assertEq(deployer.owner(), owner);
    }

    function testTransferSuccess() public {
        uint256 amount = 1_000_000 ether;
        uint256 balanceBefore = recipient.balance;

        deployer.transfer(recipient, amount);

        assertEq(recipient.balance, balanceBefore + amount);
        assertEq(deployer.getBalance(), TOTAL_ALLOCATION - amount);
    }

    function testTransferMultipleTimes() public {
        deployer.transfer(recipient, 1_000_000 ether);
        deployer.transfer(recipient, 2_000_000 ether);

        assertEq(recipient.balance, 3_000_000 ether);
    }

    function testTransferRevertsInvalidRecipient() public {
        vm.expectRevert("Invalid recipient");
        deployer.transfer(address(0), 1_000_000 ether);
    }

    function testTransferRevertsZeroAmount() public {
        vm.expectRevert("Amount must be positive");
        deployer.transfer(recipient, 0);
    }

    function testTransferRevertsInsufficientBalance() public {
        uint256 balance = deployer.getBalance();

        vm.expectRevert("Insufficient balance");
        deployer.transfer(recipient, balance + 1);
    }

    function testTransferRevertsNonOwner() public {
        vm.prank(recipient);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", recipient));
        deployer.transfer(recipient, 1_000_000 ether);
    }

    function testWrapAndAddLiquidity() public {
        uint256 plmAmount = 1_000_000 ether;
        uint256 tokenAmount = 500_000 ether;

        deployer.wrapAndAddLiquidity(router, token, plmAmount, tokenAmount);
    }

    function testWrapAndAddLiquidityRevertsInvalidRouter() public {
        vm.expectRevert("Invalid router");
        deployer.wrapAndAddLiquidity(address(0), token, 1_000_000 ether, 500_000 ether);
    }

    function testWrapAndAddLiquidityRevertsInvalidToken() public {
        vm.expectRevert("Invalid token");
        deployer.wrapAndAddLiquidity(router, address(0), 1_000_000 ether, 500_000 ether);
    }

    function testWrapAndAddLiquidityRevertsZeroPLM() public {
        vm.expectRevert("PLM amount must be positive");
        deployer.wrapAndAddLiquidity(router, token, 0, 500_000 ether);
    }

    function testWrapAndAddLiquidityRevertsZeroToken() public {
        vm.expectRevert("Token amount must be positive");
        deployer.wrapAndAddLiquidity(router, token, 1_000_000 ether, 0);
    }

    function testWrapAndAddLiquidityRevertsInsufficientBalance() public {
        uint256 balance = deployer.getBalance();

        vm.expectRevert("Insufficient PLM balance");
        deployer.wrapAndAddLiquidity(router, token, balance + 1, 500_000 ether);
    }

    function testWrapAndAddLiquidityRevertsNonOwner() public {
        vm.prank(recipient);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", recipient));
        deployer.wrapAndAddLiquidity(router, token, 1_000_000 ether, 500_000 ether);
    }

    function testGetBalance() public view {
        assertEq(deployer.getBalance(), TOTAL_ALLOCATION);
    }

    function testGetBalanceAfterTransfer() public {
        deployer.transfer(recipient, 1_000_000 ether);
        assertEq(deployer.getBalance(), TOTAL_ALLOCATION - 1_000_000 ether);
    }

    function testReceive() public {
        uint256 amount = 1 ether;

        vm.deal(recipient, amount);
        vm.prank(recipient);
        (bool success, ) = address(deployer).call{value: amount}("");
        assertTrue(success);

        assertEq(deployer.getBalance(), TOTAL_ALLOCATION + amount);
    }

    function testFuzzTransfer(uint256 amount) public {
        amount = bound(amount, 1, TOTAL_ALLOCATION);

        deployer.transfer(recipient, amount);
        assertEq(recipient.balance, amount);
    }

    function testFuzzWrapAndAddLiquidity(uint256 plmAmount, uint256 tokenAmount) public {
        plmAmount = bound(plmAmount, 1 ether, TOTAL_ALLOCATION);
        tokenAmount = bound(tokenAmount, 1 ether, type(uint128).max);

        deployer.wrapAndAddLiquidity(router, token, plmAmount, tokenAmount);
    }
}

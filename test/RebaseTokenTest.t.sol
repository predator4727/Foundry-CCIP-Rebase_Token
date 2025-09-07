//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { Test, console } from "forge-std/Test.sol";

import { RebaseToken } from "../src/RebaseToken.sol";
import { Vault } from "../src/Vault.sol";

import { IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

import { Ownable } from "@openzeppelin/access/Ownable.sol";
import { IAccessControl }  from "@openzeppelin/access/AccessControl.sol";


contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    uint256 public SEND_VALUE = 1e5;

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        payable(address(vault)).call{value: rewardAmount}("");
    }

    function testDepositLinear(uint256 amount) public {
        // vm.assume(amount > SEND_VALUE);
        amount = bound(amount, SEND_VALUE, type(uint96).max);
        // 1. Deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        // 2. check our rebase token balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("startBalance: ", startBalance);
        assertEq(startBalance, amount);
        // 3. warp the time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        console.log("middleBalance: ", middleBalance);
        assertGt(middleBalance, startBalance);
        // 4. warp the time again by the same amount and check balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 finalBalance = rebaseToken.balanceOf(user);
        console.log("finalBalance: ", finalBalance);
        assertGt(finalBalance, middleBalance);

        assertApproxEqAbs(finalBalance - middleBalance, middleBalance - startBalance, 1);
        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, SEND_VALUE, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        // deposit
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);
        // redeem
        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(address(user).balance, amount);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max); // maximum time of 2.5 * 10 ^21 years!
        depositAmount = bound(depositAmount, SEND_VALUE, type(uint96).max);
        vm.deal(user, depositAmount);
        vm.prank(user);
        // deposit
        vault.deposit{value: depositAmount}();
        // warp the time
        vm.warp(block.timestamp + time);
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user);
        // add rewards to the vault
        vm.deal(owner, balanceAfterSomeTime - depositAmount); // if we have 1 ETH:1 rebase token model
        vm.prank(owner);
        addRewardsToVault(balanceAfterSomeTime - depositAmount);
        // redeem
        vm.prank(user);
        vault.redeem(type(uint256).max);

        uint256 ethBalance = address(user).balance;
        assertEq(ethBalance, balanceAfterSomeTime);
        assertGt(ethBalance, depositAmount);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        address user2 = makeAddr("user2");

        amount = bound(amount, SEND_VALUE + SEND_VALUE, type(uint96).max);
        amountToSend = bound(amountToSend, SEND_VALUE, amount - SEND_VALUE);

        // 1. deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        assertEq(userBalance, amount);
        assertEq(user2Balance, 0);

        // owner reduces the interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // transfer
        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);

        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);

        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(user2BalanceAfterTransfer, user2Balance + amountToSend);

        // check the user interest rate has been inherited (5e10 not 4e10)
        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);
    }

    function testCannotSetInterestRate(uint256 _newInterestRate) public {
        vm.prank(user);
        vm.expectPartialRevert(bytes4(Ownable.OwnableUnauthorizedAccount.selector));
        rebaseToken.setInterestRate(_newInterestRate);
    }

    function testCannotCallMintAndBurn(uint256 amount) public {
        vm.prank(user);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.mint(user, amount, rebaseToken.getInterestRate());

        vm.prank(user);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.burn(user, amount);
    }

    function testPrincipleBalance(uint256 amount) public {
        amount = bound(amount, SEND_VALUE, type(uint96).max);
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.getPrincipleBalance(user), amount);

        vm.warp(block.timestamp + 1 hours);
        assertEq(rebaseToken.getPrincipleBalance(user), amount);
    }

    function testRebaseTokenAddress() public view{
        assertEq(address(rebaseToken), vault.getRebaseTokenAddress());
    }

    function testIncreaseInterestRate(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);
        vm.prank(owner);
        vm.expectPartialRevert(bytes4(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector));
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }

    function testSetInterestRate(uint256 newInterestRate) public {
        newInterestRate = bound(newInterestRate, 0, rebaseToken.getInterestRate() - 1);
        vm.startPrank(owner);
        rebaseToken.setInterestRate(newInterestRate);
        vm.stopPrank();
        assertEq(rebaseToken.getInterestRate(), newInterestRate);

        vm.deal(user, SEND_VALUE);
        vm.startPrank(user);
        vault.deposit{value: SEND_VALUE}();
        vm.stopPrank();
        assertEq(rebaseToken.getUserInterestRate(user), newInterestRate);
    }

    function testTransferFrom(uint256 amount, uint256 amountToSend) public {
        address user2 = makeAddr("user2");

        amount = bound(amount, SEND_VALUE + SEND_VALUE, type(uint96).max);
        amountToSend = bound(amountToSend, SEND_VALUE, amount - SEND_VALUE);

        // 1. deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        assertEq(userBalance, amount);
        assertEq(user2Balance, 0);

        // owner reduces the interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // transfer
        vm.startPrank(user);
        rebaseToken.approve(user, amountToSend);
        rebaseToken.transferFrom(user, user2, amountToSend);
        vm.stopPrank();

        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);

        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(user2BalanceAfterTransfer, user2Balance + amountToSend);

        // check the user interest rate has been inherited (5e10 not 4e10)
        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);
    }


}
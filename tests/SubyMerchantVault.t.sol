// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Test } from 'forge-std/Test.sol';

import { SubyMerchantVault } from '../src/SubyMerchantVault.sol';
import { SubyMerchantVaultFactory } from '../src/SubyMerchantVaultFactory.sol';
import { MockERC20 } from './mocks/MockERC20.sol';

contract SubyMerchantVaultTest is Test {
    SubyMerchantVaultFactory factory;
    SubyMerchantVault vault;
    MockERC20 usdc;
    MockERC20 eurc;
    MockERC20 randomToken;

    address owner = makeAddr('owner');
    address operator = makeAddr('operator');
    address feeWallet = makeAddr('feeWallet');
    address merchant = makeAddr('merchant');
    address payoutDst = makeAddr('payoutDst');
    address attacker = makeAddr('attacker');

    bytes32 constant REASON_DEBT = keccak256('debt:debt_001');
    bytes32 constant REASON_RR = keccak256('rr:rrh_001');

    function setUp() public {
        usdc = new MockERC20('USDC', 'USDC', 6);
        eurc = new MockERC20('EURC', 'EURC', 6);
        randomToken = new MockERC20('Random', 'RND', 18);

        factory = new SubyMerchantVaultFactory(owner, operator, feeWallet, address(usdc), address(eurc));

        vm.prank(operator);
        vault = SubyMerchantVault(factory.deployVault(keccak256('org_test'), merchant));
    }

    // --------------- balance / withdrawable ---------------

    function test_balanceTracks_plainTransfer() public {
        usdc.mint(address(vault), 500e6);
        assertEq(vault.balanceOf(address(usdc)), 500e6);
        assertEq(vault.availableToWithdraw(address(usdc)), 500e6);
        assertEq(vault.withdrawable(address(usdc)), int256(500e6));
    }

    function test_withdrawable_signedNegative_whenHeldExceedsBalance() public {
        usdc.mint(address(vault), 100e6);

        vm.prank(operator);
        vault.hold(address(usdc), 300e6, REASON_DEBT);

        assertEq(vault.availableToWithdraw(address(usdc)), 0);
        assertEq(vault.withdrawable(address(usdc)), -int256(200e6));
    }

    // --------------- hold ---------------

    function test_hold_onlyOperator() public {
        vm.prank(attacker);
        vm.expectRevert(SubyMerchantVault.NotOperator.selector);
        vault.hold(address(usdc), 1e6, REASON_RR);
    }

    function test_hold_rejectsUnsupportedToken() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SubyMerchantVault.UnsupportedToken.selector, address(randomToken)));
        vault.hold(address(randomToken), 1e6, REASON_RR);
    }

    function test_hold_rejectsZero() public {
        vm.prank(operator);
        vm.expectRevert(SubyMerchantVault.ZeroAmount.selector);
        vault.hold(address(usdc), 0, REASON_RR);
    }

    function test_hold_accumulates() public {
        vm.startPrank(operator);
        vault.hold(address(usdc), 100e6, REASON_RR);
        vault.hold(address(usdc), 50e6, REASON_DEBT);
        vm.stopPrank();

        assertEq(vault.holdOf(address(usdc)), 150e6);
    }

    // --------------- release ---------------

    function test_release_decrementsHold() public {
        vm.startPrank(operator);
        vault.hold(address(usdc), 200e6, REASON_RR);
        vault.release(address(usdc), 80e6, REASON_RR);
        vm.stopPrank();

        assertEq(vault.holdOf(address(usdc)), 120e6);
    }

    function test_release_revertsAboveHeld() public {
        vm.prank(operator);
        vault.hold(address(usdc), 50e6, REASON_RR);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SubyMerchantVault.ExceedsHeld.selector, 60e6, 50e6));
        vault.release(address(usdc), 60e6, REASON_RR);
    }

    function test_release_onlyOperator() public {
        vm.prank(operator);
        vault.hold(address(usdc), 100e6, REASON_RR);

        vm.prank(attacker);
        vm.expectRevert(SubyMerchantVault.NotOperator.selector);
        vault.release(address(usdc), 10e6, REASON_RR);
    }

    // --------------- clawback ---------------

    function test_clawback_transfersToFeeWalletAndReducesHold() public {
        usdc.mint(address(vault), 200e6);

        vm.startPrank(operator);
        vault.hold(address(usdc), 150e6, REASON_DEBT);
        vault.clawback(address(usdc), 100e6, REASON_DEBT);
        vm.stopPrank();

        assertEq(usdc.balanceOf(feeWallet), 100e6);
        assertEq(vault.balanceOf(address(usdc)), 100e6);
        assertEq(vault.holdOf(address(usdc)), 50e6);
    }

    function test_clawback_burnsHeldUpToAmount_whenAmountExceedsHeld() public {
        usdc.mint(address(vault), 300e6);
        vm.startPrank(operator);
        vault.hold(address(usdc), 80e6, REASON_DEBT);
        vault.clawback(address(usdc), 150e6, REASON_DEBT);
        vm.stopPrank();

        assertEq(usdc.balanceOf(feeWallet), 150e6);
        assertEq(vault.holdOf(address(usdc)), 0, 'held should be burned to 0, not under-flowed');
        assertEq(vault.balanceOf(address(usdc)), 150e6);
    }

    function test_clawback_worksWithoutPriorHold() public {
        usdc.mint(address(vault), 100e6);

        vm.prank(operator);
        vault.clawback(address(usdc), 40e6, REASON_DEBT);

        assertEq(usdc.balanceOf(feeWallet), 40e6);
        assertEq(vault.balanceOf(address(usdc)), 60e6);
        assertEq(vault.holdOf(address(usdc)), 0);
    }

    function test_clawback_followsRotatedFeeWallet() public {
        usdc.mint(address(vault), 100e6);

        address newFw = makeAddr('newFw');
        vm.prank(owner);
        factory.setFeeWallet(newFw);

        vm.prank(operator);
        vault.clawback(address(usdc), 30e6, REASON_DEBT);

        assertEq(usdc.balanceOf(newFw), 30e6);
        assertEq(usdc.balanceOf(feeWallet), 0);
    }

    function test_clawback_onlyOperator() public {
        usdc.mint(address(vault), 100e6);
        vm.prank(attacker);
        vm.expectRevert(SubyMerchantVault.NotOperator.selector);
        vault.clawback(address(usdc), 10e6, REASON_DEBT);
    }

    // --------------- withdraw ---------------

    function test_withdraw_byMerchant() public {
        usdc.mint(address(vault), 200e6);

        vm.prank(merchant);
        vault.withdraw(address(usdc), payoutDst, 120e6);

        assertEq(usdc.balanceOf(payoutDst), 120e6);
        assertEq(vault.balanceOf(address(usdc)), 80e6);
    }

    function test_withdraw_rejectsOverAvailable() public {
        usdc.mint(address(vault), 200e6);
        vm.prank(operator);
        vault.hold(address(usdc), 150e6, REASON_RR);

        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(SubyMerchantVault.InsufficientWithdrawable.selector, 60e6, 50e6));
        vault.withdraw(address(usdc), payoutDst, 60e6);

        // exact bound succeeds
        vm.prank(merchant);
        vault.withdraw(address(usdc), payoutDst, 50e6);
        assertEq(usdc.balanceOf(payoutDst), 50e6);
    }

    function test_withdraw_onlyMerchant() public {
        usdc.mint(address(vault), 100e6);
        vm.prank(attacker);
        vm.expectRevert(SubyMerchantVault.NotMerchant.selector);
        vault.withdraw(address(usdc), attacker, 10e6);

        vm.prank(operator);
        vm.expectRevert(SubyMerchantVault.NotMerchant.selector);
        vault.withdraw(address(usdc), payoutDst, 10e6);
    }

    function test_withdraw_rejectsUnsupportedToken() public {
        randomToken.mint(address(vault), 100e18);
        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(SubyMerchantVault.UnsupportedToken.selector, address(randomToken)));
        vault.withdraw(address(randomToken), payoutDst, 1e18);
    }

    // --------------- rescue ---------------

    function test_rescue_sweepsUnsupportedToken() public {
        randomToken.mint(address(vault), 5e18);

        vm.prank(operator);
        vault.rescue(address(randomToken), payoutDst, 5e18);

        assertEq(randomToken.balanceOf(payoutDst), 5e18);
        assertEq(randomToken.balanceOf(address(vault)), 0);
    }

    function test_rescue_rejectsSupportedToken() public {
        usdc.mint(address(vault), 100e6);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SubyMerchantVault.CannotRescueSupported.selector, address(usdc)));
        vault.rescue(address(usdc), payoutDst, 1e6);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SubyMerchantVault.CannotRescueSupported.selector, address(eurc)));
        vault.rescue(address(eurc), payoutDst, 1e6);
    }

    function test_rescue_onlyOperator() public {
        randomToken.mint(address(vault), 1e18);
        vm.prank(attacker);
        vm.expectRevert(SubyMerchantVault.NotOperator.selector);
        vault.rescue(address(randomToken), attacker, 1e18);

        vm.prank(merchant);
        vm.expectRevert(SubyMerchantVault.NotOperator.selector);
        vault.rescue(address(randomToken), payoutDst, 1e18);
    }

    function test_eurc_alsoSupported() public {
        eurc.mint(address(vault), 50e6);
        vm.prank(operator);
        vault.hold(address(eurc), 20e6, REASON_DEBT);

        vm.prank(merchant);
        vault.withdraw(address(eurc), payoutDst, 30e6);

        assertEq(eurc.balanceOf(payoutDst), 30e6);
        assertEq(vault.holdOf(address(eurc)), 20e6);
    }
}

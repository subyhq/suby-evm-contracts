// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Test } from 'forge-std/Test.sol';

import { SubyPayment } from '../src/SubyPayment.sol';
import { SubyRelayer } from '../src/SubyRelayer.sol';
import { ISubyPayment } from '../src/interfaces/ISubyPayment.sol';
import { MockERC20 } from './mocks/MockERC20.sol';

contract SubyRelayerTest is Test {
    SubyPayment subyPayment;
    SubyRelayer relayer;
    MockERC20 usdc;

    address owner = makeAddr('owner');
    address operator = makeAddr('operator');
    address attacker = makeAddr('attacker');

    address merchant = makeAddr('merchant');
    address feeWallet = makeAddr('feeWallet');
    address referrer = makeAddr('referrer');

    function setUp() public {
        usdc = new MockERC20('USDC', 'USDC', 6);
        subyPayment = new SubyPayment();
        relayer = new SubyRelayer(owner, operator, address(subyPayment));
    }

    function _split(
        uint256 mAmt,
        uint256 fAmt,
        uint256 rAmt
    )
        internal
        view
        returns (ISubyPayment.RecipientAndAmount[] memory s)
    {
        s = new ISubyPayment.RecipientAndAmount[](3);
        s[0] = ISubyPayment.RecipientAndAmount({ recipient: merchant, amount: mAmt });
        s[1] = ISubyPayment.RecipientAndAmount({ recipient: feeWallet, amount: fAmt });
        s[2] = ISubyPayment.RecipientAndAmount({ recipient: referrer, amount: rAmt });
    }

    function test_constructor_setsConfig() public view {
        assertEq(relayer.owner(), owner);
        assertEq(relayer.operator(), operator);
        assertEq(address(relayer.subyPayment()), address(subyPayment));
    }

    function test_executePayment_byOperator_distributesFunds() public {
        usdc.mint(address(relayer), 1000e6);

        vm.prank(operator);
        relayer.executePayment('pay_001', address(usdc), 1000e6, _split(900e6, 80e6, 20e6));

        assertEq(usdc.balanceOf(merchant), 900e6);
        assertEq(usdc.balanceOf(feeWallet), 80e6);
        assertEq(usdc.balanceOf(referrer), 20e6);
        assertEq(usdc.balanceOf(address(relayer)), 0);
        assertTrue(relayer.settled('pay_001'));
    }

    function test_executePayment_arbitraryToken() public {
        MockERC20 dai = new MockERC20('DAI', 'DAI', 18);
        dai.mint(address(relayer), 1000e18);

        vm.prank(operator);
        relayer.executePayment('pay_dai', address(dai), 1000e18, _split(900e18, 80e18, 20e18));

        assertEq(dai.balanceOf(merchant), 900e18);
        assertEq(dai.balanceOf(feeWallet), 80e18);
        assertEq(dai.balanceOf(referrer), 20e18);
    }

    function test_executePaymentNative_distributesFunds() public {
        vm.deal(address(relayer), 1 ether);

        vm.prank(operator);
        relayer.executePaymentNative('pay_native', 1 ether, _split(0.9 ether, 0.08 ether, 0.02 ether));

        assertEq(merchant.balance, 0.9 ether);
        assertEq(feeWallet.balance, 0.08 ether);
        assertEq(referrer.balance, 0.02 ether);
        assertEq(address(relayer).balance, 0);
        assertTrue(relayer.settled('pay_native'));
    }

    function test_executePaymentNative_revertsOnTotalMismatch() public {
        vm.deal(address(relayer), 1 ether);

        // total forwarded as msg.value must equal sum(splits); paymentNative reverts otherwise.
        vm.prank(operator);
        vm.expectRevert();
        relayer.executePaymentNative('pay_native_bad', 0.5 ether, _split(0.9 ether, 0.08 ether, 0.02 ether));
    }

    function test_executePayment_idempotent() public {
        usdc.mint(address(relayer), 2000e6);

        vm.prank(operator);
        relayer.executePayment('pay_dup', address(usdc), 1000e6, _split(900e6, 80e6, 20e6));

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SubyRelayer.AlreadySettled.selector, 'pay_dup'));
        relayer.executePayment('pay_dup', address(usdc), 1000e6, _split(900e6, 80e6, 20e6));
    }

    function test_executePayment_onlyOperator() public {
        usdc.mint(address(relayer), 1000e6);

        vm.prank(attacker);
        vm.expectRevert(SubyRelayer.NotOperator.selector);
        relayer.executePayment('pay_002', address(usdc), 1000e6, _split(900e6, 80e6, 20e6));

        vm.prank(owner);
        vm.expectRevert(SubyRelayer.NotOperator.selector);
        relayer.executePayment('pay_002', address(usdc), 1000e6, _split(900e6, 80e6, 20e6));
    }

    function test_executePayment_revertsOnEmptySplit() public {
        ISubyPayment.RecipientAndAmount[] memory empty = new ISubyPayment.RecipientAndAmount[](0);
        vm.prank(operator);
        vm.expectRevert(SubyRelayer.EmptySplitData.selector);
        relayer.executePayment('pay_003', address(usdc), 0, empty);
    }

    function test_executePayment_revertsWhenInsufficientUSDC() public {
        // Relayer has only 500 USDC but split totals 1000 — SubyPayment.payment will revert
        // on the underlying safeTransferFrom.
        usdc.mint(address(relayer), 500e6);
        vm.prank(operator);
        vm.expectRevert();
        relayer.executePayment('pay_short', address(usdc), 1000e6, _split(900e6, 80e6, 20e6));
    }

    function test_setOperator_byOwner() public {
        address newOp = makeAddr('newOp');
        vm.prank(attacker);
        vm.expectRevert();
        relayer.setOperator(newOp);

        vm.prank(owner);
        relayer.setOperator(newOp);
        assertEq(relayer.operator(), newOp);
    }

    function test_withdrawToken_byOwner() public {
        MockERC20 stray = new MockERC20('Stray', 'STR', 18);
        stray.mint(address(relayer), 1e18);

        vm.prank(attacker);
        vm.expectRevert();
        relayer.withdrawToken(address(stray));

        vm.prank(owner);
        relayer.withdrawToken(address(stray));
        assertEq(stray.balanceOf(owner), 1e18);
    }

    function test_withdrawETH_byOwner() public {
        vm.deal(address(relayer), 1 ether);

        vm.prank(attacker);
        vm.expectRevert();
        relayer.withdrawETH();

        uint256 before = owner.balance;
        vm.prank(owner);
        relayer.withdrawETH();
        assertEq(owner.balance, before + 1 ether);
    }
}

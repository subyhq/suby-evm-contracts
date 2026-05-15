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
        relayer = new SubyRelayer(owner, operator, address(subyPayment), address(usdc));
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
        assertEq(relayer.USDC(), address(usdc));
    }

    function test_executePayment_byOperator_distributesFunds() public {
        usdc.mint(address(relayer), 1000e6);

        vm.prank(operator);
        relayer.executePayment('pay_001', _split(900e6, 80e6, 20e6));

        assertEq(usdc.balanceOf(merchant), 900e6);
        assertEq(usdc.balanceOf(feeWallet), 80e6);
        assertEq(usdc.balanceOf(referrer), 20e6);
        assertEq(usdc.balanceOf(address(relayer)), 0);
        assertTrue(relayer.settled('pay_001'));
    }

    function test_executePayment_idempotent() public {
        usdc.mint(address(relayer), 2000e6);

        vm.prank(operator);
        relayer.executePayment('pay_dup', _split(900e6, 80e6, 20e6));

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SubyRelayer.AlreadySettled.selector, 'pay_dup'));
        relayer.executePayment('pay_dup', _split(900e6, 80e6, 20e6));
    }

    function test_executePayment_onlyOperator() public {
        usdc.mint(address(relayer), 1000e6);

        vm.prank(attacker);
        vm.expectRevert(SubyRelayer.NotOperator.selector);
        relayer.executePayment('pay_002', _split(900e6, 80e6, 20e6));

        vm.prank(owner);
        vm.expectRevert(SubyRelayer.NotOperator.selector);
        relayer.executePayment('pay_002', _split(900e6, 80e6, 20e6));
    }

    function test_executePayment_revertsOnEmptySplit() public {
        ISubyPayment.RecipientAndAmount[] memory empty = new ISubyPayment.RecipientAndAmount[](0);
        vm.prank(operator);
        vm.expectRevert(SubyRelayer.EmptySplitData.selector);
        relayer.executePayment('pay_003', empty);
    }

    function test_executePayment_revertsWhenInsufficientUSDC() public {
        // Relayer has only 500 USDC but split totals 1000 — SubyPayment.payment will revert
        // on the underlying safeTransferFrom.
        usdc.mint(address(relayer), 500e6);
        vm.prank(operator);
        vm.expectRevert();
        relayer.executePayment('pay_short', _split(900e6, 80e6, 20e6));
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

    function test_rescue_byOwner() public {
        MockERC20 stray = new MockERC20('Stray', 'STR', 18);
        stray.mint(address(relayer), 1e18);

        vm.prank(attacker);
        vm.expectRevert();
        relayer.rescue(address(stray), attacker, 1e18);

        vm.prank(owner);
        relayer.rescue(address(stray), owner, 1e18);
        assertEq(stray.balanceOf(owner), 1e18);
    }
}

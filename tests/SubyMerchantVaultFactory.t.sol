// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Test } from 'forge-std/Test.sol';

import { SubyMerchantVault } from '../src/SubyMerchantVault.sol';
import { SubyMerchantVaultFactory } from '../src/SubyMerchantVaultFactory.sol';
import { MockERC20 } from './mocks/MockERC20.sol';

contract SubyMerchantVaultFactoryTest is Test {
    SubyMerchantVaultFactory factory;
    MockERC20 usdc;
    MockERC20 eurc;

    address owner = makeAddr('owner');
    address operator = makeAddr('operator');
    address feeWallet = makeAddr('feeWallet');
    address merchant = makeAddr('merchant');
    address attacker = makeAddr('attacker');

    function setUp() public {
        usdc = new MockERC20('USDC', 'USDC', 6);
        eurc = new MockERC20('EURC', 'EURC', 6);
        factory = new SubyMerchantVaultFactory(owner, operator, feeWallet, address(usdc), address(eurc));
    }

    function test_constructor_setsConfig() public view {
        assertEq(factory.owner(), owner);
        assertEq(factory.operator(), operator);
        assertEq(factory.feeWallet(), feeWallet);
        assertEq(factory.USDC(), address(usdc));
        assertEq(factory.EURC(), address(eurc));
    }

    function test_constructor_rejectsZeroAddresses() public {
        vm.expectRevert(SubyMerchantVaultFactory.InvalidAddress.selector);
        new SubyMerchantVaultFactory(owner, address(0), feeWallet, address(usdc), address(eurc));

        vm.expectRevert(SubyMerchantVaultFactory.InvalidAddress.selector);
        new SubyMerchantVaultFactory(owner, operator, address(0), address(usdc), address(eurc));

        vm.expectRevert(SubyMerchantVaultFactory.InvalidAddress.selector);
        new SubyMerchantVaultFactory(owner, operator, feeWallet, address(0), address(eurc));

        vm.expectRevert(SubyMerchantVaultFactory.InvalidAddress.selector);
        new SubyMerchantVaultFactory(owner, operator, feeWallet, address(usdc), address(0));
    }

    function test_predictVault_matchesDeployed() public {
        bytes32 salt = keccak256('org_abc');
        address predicted = factory.predictVault(salt, merchant);

        vm.prank(operator);
        address actual = factory.deployVault(salt, merchant);

        assertEq(actual, predicted, 'CREATE2 prediction mismatch');
        assertEq(factory.vaultOf(salt), actual);

        // sanity: vault state is wired to factory
        SubyMerchantVault vault = SubyMerchantVault(actual);
        assertEq(address(vault.factory()), address(factory));
        assertEq(vault.merchant(), merchant);
        assertEq(vault.USDC(), address(usdc));
        assertEq(vault.EURC(), address(eurc));
    }

    function test_deployVault_revertsForNonOperator() public {
        vm.prank(attacker);
        vm.expectRevert(SubyMerchantVaultFactory.NotOperator.selector);
        factory.deployVault(keccak256('x'), merchant);
    }

    function test_deployVault_revertsOnDuplicateSalt() public {
        bytes32 salt = keccak256('dup');
        vm.prank(operator);
        factory.deployVault(salt, merchant);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SubyMerchantVaultFactory.AlreadyDeployed.selector, salt));
        factory.deployVault(salt, merchant);
    }

    function test_deployVault_revertsOnZeroMerchant() public {
        vm.prank(operator);
        vm.expectRevert(SubyMerchantVaultFactory.InvalidAddress.selector);
        factory.deployVault(keccak256('z'), address(0));
    }

    function test_predictVault_canReceiveUsdcBeforeDeploy() public {
        bytes32 salt = keccak256('preonramp');
        address predicted = factory.predictVault(salt, merchant);

        // PFI / Borderless drops USDC at the predicted address *before* the vault contract exists
        usdc.mint(predicted, 1000e6);
        assertEq(usdc.balanceOf(predicted), 1000e6);

        vm.prank(operator);
        address actual = factory.deployVault(salt, merchant);
        assertEq(actual, predicted);

        // Funds are now reachable through the freshly-deployed vault
        SubyMerchantVault vault = SubyMerchantVault(actual);
        assertEq(vault.balanceOf(address(usdc)), 1000e6);
        assertEq(vault.availableToWithdraw(address(usdc)), 1000e6);
    }

    function test_setOperator_onlyOwner() public {
        address newOp = makeAddr('newOp');
        vm.prank(attacker);
        vm.expectRevert();
        factory.setOperator(newOp);

        vm.prank(owner);
        factory.setOperator(newOp);
        assertEq(factory.operator(), newOp);
    }

    function test_setOperator_rejectsZero() public {
        vm.prank(owner);
        vm.expectRevert(SubyMerchantVaultFactory.InvalidAddress.selector);
        factory.setOperator(address(0));
    }

    function test_setFeeWallet_onlyOwner() public {
        address newFw = makeAddr('newFw');
        vm.prank(attacker);
        vm.expectRevert();
        factory.setFeeWallet(newFw);

        vm.prank(owner);
        factory.setFeeWallet(newFw);
        assertEq(factory.feeWallet(), newFw);
    }
}

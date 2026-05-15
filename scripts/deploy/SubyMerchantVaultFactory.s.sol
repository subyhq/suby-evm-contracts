// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Script }  from 'forge-std/Script.sol';
import { console } from 'forge-std/console.sol';

import { SubyMerchantVaultFactory } from '../../src/SubyMerchantVaultFactory.sol';

/// @notice env vars:
///   PRIVATE_KEY        — deployer key (also receives owner role)
///   VAULT_OWNER        — multisig that will own the factory (admin, settable: operator/feeWallet)
///   VAULT_OPERATOR     — Suby backend signer allowed to call deployVault / hold / release / clawback
///   VAULT_FEE_WALLET   — clawback destination
///   USDC               — USDC token address on the target network
///   EURC               — EURC token address on the target network
contract DeploySubyMerchantVaultFactory is Script {

    function run() external {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');

        address owner     = vm.envAddress('VAULT_OWNER');
        address operator  = vm.envAddress('VAULT_OPERATOR');
        address feeWallet = vm.envAddress('VAULT_FEE_WALLET');
        address usdc      = vm.envAddress('USDC');
        address eurc      = vm.envAddress('EURC');

        vm.startBroadcast(deployerPrivateKey);
        SubyMerchantVaultFactory factory = new SubyMerchantVaultFactory(
            owner,
            operator,
            feeWallet,
            usdc,
            eurc
        );
        vm.stopBroadcast();

        console.log('SubyMerchantVaultFactory: %s', address(factory));
        console.log('  owner    : %s', owner);
        console.log('  operator : %s', operator);
        console.log('  feeWallet: %s', feeWallet);
        console.log('  USDC     : %s', usdc);
        console.log('  EURC     : %s', eurc);
    }
}

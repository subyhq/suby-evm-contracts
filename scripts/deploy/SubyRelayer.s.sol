// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Script }  from 'forge-std/Script.sol';
import { console } from 'forge-std/console.sol';

import { SubyRelayer } from '../../src/SubyRelayer.sol';

/// @notice env vars:
///   PRIVATE_KEY         — deployer key
///   RELAYER_OWNER       — multisig that will own the relayer (rotate operator, rescue stuck funds)
///   RELAYER_OPERATOR    — Suby backend signer allowed to call executePayment
///   SUBY_PAYMENT        — deployed SubyPayment.sol address on this network
///   USDC                — USDC token address on this network
contract DeploySubyRelayer is Script {

    function run() external {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');

        address owner        = vm.envAddress('RELAYER_OWNER');
        address operator     = vm.envAddress('RELAYER_OPERATOR');
        address subyPayment  = vm.envAddress('SUBY_PAYMENT');
        address usdc         = vm.envAddress('USDC');

        vm.startBroadcast(deployerPrivateKey);
        SubyRelayer relayer = new SubyRelayer(owner, operator, subyPayment, usdc);
        vm.stopBroadcast();

        console.log('SubyRelayer  : %s', address(relayer));
        console.log('  owner      : %s', owner);
        console.log('  operator   : %s', operator);
        console.log('  subyPayment: %s', subyPayment);
        console.log('  USDC       : %s', usdc);
    }
}

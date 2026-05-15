// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { console } from 'forge-std/console.sol';
import { Script } from 'forge-std/Script.sol';

import { SubyPayment } from '../../src/SubyPayment.sol';

/// @title  DeploySubyPayment
/// @notice Deploys the `SubyPayment` settlement contract. The deployer becomes the
///         initial Ownable owner (controls `withdrawETH` / `withdrawToken` escape
///         hatches) — transfer ownership to a multisig post-deploy if needed.
contract DeploySubyPayment is Script {
    address owner;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        owner = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        SubyPayment paymentManager = new SubyPayment();
        vm.stopBroadcast();

        console.log('SubyPayment: %s', address(paymentManager));
        console.log('  owner    : %s', owner);
    }
}

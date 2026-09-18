// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Script }  from 'forge-std/Script.sol';
import { console } from 'forge-std/console.sol';

import { SubySettlement } from '../../src/SubySettlement.sol';

/// @notice env vars:
///   PRIVATE_KEY          — deployer key
///   SETTLEMENT_OWNER     — cold multisig: setOperator / pause / rescue
///   SETTLEMENT_OPERATOR  — Suby backend signer (RELAYER_OPERATOR_PRIVATE_KEY in apps/workers),
///                          the only caller of `distribute`. NOT a DFNS key.
///
/// @dev The deployed address is declared as the beneficiary of the ramp conversion, so it must
///      reach the PFI before the first delivery batch.
contract DeploySubySettlement is Script {

    function run() external {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');

        address owner    = vm.envAddress('SETTLEMENT_OWNER');
        address operator = vm.envAddress('SETTLEMENT_OPERATOR');

        vm.startBroadcast(deployerPrivateKey);
        SubySettlement settlement = new SubySettlement(owner, operator);
        vm.stopBroadcast();

        console.log('SubySettlement: %s', address(settlement));
        console.log('  owner   : %s', owner);
        console.log('  operator: %s', operator);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @notice Address that refuses native ETH, to exercise `rescueNative`'s failure path.
contract EtherRejector {
    receive() external payable {
        revert('no ether');
    }
}

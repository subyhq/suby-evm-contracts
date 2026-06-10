// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISubyPayment {
    function payment(string calldata paymentId, address tokenAddress, RecipientAndAmount[] calldata splitData) external;

    function paymentNative(string calldata paymentId, RecipientAndAmount[] calldata splitData) external payable;

    struct RecipientAndAmount {
        address recipient;
        uint256 amount;
    }
}

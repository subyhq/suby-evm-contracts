// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { ReentrancyGuard } from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { AccessControl } from '@openzeppelin/contracts/access/AccessControl.sol';

contract SubyPayment is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    constructor() Ownable(msg.sender) { }

    event Payment(
        address indexed sender,
        address indexed tokenAddress,
        uint256 transferAmount,
        RecipientAndAmount[] splitData,
        string paymentId
    );

    struct RecipientAndAmount {
        address recipient;
        uint256 amount;
    }

    function payment(
        string calldata paymentId,
        address tokenAddress,
        RecipientAndAmount[] calldata splitData
    )
        external
        nonReentrant
    {
        uint256 totalTransferAmount = 0;
        IERC20 token = IERC20(tokenAddress);
        for (uint256 i = 0; i < splitData.length; i++) {
            require(splitData[i].recipient != address(0), 'Recipient cannot be zero address');
            require(splitData[i].amount > 0, 'Transfer amount cannot be zero address');

            token.safeTransferFrom(msg.sender, splitData[i].recipient, splitData[i].amount);

            totalTransferAmount += splitData[i].amount;
        }

        emit Payment(msg.sender, tokenAddress, totalTransferAmount, splitData, paymentId);
    }

    function paymentNative(
        string calldata paymentId,
        RecipientAndAmount[] calldata splitData
    )
        external
        payable
        nonReentrant
    {
        uint256 totalTransferAmount = 0;
        for (uint256 i = 0; i < splitData.length; i++) {
            require(splitData[i].recipient != address(0), 'Recipient cannot be zero address');
            require(splitData[i].amount > 0, 'Transfer amount cannot be zero address');
            transferETH(splitData[i].recipient, splitData[i].amount);
            totalTransferAmount += splitData[i].amount;
        }

        require(msg.value == totalTransferAmount, 'Total message value does not match eth amount');

        emit Payment(msg.sender, address(0), totalTransferAmount, splitData, paymentId);
    }

    function transferETH(address recipient, uint256 amount) private {
        (bool sent,) = recipient.call{ value: amount }('');
        require(sent, 'Failed to send Ether');
    }

    function withdrawETH() external onlyOwner {
        (bool sent,) = msg.sender.call{ value: address(this).balance }('');
        require(sent, 'Failed to send Ether');
    }

    function withdrawToken(address tokenAddress) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        token.safeTransfer(msg.sender, token.balanceOf(address(this)));
    }

    receive() external payable { }

    fallback() external payable { }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { ReentrancyGuard } from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

import { ISubyPayment } from './interfaces/ISubyPayment.sol';

/// @title SubyRelayer
/// @notice Receives USDC bridged from Solana → Base via LI.FI (whose API does not yet
///         expose `contractCalls` from Solana) and forwards it through `SubyPayment.payment`
///         with the canonical merchant / fee-wallet / referrer split. Operator-gated.
contract SubyRelayer is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ISubyPayment public subyPayment;

    address public operator;

    /// @notice paymentId → settled. Prevents double-execution.
    mapping(string paymentId => bool) public settled;

    event Executed(string paymentId, uint256 total, uint256 splits);
    event OperatorChanged(address indexed previous, address indexed current);
    event Rescued(address indexed token, address indexed to, uint256 amount);

    error NotOperator();
    error InvalidAddress();
    error AlreadySettled(string paymentId);
    error EmptySplitData();

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    constructor(address owner_, address operator_, address subyPayment_) Ownable(owner_) {
        if (operator_ == address(0) || subyPayment_ == address(0)) revert InvalidAddress();
        subyPayment = ISubyPayment(subyPayment_);
        operator = operator_;
        emit OperatorChanged(address(0), operator_);
    }

    /// @notice Forward an arbitrary ERC-20 sitting on this contract into `SubyPayment.payment`
    ///         with the provided split. Caller (operator) is responsible for ensuring the relayer
    ///         holds enough `token` to cover `total` and that `total == sum(splitData.amount)`.
    /// @param token  ERC-20 to distribute (e.g. USDC).
    /// @param total  Sum of `splitData.amount`. Passed in to avoid recomputing it on-chain; it is
    ///               only used as the approval amount, so an undersized value makes the inner
    ///               `payment` revert on insufficient allowance.
    function executePayment(
        string calldata paymentId,
        address token,
        uint256 total,
        ISubyPayment.RecipientAndAmount[] calldata splitData
    )
        external
        nonReentrant
        onlyOperator
    {
        if (splitData.length == 0) revert EmptySplitData();
        if (token == address(0)) revert InvalidAddress();
        if (settled[paymentId]) revert AlreadySettled(paymentId);
        settled[paymentId] = true;

        // Approve only the exact amount needed for this call. forceApprove handles
        // any non-zero stale allowance defensively.
        IERC20(token).forceApprove(address(subyPayment), total);
        subyPayment.payment(paymentId, token, splitData);

        emit Executed(paymentId, total, splitData.length);
    }

    /// @notice Forward native ETH sitting on this contract into `SubyPayment.paymentNative`
    ///         with the provided split. `total` must equal `sum(splitData.amount)`, otherwise the
    ///         inner `paymentNative` reverts on the `msg.value` check.
    function executePaymentNative(
        string calldata paymentId,
        uint256 total,
        ISubyPayment.RecipientAndAmount[] calldata splitData
    )
        external
        nonReentrant
        onlyOperator
    {
        if (splitData.length == 0) revert EmptySplitData();
        if (settled[paymentId]) revert AlreadySettled(paymentId);
        settled[paymentId] = true;

        subyPayment.paymentNative{ value: total }(paymentId, splitData);

        emit Executed(paymentId, total, splitData.length);
    }

    // ---------------------- Owner ----------------------

    function setOperator(address newOperator) external onlyOwner {
        if (newOperator == address(0)) revert InvalidAddress();
        address old = operator;
        operator = newOperator;
        emit OperatorChanged(old, newOperator);
    }

    function setSubyPayment(address newSubyPayment) external onlyOwner {
        if (newSubyPayment == address(0)) revert InvalidAddress();
        subyPayment = ISubyPayment(newSubyPayment);
    }

    function withdrawETH() external onlyOwner {
        (bool sent,) = msg.sender.call{ value: address(this).balance }('');
        require(sent, 'Failed to send Ether');
    }

    function withdrawToken(address tokenAddress) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        token.safeTransfer(msg.sender, token.balanceOf(address(this)));
    }

    /// @notice Accept native ETH (e.g. bridged funds) so it can later be forwarded via
    ///         `executePaymentNative`.
    receive() external payable { }
}

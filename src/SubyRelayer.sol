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

    address public immutable USDC;
    ISubyPayment public immutable subyPayment;

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

    constructor(address owner_, address operator_, address subyPayment_, address usdc_) Ownable(owner_) {
        if (operator_ == address(0) || subyPayment_ == address(0) || usdc_ == address(0)) revert InvalidAddress();
        subyPayment = ISubyPayment(subyPayment_);
        USDC = usdc_;
        operator = operator_;
        emit OperatorChanged(address(0), operator_);
    }

    /// @notice Forward USDC sitting on this contract into `SubyPayment.payment` with the
    ///         provided split. Caller (operator) is responsible for ensuring the relayer
    ///         holds enough USDC to cover `sum(splitData.amount)`.
    function executePayment(
        string calldata paymentId,
        ISubyPayment.RecipientAndAmount[] calldata splitData
    )
        external
        nonReentrant
        onlyOperator
    {
        if (splitData.length == 0) revert EmptySplitData();
        if (settled[paymentId]) revert AlreadySettled(paymentId);
        settled[paymentId] = true;

        uint256 total;
        for (uint256 i = 0; i < splitData.length; i++) {
            total += splitData[i].amount;
        }

        // Approve only the exact amount needed for this call. forceApprove handles
        // any non-zero stale allowance defensively.
        IERC20(USDC).forceApprove(address(subyPayment), total);
        subyPayment.payment(paymentId, USDC, splitData);

        emit Executed(paymentId, total, splitData.length);
    }

    // ---------------------- Owner ----------------------

    function setOperator(address newOperator) external onlyOwner {
        if (newOperator == address(0)) revert InvalidAddress();
        address old = operator;
        operator = newOperator;
        emit OperatorChanged(old, newOperator);
    }

    /// @notice Escape hatch for funds stuck in the relayer (non-USDC bridged by mistake,
    ///         dust left over after partial fills, etc.). Owner-only.
    function rescue(address token, address to, uint256 amount) external nonReentrant onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        IERC20(token).safeTransfer(to, amount);
        emit Rescued(token, to, amount);
    }
}

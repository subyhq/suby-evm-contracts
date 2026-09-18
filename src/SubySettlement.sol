// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { Pausable } from '@openzeppelin/contracts/utils/Pausable.sol';
import { ReentrancyGuard } from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

contract SubySettlement is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public operator;

    mapping(bytes32 batchId => bool) public distributed;

    event Distributed(
        bytes32 indexed batchId, address indexed token, uint256 sentAmount, uint256 sentCount, uint256 failedCount
    );
    event PayoutFailed(bytes32 indexed batchId, address indexed token, address indexed recipient, uint256 amount);
    event OperatorChanged(address indexed previous, address indexed current);
    event Rescued(address indexed token, address indexed to, uint256 amount);
    event RescuedNative(address indexed to, uint256 amount);

    error NotOperator();
    error InvalidAddress();
    error SelfPayout(uint256 index);
    error NotAContract(address token);
    error AlreadyDistributed(bytes32 batchId);
    error EmptyBatch();
    error LengthMismatch(uint256 recipients, uint256 amounts);
    error ZeroAmount(uint256 index);
    error InsufficientBalance(uint256 required, uint256 available);
    error NothingToRescue();
    error NativeTransferFailed();

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    constructor(address owner_, address operator_) Ownable(owner_) {
        if (operator_ == address(0)) revert InvalidAddress();
        operator = operator_;
        emit OperatorChanged(address(0), operator_);
    }

    /// @param token      ERC-20 delivered by the ramp (USDC or EURC).
    /// @param recipients Merchant wallets, from the ledger plan.
    /// @param amounts    Per-merchant amounts, from the ledger plan. Parallel to `recipients`.
    /// @param batchId    Off-chain batch identifier; replay key.
    function distribute(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts,
        bytes32 batchId
    )
        external
        nonReentrant
        whenNotPaused
        onlyOperator
    {
        uint256 n = recipients.length;
        if (n == 0) revert EmptyBatch();
        if (n != amounts.length) revert LengthMismatch(n, amounts.length);
        if (token.code.length == 0) revert NotAContract(token);
        if (distributed[batchId]) revert AlreadyDistributed(batchId);

        distributed[batchId] = true;

        uint256 total;
        for (uint256 i; i < n; ++i) {
            if (recipients[i] == address(0)) revert InvalidAddress();
            if (recipients[i] == address(this)) revert SelfPayout(i);
            if (amounts[i] == 0) revert ZeroAmount(i);
            total += amounts[i];
        }

        uint256 available = IERC20(token).balanceOf(address(this));
        if (available < total) revert InsufficientBalance(total, available);

        uint256 sentAmount;
        uint256 sentCount;
        for (uint256 i; i < n; ++i) {
            if (_tryTransfer(token, recipients[i], amounts[i])) {
                sentAmount += amounts[i];
                unchecked {
                    ++sentCount;
                }
            } else {
                emit PayoutFailed(batchId, token, recipients[i], amounts[i]);
            }
        }

        emit Distributed(batchId, token, sentAmount, sentCount, n - sentCount);
    }

    /// @param token ERC-20 to sweep.
    /// @param to    Destination of the full balance.
    function rescue(address token, address to) external nonReentrant onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        if (token.code.length == 0) revert NotAContract(token);

        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount == 0) revert NothingToRescue();

        IERC20(token).safeTransfer(to, amount);
        emit Rescued(token, to, amount);
    }

    /// @param to Destination of the full native balance.
    function rescueNative(address to) external nonReentrant onlyOwner {
        if (to == address(0)) revert InvalidAddress();

        uint256 amount = address(this).balance;
        if (amount == 0) revert NothingToRescue();

        (bool ok,) = to.call{ value: amount }('');
        if (!ok) revert NativeTransferFailed();
        emit RescuedNative(to, amount);
    }

    /// @param newOperator Signer allowed to call `distribute`.
    function setOperator(address newOperator) external onlyOwner {
        if (newOperator == address(0)) revert InvalidAddress();
        address old = operator;
        operator = newOperator;
        emit OperatorChanged(old, newOperator);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @param token  ERC-20 to call `transfer` on.
    /// @param to     Recipient.
    /// @param amount Amount to send.
    function _tryTransfer(address token, address to, uint256 amount) private returns (bool) {
        (bool ok, bytes memory ret) = token.call(abi.encodeCall(IERC20.transfer, (to, amount)));
        return ok && (ret.length == 0 || (ret.length == 32 && abi.decode(ret, (bool))));
    }
}

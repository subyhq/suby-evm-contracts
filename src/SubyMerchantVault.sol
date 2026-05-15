// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { ReentrancyGuard } from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

import { ISubyMerchantVaultFactory } from './interfaces/ISubyMerchantVaultFactory.sol';

/// @title SubyMerchantVault
/// @notice Per-merchant escrow holding USDC/EURC on Base. Deposits are plain ERC20
///         transfers (no `deposit()` fn). Withdrawable = `balanceOf - holdOf`.
///         Operator (read from factory) can hold / release / clawback to feeWallet.
///         Merchant can withdraw up to `availableToWithdraw`.
contract SubyMerchantVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    ISubyMerchantVaultFactory public immutable factory;
    address public immutable merchant;
    address public immutable USDC;
    address public immutable EURC;

    /// @notice Aggregate amount frozen per supported token. Off-chain detail lives in
    ///         `VaultHoldEntry` (DB) — this is reconciled by `vault-event.worker`.
    mapping(address token => uint256 amount) public holdOf;

    event Held(address indexed token, uint256 amount, uint256 totalHeld, bytes32 reason);
    event Released(address indexed token, uint256 amount, uint256 totalHeld, bytes32 reason);
    event Clawback(address indexed token, address indexed feeWallet, uint256 amount, uint256 totalHeld, bytes32 reason);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);
    event Rescued(address indexed token, address indexed to, uint256 amount);

    error NotMerchant();
    error NotOperator();
    error UnsupportedToken(address token);
    error CannotRescueSupported(address token);
    error ZeroAmount();
    error ZeroAddress();
    error ExceedsHeld(uint256 requested, uint256 totalHeld);
    error InsufficientWithdrawable(uint256 requested, uint256 available);

    modifier onlyMerchant() {
        if (msg.sender != merchant) revert NotMerchant();
        _;
    }

    modifier onlyOperator() {
        if (msg.sender != factory.operator()) revert NotOperator();
        _;
    }

    modifier onlySupported(address token) {
        if (token != USDC && token != EURC) revert UnsupportedToken(token);
        _;
    }

    constructor(address merchant_, address usdc_, address eurc_) {
        if (merchant_ == address(0) || usdc_ == address(0) || eurc_ == address(0)) revert ZeroAddress();
        factory = ISubyMerchantVaultFactory(msg.sender);
        merchant = merchant_;
        USDC = usdc_;
        EURC = eurc_;
    }

    // ---------------------- Views ----------------------

    function balanceOf(address token) public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Signed withdrawable. Negative ⇒ Suby is fronting fee debt (held > balance).
    function withdrawable(address token) public view returns (int256) {
        return int256(balanceOf(token)) - int256(holdOf[token]);
    }

    /// @notice withdrawable clamped at zero (safe ceiling for `withdraw(amount)`).
    function availableToWithdraw(address token) public view returns (uint256) {
        uint256 bal = balanceOf(token);
        uint256 held = holdOf[token];
        return bal > held ? bal - held : 0;
    }

    // ---------------------- Operator ----------------------

    /// @notice Freeze `amount` of `token` so it cannot be withdrawn. `reason` is an
    ///         opaque tag for off-chain cross-reference (e.g. keccak256("rr:rrh_xxx")).
    function hold(address token, uint256 amount, bytes32 reason) external onlyOperator onlySupported(token) {
        if (amount == 0) revert ZeroAmount();
        uint256 newTotal = holdOf[token] + amount;
        holdOf[token] = newTotal;
        emit Held(token, amount, newTotal, reason);
    }

    /// @notice Release a previously-frozen amount back to withdrawable.
    function release(address token, uint256 amount, bytes32 reason) external onlyOperator onlySupported(token) {
        if (amount == 0) revert ZeroAmount();
        uint256 held = holdOf[token];
        if (amount > held) revert ExceedsHeld(amount, held);
        uint256 newTotal = held - amount;
        holdOf[token] = newTotal;
        emit Released(token, amount, newTotal, reason);
    }

    /// @notice Operator pulls `amount` of `token` to the factory `feeWallet` (debt recovery).
    ///         Held is reduced by `min(amount, held)` — the freeze that mirrored the debt
    ///         no longer needs to gate withdrawal once the funds have actually moved out.
    function clawback(
        address token,
        uint256 amount,
        bytes32 reason
    )
        external
        nonReentrant
        onlyOperator
        onlySupported(token)
    {
        if (amount == 0) revert ZeroAmount();
        address dst = factory.feeWallet();
        if (dst == address(0)) revert ZeroAddress();

        uint256 held = holdOf[token];
        uint256 newTotal = held;
        if (held > 0) {
            uint256 burn = amount > held ? held : amount;
            newTotal = held - burn;
            holdOf[token] = newTotal;
        }
        IERC20(token).safeTransfer(dst, amount);
        emit Clawback(token, dst, amount, newTotal, reason);
    }

    /// @notice Sweep a non-supported token accidentally sent to the vault.
    ///         Restricted to tokens ≠ USDC / EURC so that the `holdOf` / `withdrawable`
    ///         accounting on supported tokens cannot be bypassed.
    function rescue(address token, address to, uint256 amount) external nonReentrant onlyOperator {
        if (token == USDC || token == EURC) revert CannotRescueSupported(token);
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        IERC20(token).safeTransfer(to, amount);
        emit Rescued(token, to, amount);
    }

    // ---------------------- Merchant ----------------------

    function withdraw(address token, address to, uint256 amount)
        external
        nonReentrant
        onlyMerchant
        onlySupported(token)
    {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 available = availableToWithdraw(token);
        if (amount > available) revert InsufficientWithdrawable(amount, available);

        IERC20(token).safeTransfer(to, amount);
        emit Withdrawn(token, to, amount);
    }
}

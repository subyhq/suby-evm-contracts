// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { Create2 } from '@openzeppelin/contracts/utils/Create2.sol';

import { SubyMerchantVault } from './SubyMerchantVault.sol';
import { ISubyMerchantVaultFactory } from './interfaces/ISubyMerchantVaultFactory.sol';

/// @title SubyMerchantVaultFactory
/// @notice CREATE2 deployer for per-merchant `SubyMerchantVault`s on Base. Suby's backend
///         computes the salt off-chain (`keccak256(orgId)`), pre-shares the predicted
///         address with the PFI for onramp deposits, and deploys lazily on first inflow.
contract SubyMerchantVaultFactory is Ownable, ISubyMerchantVaultFactory {
    address public immutable override USDC;
    address public immutable override EURC;

    address public override operator;
    address public override feeWallet;

    mapping(bytes32 salt => address vault) public override vaultOf;

    error InvalidAddress();
    error AlreadyDeployed(bytes32 salt);
    error NotOperator();

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    constructor(address owner_, address operator_, address feeWallet_, address usdc_, address eurc_) Ownable(owner_) {
        if (operator_ == address(0) || feeWallet_ == address(0) || usdc_ == address(0) || eurc_ == address(0)) {
            revert InvalidAddress();
        }
        USDC = usdc_;
        EURC = eurc_;
        operator = operator_;
        feeWallet = feeWallet_;
        emit OperatorChanged(address(0), operator_);
        emit FeeWalletChanged(address(0), feeWallet_);
    }

    /// @notice Deploy a vault at the address returned by `predictVault(salt, merchant)`.
    function deployVault(bytes32 salt, address merchant) external override onlyOperator returns (address vault) {
        if (merchant == address(0)) revert InvalidAddress();
        if (vaultOf[salt] != address(0)) revert AlreadyDeployed(salt);

        vault = address(new SubyMerchantVault{ salt: salt }(merchant, USDC, EURC));
        vaultOf[salt] = vault;

        emit VaultDeployed(salt, merchant, vault);
    }

    /// @notice Off-chain CREATE2 address pre-image. Stable across networks for a given
    ///         (factory, salt, merchant, USDC, EURC) tuple.
    function predictVault(bytes32 salt, address merchant) external view override returns (address) {
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(SubyMerchantVault).creationCode, abi.encode(merchant, USDC, EURC)));
        return Create2.computeAddress(salt, initCodeHash, address(this));
    }

    // ---------------------- Owner ----------------------

    function setOperator(address newOperator) external onlyOwner {
        if (newOperator == address(0)) revert InvalidAddress();
        address old = operator;
        operator = newOperator;
        emit OperatorChanged(old, newOperator);
    }

    function setFeeWallet(address newFeeWallet) external onlyOwner {
        if (newFeeWallet == address(0)) revert InvalidAddress();
        address old = feeWallet;
        feeWallet = newFeeWallet;
        emit FeeWalletChanged(old, newFeeWallet);
    }
}

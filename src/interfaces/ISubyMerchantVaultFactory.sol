// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISubyMerchantVaultFactory {
    event VaultDeployed(bytes32 indexed salt, address indexed merchant, address vault);
    event OperatorChanged(address indexed previous, address indexed current);
    event FeeWalletChanged(address indexed previous, address indexed current);

    function USDC() external view returns (address);
    function EURC() external view returns (address);
    function operator() external view returns (address);
    function feeWallet() external view returns (address);
    function vaultOf(bytes32 salt) external view returns (address);

    function deployVault(bytes32 salt, address merchant) external returns (address vault);
    function predictVault(bytes32 salt, address merchant) external view returns (address);
}

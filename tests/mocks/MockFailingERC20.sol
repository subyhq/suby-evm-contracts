// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

/// @notice ERC-20 that can fail a transfer for a specific destination, the two ways a real
///         stablecoin does it: USDC/EURC *revert* on a blacklisted address, while some older
///         tokens return `false` instead. Both must leave the rest of a batch payable.
contract MockFailingERC20 is ERC20 {
    uint8 private immutable _customDecimals;

    mapping(address => bool) public blacklisted;
    mapping(address => bool) public silentlyRejects;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _customDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _customDecimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Transfers to `who` revert, like a Circle-blacklisted address.
    function setBlacklisted(address who, bool value) external {
        blacklisted[who] = value;
    }

    /// @notice Transfers to `who` return `false` without reverting.
    function setSilentlyRejects(address who, bool value) external {
        silentlyRejects[who] = value;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        require(!blacklisted[to], 'blacklisted');
        if (silentlyRejects[to]) return false;
        return super.transfer(to, amount);
    }
}

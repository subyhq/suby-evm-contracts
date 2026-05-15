// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console } from 'forge-std/Test.sol';

import { SubyPayment } from '../src/SubyPayment.sol';

contract SubyPaymentTest {
    SubyPayment public subyPayment;

    function setUp() public {
        subyPayment = new SubyPayment();
    }
}

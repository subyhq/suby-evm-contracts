// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Test } from 'forge-std/Test.sol';

import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { Pausable } from '@openzeppelin/contracts/utils/Pausable.sol';

import { SubySettlement } from '../src/SubySettlement.sol';
import { MockERC20 } from './mocks/MockERC20.sol';
import { MockFailingERC20 } from './mocks/MockFailingERC20.sol';
import { EtherRejector } from './mocks/EtherRejector.sol';

contract SubySettlementTest is Test {
    SubySettlement settlement;
    MockERC20 usdc;
    MockERC20 eurc;

    address owner = makeAddr('owner');
    address operator = makeAddr('operator');
    address attacker = makeAddr('attacker');
    address treasury = makeAddr('treasury');

    address merchantA = makeAddr('merchantA');
    address merchantB = makeAddr('merchantB');
    address merchantC = makeAddr('merchantC');

    bytes32 constant BATCH_1 = keccak256('dlv_batch_001');
    bytes32 constant BATCH_2 = keccak256('dlv_batch_002');
    bytes32 constant BATCH_3 = keccak256('dlv_batch_003');

    event Distributed(
        bytes32 indexed batchId, address indexed token, uint256 sentAmount, uint256 sentCount, uint256 failedCount
    );
    event PayoutFailed(bytes32 indexed batchId, address indexed token, address indexed recipient, uint256 amount);
    event Rescued(address indexed token, address indexed to, uint256 amount);

    function setUp() public {
        usdc = new MockERC20('USDC', 'USDC', 6);
        eurc = new MockERC20('EURC', 'EURC', 6);
        settlement = new SubySettlement(owner, operator);
    }

    // ---------------------- helpers ----------------------

    function _recipients3() internal view returns (address[] memory r) {
        r = new address[](3);
        r[0] = merchantA;
        r[1] = merchantB;
        r[2] = merchantC;
    }

    function _amounts3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256[] memory v) {
        v = new uint256[](3);
        v[0] = a;
        v[1] = b;
        v[2] = c;
    }

    function _one(address who) internal pure returns (address[] memory r) {
        r = new address[](1);
        r[0] = who;
    }

    function _one(uint256 amount) internal pure returns (uint256[] memory v) {
        v = new uint256[](1);
        v[0] = amount;
    }

    // ---------------------- constructor ----------------------

    function test_constructor_setsConfig() public view {
        assertEq(settlement.owner(), owner);
        assertEq(settlement.operator(), operator);
        assertFalse(settlement.paused());
    }

    function test_constructor_revertsOnZeroOperator() public {
        vm.expectRevert(SubySettlement.InvalidAddress.selector);
        new SubySettlement(owner, address(0));
    }

    // ---------------------- distribute · happy path ----------------------

    function test_distribute_paysEveryRecipient() public {
        usdc.mint(address(settlement), 1000e6);

        vm.prank(operator);
        settlement.distribute(address(usdc), _recipients3(), _amounts3(500e6, 300e6, 200e6), BATCH_1);

        assertEq(usdc.balanceOf(merchantA), 500e6);
        assertEq(usdc.balanceOf(merchantB), 300e6);
        assertEq(usdc.balanceOf(merchantC), 200e6);
        assertEq(usdc.balanceOf(address(settlement)), 0);
        assertTrue(settlement.distributed(BATCH_1));
    }

    function test_distribute_emitsDistributed() public {
        usdc.mint(address(settlement), 1000e6);

        vm.expectEmit(true, true, false, true, address(settlement));
        emit Distributed(BATCH_1, address(usdc), 1000e6, 3, 0);

        vm.prank(operator);
        settlement.distribute(address(usdc), _recipients3(), _amounts3(500e6, 300e6, 200e6), BATCH_1);
    }

    function test_distribute_twoTokensAreIndependent() public {
        usdc.mint(address(settlement), 300e6);
        eurc.mint(address(settlement), 700e6);

        vm.startPrank(operator);
        settlement.distribute(address(usdc), _one(merchantA), _one(300e6), BATCH_1);
        settlement.distribute(address(eurc), _one(merchantB), _one(700e6), BATCH_2);
        vm.stopPrank();

        assertEq(usdc.balanceOf(merchantA), 300e6);
        assertEq(eurc.balanceOf(merchantB), 700e6);
        assertEq(usdc.balanceOf(merchantB), 0);
        assertEq(eurc.balanceOf(merchantA), 0);
    }

    // ---------------------- distribute · replay ----------------------

    function test_distribute_replaySameBatchId_revertsWithoutPayingTwice() public {
        usdc.mint(address(settlement), 2000e6);

        vm.prank(operator);
        settlement.distribute(address(usdc), _recipients3(), _amounts3(500e6, 300e6, 200e6), BATCH_1);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SubySettlement.AlreadyDistributed.selector, BATCH_1));
        settlement.distribute(address(usdc), _recipients3(), _amounts3(500e6, 300e6, 200e6), BATCH_1);

        assertEq(usdc.balanceOf(merchantA), 500e6);
        assertEq(usdc.balanceOf(merchantB), 300e6);
        assertEq(usdc.balanceOf(merchantC), 200e6);
        assertEq(usdc.balanceOf(address(settlement)), 1000e6);
    }

    /// @dev The id is the replay key, not the payload.
    function test_distribute_replayWithDifferentPayload_stillReverts() public {
        usdc.mint(address(settlement), 2000e6);

        vm.prank(operator);
        settlement.distribute(address(usdc), _one(merchantA), _one(100e6), BATCH_1);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SubySettlement.AlreadyDistributed.selector, BATCH_1));
        settlement.distribute(address(usdc), _one(merchantB), _one(50e6), BATCH_1);

        assertEq(usdc.balanceOf(merchantB), 0);
    }

    // ---------------------- distribute · chunking ----------------------

    function test_distribute_threeChunksFromOneArrival() public {
        usdc.mint(address(settlement), 1000e6);

        vm.startPrank(operator);
        settlement.distribute(address(usdc), _one(merchantA), _one(500e6), BATCH_1);
        settlement.distribute(address(usdc), _one(merchantB), _one(300e6), BATCH_2);
        settlement.distribute(address(usdc), _one(merchantC), _one(200e6), BATCH_3);
        vm.stopPrank();

        assertEq(usdc.balanceOf(merchantA), 500e6);
        assertEq(usdc.balanceOf(merchantB), 300e6);
        assertEq(usdc.balanceOf(merchantC), 200e6);
        assertEq(usdc.balanceOf(address(settlement)), 0);
    }

    function test_distribute_partialRun_resumesOnUnsettledOnly() public {
        usdc.mint(address(settlement), 500e6);

        vm.prank(operator);
        settlement.distribute(address(usdc), _one(merchantA), _one(500e6), BATCH_1);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SubySettlement.InsufficientBalance.selector, 300e6, 0));
        settlement.distribute(address(usdc), _one(merchantB), _one(300e6), BATCH_2);
        assertFalse(settlement.distributed(BATCH_2));

        usdc.mint(address(settlement), 300e6);
        vm.prank(operator);
        settlement.distribute(address(usdc), _one(merchantB), _one(300e6), BATCH_2);

        assertEq(usdc.balanceOf(merchantA), 500e6);
        assertEq(usdc.balanceOf(merchantB), 300e6);
    }

    // ---------------------- distribute · partial failure ----------------------

    function test_distribute_blacklistedRecipientDoesNotBlockOthers() public {
        MockFailingERC20 token = new MockFailingERC20('USDC', 'USDC', 6);
        token.mint(address(settlement), 1000e6);
        token.setBlacklisted(merchantB, true);

        vm.expectEmit(true, true, true, true, address(settlement));
        emit PayoutFailed(BATCH_1, address(token), merchantB, 300e6);

        vm.prank(operator);
        settlement.distribute(address(token), _recipients3(), _amounts3(500e6, 300e6, 200e6), BATCH_1);

        assertEq(token.balanceOf(merchantA), 500e6, 'A paid');
        assertEq(token.balanceOf(merchantB), 0, 'B blacklisted');
        assertEq(token.balanceOf(merchantC), 200e6, 'C paid despite B failing');
        assertEq(token.balanceOf(address(settlement)), 300e6, "B's share stays put");
        assertTrue(settlement.distributed(BATCH_1), 'batch is consumed even with a failure');
    }

    function test_distribute_silentFalseReturnIsTreatedAsFailure() public {
        MockFailingERC20 token = new MockFailingERC20('USDC', 'USDC', 6);
        token.mint(address(settlement), 1000e6);
        token.setSilentlyRejects(merchantB, true);

        vm.prank(operator);
        settlement.distribute(address(token), _recipients3(), _amounts3(500e6, 300e6, 200e6), BATCH_1);

        assertEq(token.balanceOf(merchantB), 0);
        assertEq(token.balanceOf(merchantC), 200e6);
    }

    function test_distribute_failedPayoutRetriesUnderNewBatchId() public {
        MockFailingERC20 token = new MockFailingERC20('USDC', 'USDC', 6);
        token.mint(address(settlement), 1000e6);
        token.setBlacklisted(merchantB, true);

        vm.prank(operator);
        settlement.distribute(address(token), _recipients3(), _amounts3(500e6, 300e6, 200e6), BATCH_1);

        token.setBlacklisted(merchantB, false);
        vm.prank(operator);
        settlement.distribute(address(token), _one(merchantB), _one(300e6), BATCH_2);

        assertEq(token.balanceOf(merchantA), 500e6, 'A not paid twice');
        assertEq(token.balanceOf(merchantB), 300e6);
        assertEq(token.balanceOf(merchantC), 200e6, 'C not paid twice');
        assertEq(token.balanceOf(address(settlement)), 0);
    }

    // ---------------------- distribute · dust ----------------------

    /// @dev Anyone can push 1 wei here; it must not be able to stall a batch.
    function test_distribute_unrelatedDustDoesNotBlockTheBatch() public {
        usdc.mint(address(settlement), 1000e6);
        vm.prank(attacker);
        usdc.mint(address(settlement), 1);

        vm.prank(operator);
        settlement.distribute(address(usdc), _recipients3(), _amounts3(500e6, 300e6, 200e6), BATCH_1);

        assertEq(usdc.balanceOf(merchantA), 500e6);
        assertEq(usdc.balanceOf(address(settlement)), 1, 'dust survives, harmlessly');

        vm.prank(owner);
        settlement.rescue(address(usdc), treasury);
        assertEq(usdc.balanceOf(treasury), 1);
        assertEq(usdc.balanceOf(address(settlement)), 0);
    }

    // ---------------------- distribute · access & pause ----------------------

    function test_distribute_onlyOperator() public {
        usdc.mint(address(settlement), 1000e6);

        vm.prank(attacker);
        vm.expectRevert(SubySettlement.NotOperator.selector);
        settlement.distribute(address(usdc), _one(merchantA), _one(500e6), BATCH_1);

        vm.prank(owner);
        vm.expectRevert(SubySettlement.NotOperator.selector);
        settlement.distribute(address(usdc), _one(merchantA), _one(500e6), BATCH_1);
    }

    function test_distribute_revertsWhilePausedAndResumesAfterUnpause() public {
        usdc.mint(address(settlement), 1000e6);

        vm.prank(owner);
        settlement.pause();

        vm.prank(operator);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        settlement.distribute(address(usdc), _one(merchantA), _one(500e6), BATCH_1);

        vm.prank(owner);
        settlement.unpause();

        vm.prank(operator);
        settlement.distribute(address(usdc), _one(merchantA), _one(500e6), BATCH_1);
        assertEq(usdc.balanceOf(merchantA), 500e6);
    }

    function test_pause_onlyOwner() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, operator));
        settlement.pause();
    }

    // ---------------------- distribute · input validation ----------------------

    function test_distribute_revertsOnEmptyBatch() public {
        vm.prank(operator);
        vm.expectRevert(SubySettlement.EmptyBatch.selector);
        settlement.distribute(address(usdc), new address[](0), new uint256[](0), BATCH_1);
    }

    function test_distribute_revertsOnLengthMismatch() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SubySettlement.LengthMismatch.selector, 3, 2));
        settlement.distribute(address(usdc), _recipients3(), new uint256[](2), BATCH_1);
    }

    function test_distribute_revertsOnZeroAmount() public {
        usdc.mint(address(settlement), 1000e6);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SubySettlement.ZeroAmount.selector, 1));
        settlement.distribute(address(usdc), _recipients3(), _amounts3(500e6, 0, 200e6), BATCH_1);
    }

    function test_distribute_revertsOnZeroRecipient() public {
        usdc.mint(address(settlement), 1000e6);

        address[] memory r = _recipients3();
        r[2] = address(0);

        vm.prank(operator);
        vm.expectRevert(SubySettlement.InvalidAddress.selector);
        settlement.distribute(address(usdc), r, _amounts3(500e6, 300e6, 200e6), BATCH_1);
    }

    /// @dev A self-transfer succeeds at the token level, so it would count as a payment while the
    ///      funds never left.
    function test_distribute_revertsOnSelfPayout() public {
        usdc.mint(address(settlement), 1000e6);

        address[] memory r = _recipients3();
        r[1] = address(settlement);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SubySettlement.SelfPayout.selector, 1));
        settlement.distribute(address(usdc), r, _amounts3(500e6, 300e6, 200e6), BATCH_1);

        assertEq(usdc.balanceOf(merchantA), 0, 'nothing moved');
        assertFalse(settlement.distributed(BATCH_1));
    }

    /// @dev A codeless address would make every low-level transfer report success.
    function test_distribute_revertsOnCodelessToken() public {
        address notAToken = makeAddr('notAToken');

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SubySettlement.NotAContract.selector, notAToken));
        settlement.distribute(notAToken, _one(merchantA), _one(500e6), BATCH_1);

        assertFalse(settlement.distributed(BATCH_1));
    }

    function test_distribute_revertsOnInsufficientBalance() public {
        usdc.mint(address(settlement), 999e6);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SubySettlement.InsufficientBalance.selector, 1000e6, 999e6));
        settlement.distribute(address(usdc), _recipients3(), _amounts3(500e6, 300e6, 200e6), BATCH_1);

        assertEq(usdc.balanceOf(merchantA), 0);
        assertFalse(settlement.distributed(BATCH_1), 'id stays reusable after a top-up');
    }

    // ---------------------- rescue ----------------------

    function test_rescue_byOwnerSweepsFullBalance() public {
        usdc.mint(address(settlement), 42e6);

        vm.expectEmit(true, true, false, true, address(settlement));
        emit Rescued(address(usdc), treasury, 42e6);

        vm.prank(owner);
        settlement.rescue(address(usdc), treasury);

        assertEq(usdc.balanceOf(treasury), 42e6);
        assertEq(usdc.balanceOf(address(settlement)), 0);
    }

    function test_rescue_onlyOwner() public {
        usdc.mint(address(settlement), 42e6);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, operator));
        settlement.rescue(address(usdc), treasury);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        settlement.rescue(address(usdc), treasury);
    }

    /// @dev Pausing stops payouts during an incident; the recovery path must survive it.
    function test_rescue_worksWhilePaused() public {
        usdc.mint(address(settlement), 42e6);

        vm.startPrank(owner);
        settlement.pause();
        settlement.rescue(address(usdc), treasury);
        vm.stopPrank();

        assertEq(usdc.balanceOf(treasury), 42e6);
    }

    function test_rescue_revertsWhenEmpty() public {
        vm.prank(owner);
        vm.expectRevert(SubySettlement.NothingToRescue.selector);
        settlement.rescue(address(usdc), treasury);
    }

    function test_rescue_revertsOnZeroDestination() public {
        usdc.mint(address(settlement), 42e6);

        vm.prank(owner);
        vm.expectRevert(SubySettlement.InvalidAddress.selector);
        settlement.rescue(address(usdc), address(0));
    }

    // ---------------------- rescueNative ----------------------

    function test_rescueNative_byOwner() public {
        vm.deal(address(settlement), 1 ether);

        vm.prank(owner);
        settlement.rescueNative(treasury);

        assertEq(treasury.balance, 1 ether);
        assertEq(address(settlement).balance, 0);
    }

    function test_rescueNative_onlyOwner() public {
        vm.deal(address(settlement), 1 ether);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, operator));
        settlement.rescueNative(treasury);
    }

    function test_rescueNative_revertsWhenEmpty() public {
        vm.prank(owner);
        vm.expectRevert(SubySettlement.NothingToRescue.selector);
        settlement.rescueNative(treasury);
    }

    function test_rescueNative_revertsWhenDestinationRejects() public {
        vm.deal(address(settlement), 1 ether);
        EtherRejector rejector = new EtherRejector();

        vm.prank(owner);
        vm.expectRevert(SubySettlement.NativeTransferFailed.selector);
        settlement.rescueNative(address(rejector));
    }

    function test_plainEtherSendIsRejected() public {
        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        (bool ok,) = address(settlement).call{ value: 1 ether }('');
        assertFalse(ok);
    }

    // ---------------------- operator rotation ----------------------

    function test_setOperator_byOwnerRotatesTheHotKey() public {
        address newOperator = makeAddr('newOperator');
        usdc.mint(address(settlement), 1000e6);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        settlement.setOperator(newOperator);

        vm.prank(owner);
        settlement.setOperator(newOperator);
        assertEq(settlement.operator(), newOperator);

        vm.prank(operator);
        vm.expectRevert(SubySettlement.NotOperator.selector);
        settlement.distribute(address(usdc), _one(merchantA), _one(500e6), BATCH_1);

        vm.prank(newOperator);
        settlement.distribute(address(usdc), _one(merchantA), _one(500e6), BATCH_1);
        assertEq(usdc.balanceOf(merchantA), 500e6);
    }

    function test_setOperator_revertsOnZero() public {
        vm.prank(owner);
        vm.expectRevert(SubySettlement.InvalidAddress.selector);
        settlement.setOperator(address(0));
    }

    // ---------------------- fuzz ----------------------

    function testFuzz_distribute_movesExactlyThePlannedSum(uint8 rawCount, uint96 rawAmount) public {
        uint256 count = uint256(rawCount) % 50 + 1;
        uint256 amount = uint256(rawAmount) % 1e12 + 1;

        address[] memory recipients = new address[](count);
        uint256[] memory amounts = new uint256[](count);
        uint256 total;
        for (uint256 i; i < count; ++i) {
            recipients[i] = address(uint160(uint256(keccak256(abi.encode('m', i)))));
            amounts[i] = amount + i;
            total += amounts[i];
        }

        usdc.mint(address(settlement), total);

        vm.prank(operator);
        settlement.distribute(address(usdc), recipients, amounts, BATCH_1);

        assertEq(usdc.balanceOf(address(settlement)), 0);
        for (uint256 i; i < count; ++i) {
            assertEq(usdc.balanceOf(recipients[i]), amounts[i]);
        }
    }
}

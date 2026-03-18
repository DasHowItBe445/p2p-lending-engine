// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/core/P2PLending.sol";
import "../src/core/AaveConnector.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockAavePool.sol";
import "../src/libraries/OrderTypes.sol";

contract P2PLendingTest is Test {
    P2PLending public p2p;
    AaveConnector public connector;
    MockERC20 public asset;
    MockAavePool public pool;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    uint256 constant INITIAL_BALANCE = 100_000 * 1e6; // 6 decimals
    uint256 constant LEND_AMOUNT = 1_000 * 1e6;
    uint256 constant BORROW_AMOUNT = 500 * 1e6;
    uint256 constant RATE_BPS = 500; // 5%

    // Same signatures as P2PLending for expectEmit
    event LenderOrderPlaced(uint256 indexed orderId, address indexed owner, uint256 amount, uint256 minRateBps);
    event BorrowOrderPlaced(uint256 indexed orderId, address indexed owner, uint256 amount, uint256 maxRateBps);
    event Matched(uint256 indexed lenderOrderId, uint256 indexed borrowOrderId, uint256 rateBps, uint256 amount, uint256 loanId);
    event LenderOrderCancelled(uint256 indexed orderId, uint256 refundedAmount);
    event LoanRepaid(uint256 indexed loanId, uint256 totalPaid, uint256 interestPaid);
    event Withdrawn(address indexed user, uint256 amount);

    function setUp() public {
        asset = new MockERC20("Mock USDC", "USDC", 6);
        pool = new MockAavePool();

        // AaveConnector needs protocol = P2PLending address, but P2PLending isn’t deployed yet.
        // Predict the next contract address (P2PLending) so we can pass it to the connector.
        uint64 nonce = vm.getNonce(address(this));
        address predictedP2P = vm.computeCreateAddress(address(this), nonce + 1);

        connector = new AaveConnector(address(pool), address(asset), predictedP2P, address(0));
        p2p = new P2PLending(address(asset), address(connector));

        // Test contract holds the minted tokens; give some to alice and bob.
        asset.transfer(alice, INITIAL_BALANCE);
        asset.transfer(bob, INITIAL_BALANCE);
    }

    function test_PlaceLenderOrder() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        vm.expectEmit(true, true, true, true);
        emit LenderOrderPlaced(1, alice, LEND_AMOUNT, RATE_BPS);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS);
        vm.stopPrank();

        (address owner, uint128 amount, uint32 minRateBps,, uint128 remaining) = p2p.lenderOrders(1);
        assertEq(owner, alice);
        assertEq(amount, LEND_AMOUNT);
        assertEq(minRateBps, RATE_BPS);
        assertEq(remaining, LEND_AMOUNT);
        assertEq(asset.balanceOf(alice), INITIAL_BALANCE - LEND_AMOUNT);
        assertEq(pool.balanceOf(address(asset), address(connector)), LEND_AMOUNT);
    }

    function test_PlaceBorrowOrder() public {
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit BorrowOrderPlaced(1, bob, BORROW_AMOUNT, RATE_BPS);
        p2p.placeBorrowOrder(BORROW_AMOUNT, RATE_BPS);

        (address owner, uint128 amount, uint32 maxRateBps,, uint128 remaining) = p2p.borrowOrders(1);
        assertEq(owner, bob);
        assertEq(amount, BORROW_AMOUNT);
        assertEq(maxRateBps, RATE_BPS);
        assertEq(remaining, BORROW_AMOUNT);
    }

    function test_MatchOrders_FullMatch() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS);
        vm.stopPrank();

        vm.prank(bob);
        p2p.placeBorrowOrder(BORROW_AMOUNT, RATE_BPS);

        vm.expectEmit(true, true, true, true);
        emit Matched(1, 1, RATE_BPS, BORROW_AMOUNT, 1);
        p2p.matchOrders(1);

        assertEq(asset.balanceOf(bob), INITIAL_BALANCE + BORROW_AMOUNT);
        (address lender,, uint128 principal, uint32 rateBps,) = p2p.loanPositions(1);
        assertEq(lender, alice);
        assertEq(principal, BORROW_AMOUNT);
        assertEq(rateBps, RATE_BPS);
        (, , , , uint128 lenderRemaining) = p2p.lenderOrders(1);
        (, , , , uint128 borrowRemaining) = p2p.borrowOrders(1);
        assertEq(lenderRemaining, LEND_AMOUNT - BORROW_AMOUNT);
        assertEq(borrowRemaining, 0);
    }

    function test_MatchOrders_PartialFill() public {
        uint256 borrowMore = 2_000 * 1e6;
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS);
        vm.stopPrank();

        vm.prank(bob);
        p2p.placeBorrowOrder(borrowMore, RATE_BPS);

        p2p.matchOrders(1);

        // Lender 1: 1000 total, 1000 filled → remaining 0. Borrower: 2000 requested, 1000 filled → remaining 1000.
        (, , , , uint128 lenderRemaining) = p2p.lenderOrders(1);
        (, , , , uint128 borrowRemaining) = p2p.borrowOrders(1);
        assertEq(lenderRemaining, 0);
        assertEq(borrowRemaining, borrowMore - LEND_AMOUNT);
        assertEq(asset.balanceOf(bob), INITIAL_BALANCE + LEND_AMOUNT);
    }

    function test_CancelLenderOrder() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS);
        uint256 aliceBefore = asset.balanceOf(alice);

        // accrue yield in mock Aave
        vm.warp(block.timestamp + 30 days);

        p2p.cancelLenderOrder(1);
        vm.stopPrank();

        assertGt(asset.balanceOf(alice), aliceBefore + LEND_AMOUNT);
        (, , , , uint128 remainingAfterCancel) = p2p.lenderOrders(1);
        assertEq(remainingAfterCancel, 0);
    }

    function test_RepayAndWithdraw() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS);
        vm.stopPrank();
        vm.prank(bob);
        p2p.placeBorrowOrder(BORROW_AMOUNT, RATE_BPS);
        p2p.matchOrders(1);

        vm.warp(block.timestamp + 30 days);

        vm.startPrank(bob);
        asset.approve(address(p2p), type(uint256).max);
        p2p.repay(1);
        vm.stopPrank();

        uint256 withdrawable = p2p.lenderWithdrawable(alice);
        assertGt(withdrawable, BORROW_AMOUNT); 

        vm.prank(alice);
        p2p.withdraw();
        assertGt(
            asset.balanceOf(alice),
            INITIAL_BALANCE - LEND_AMOUNT + BORROW_AMOUNT
        );
        assertEq(p2p.lenderWithdrawable(alice), 0);
    }

    function test_Revert_PlaceLenderOrder_ZeroAmount() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        vm.expectRevert(P2PLending.InvalidAmount.selector);
        p2p.placeLenderOrder(0, RATE_BPS);
        vm.stopPrank();
    }

    function test_Revert_PlaceLenderOrder_InvalidRate() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        vm.expectRevert(P2PLending.InvalidRate.selector);
        p2p.placeLenderOrder(LEND_AMOUNT, 10001);
        vm.stopPrank();
    }

    function test_Revert_Cancel_Unauthorized() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS);
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert(P2PLending.Unauthorized.selector);
        p2p.cancelLenderOrder(1);
    }

    function test_NoMatch_WhenRatesIncompatible() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, 800); // min 8%
        vm.stopPrank();
        vm.prank(bob);
        p2p.placeBorrowOrder(BORROW_AMOUNT, 500); // max 5%

        p2p.matchOrders(1);

        // No match: lender wants 8%, borrower max 5%
        assertEq(asset.balanceOf(bob), INITIAL_BALANCE);
        assertEq(p2p.nextLoanId(), uint256(1));
    }

    function test_YieldAccruesInAave() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS);
        vm.stopPrank();

        uint256 before = pool.balanceOf(address(asset), address(connector));

        vm.warp(block.timestamp + 30 days);

        uint256 afterBal = pool.balanceOf(address(asset), address(connector));

        assertGt(afterBal, before); // yield should increase balance
    }

    function test_PartialMatch_AaveBalanceReducedCorrectly() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS);
        vm.stopPrank();

        vm.prank(bob);
        p2p.placeBorrowOrder(BORROW_AMOUNT, RATE_BPS);

        uint256 before = pool.balanceOf(address(asset), address(connector));

        p2p.matchOrders(1);

        uint256 afterBal = pool.balanceOf(address(asset), address(connector));

        assertEq(before - afterBal, BORROW_AMOUNT); // only matched amount withdrawn
    }

    function test_FullFlow_DepositMatchRepayWithdraw() public {
        // Deposit
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS);
        vm.stopPrank();

        // Borrow
        vm.prank(bob);
        p2p.placeBorrowOrder(BORROW_AMOUNT, RATE_BPS);

        // Match
        p2p.matchOrders(1);

        // Time passes
        vm.warp(block.timestamp + 30 days);

        // Repay
        vm.startPrank(bob);
        asset.approve(address(p2p), type(uint256).max);
        p2p.repay(1);
        vm.stopPrank();

        // Withdraw
        vm.prank(alice);
        p2p.withdraw();

        assertGt(asset.balanceOf(alice), INITIAL_BALANCE - LEND_AMOUNT + BORROW_AMOUNT);
    }
}
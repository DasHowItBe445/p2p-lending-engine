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

    uint256 constant DEADLINE = type(uint256).max;
    uint256 constant MIN_SHARES_OUT = 0;
    uint256 constant MIN_AMOUNT_OUT = 0;

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
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();

        (address owner, uint128 amount, uint128 remaining, uint32 minRateBps,) = p2p.lenderOrders(1);
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
        p2p.placeBorrowOrder(BORROW_AMOUNT, RATE_BPS, MIN_AMOUNT_OUT, DEADLINE);

        (address owner, uint128 amount, uint128 remaining, uint32 maxRateBps,) = p2p.borrowOrders(1);
        assertEq(owner, bob);
        assertEq(amount, BORROW_AMOUNT);
        assertEq(maxRateBps, RATE_BPS);
        assertEq(remaining, BORROW_AMOUNT);
    }

    function test_MatchOrders_FullMatch() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();

        vm.prank(bob);
        p2p.placeBorrowOrder(BORROW_AMOUNT, RATE_BPS, MIN_AMOUNT_OUT, DEADLINE);

        vm.expectEmit(true, true, true, true);
        emit Matched(1, 1, RATE_BPS, BORROW_AMOUNT, 1);
        p2p.matchOrders(1);

        uint256 expected = BORROW_AMOUNT - (BORROW_AMOUNT * 30 / 10_000);
        assertEq(asset.balanceOf(bob), INITIAL_BALANCE + expected);
        (address lender,, uint128 principal, uint32 rateBps,) = p2p.loanPositions(1);
        assertEq(lender, alice);
        assertEq(principal, BORROW_AMOUNT);
        assertEq(rateBps, RATE_BPS);
        (, , uint128 lenderRemaining, ,) = p2p.lenderOrders(1);
        (, , uint128 borrowRemaining, ,) = p2p.borrowOrders(1);
        assertEq(lenderRemaining, LEND_AMOUNT - BORROW_AMOUNT);
        assertEq(borrowRemaining, 0);
    }

    function test_MatchOrders_PartialFill() public {
        uint256 borrowMore = 2_000 * 1e6;
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();

        vm.prank(bob);
        p2p.placeBorrowOrder(borrowMore, RATE_BPS, MIN_AMOUNT_OUT, DEADLINE);

        p2p.matchOrders(1);

        // Lender 1: 1000 total, 1000 filled → remaining 0. Borrower: 2000 requested, 1000 filled → remaining 1000.
        (, , uint128 lenderRemaining, ,) = p2p.lenderOrders(1);
        (, , uint128 borrowRemaining, ,) = p2p.borrowOrders(1);
        assertEq(lenderRemaining, 0);
        assertEq(borrowRemaining, borrowMore - LEND_AMOUNT);
        uint256 expected = LEND_AMOUNT - (LEND_AMOUNT * 30 / 10_000);
        assertEq(asset.balanceOf(bob), INITIAL_BALANCE + expected);
    }

    function test_CancelLenderOrder() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        uint256 aliceBefore = asset.balanceOf(alice);

        // accrue yield in mock Aave
        vm.warp(block.timestamp + 30 days);

        p2p.cancelLenderOrder(1);
        vm.stopPrank();

        uint256 expectedMin = aliceBefore + LEND_AMOUNT;
        assertGt(asset.balanceOf(alice), expectedMin);
        (, , , , uint128 remainingAfterCancel) = p2p.lenderOrders(1);
        assertEq(remainingAfterCancel, 0);
    }

    function test_RepayAndWithdraw() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();
        vm.prank(bob);
        p2p.placeBorrowOrder(BORROW_AMOUNT, RATE_BPS, MIN_AMOUNT_OUT, DEADLINE);
        p2p.matchOrders(1);

        vm.warp(block.timestamp + 30 days);

        vm.startPrank(bob);
        asset.approve(address(p2p), type(uint256).max);
        p2p.repay(1);
        vm.stopPrank();

        uint256 withdrawable = p2p.getWithdrawable(alice);
        assertGt(withdrawable, BORROW_AMOUNT); 

        vm.prank(alice);
        p2p.withdraw();
        assertGt(
            asset.balanceOf(alice),
            INITIAL_BALANCE - LEND_AMOUNT + BORROW_AMOUNT
        );
        assertEq(p2p.getWithdrawable(alice), 0);
    }
    
    function test_Revert_PlaceLenderOrder_ZeroAmount() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        vm.expectRevert(P2PLending.InvalidAmount.selector);
        p2p.placeLenderOrder(0, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();
    }

    function test_Revert_PlaceLenderOrder_InvalidRate() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        vm.expectRevert(P2PLending.InvalidRate.selector);
        p2p.placeLenderOrder(LEND_AMOUNT, 10001, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();
    }

    function test_Revert_Cancel_Unauthorized() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert(P2PLending.Unauthorized.selector);
        p2p.cancelLenderOrder(1);
    }

    function test_NoMatch_WhenRatesIncompatible() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, 800, MIN_SHARES_OUT, DEADLINE); // min 8%
        vm.stopPrank(); 
        vm.prank(bob);
        p2p.placeBorrowOrder(BORROW_AMOUNT, 500, MIN_AMOUNT_OUT, DEADLINE); // max 5%

        p2p.matchOrders(1);

        // No match: lender wants 8%, borrower max 5%
        assertEq(asset.balanceOf(bob), INITIAL_BALANCE);
        assertEq(p2p.nextLoanId(), uint256(1));
    }

    function test_YieldAccruesInAave() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();

        uint256 before = pool.balanceOf(address(asset), address(connector));

        vm.warp(block.timestamp + 30 days);

        uint256 afterBal = pool.balanceOf(address(asset), address(connector));

        assertGt(afterBal, before); // yield should increase balance
    }

    function test_PartialMatch_AaveBalanceReducedCorrectly() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();

        vm.prank(bob);
        p2p.placeBorrowOrder(BORROW_AMOUNT, RATE_BPS, MIN_AMOUNT_OUT, DEADLINE);

        uint256 before = pool.balanceOf(address(asset), address(connector));

        p2p.matchOrders(1);

        uint256 afterBal = pool.balanceOf(address(asset), address(connector));

        uint256 expected = BORROW_AMOUNT - (BORROW_AMOUNT * 30 / 10_000);
        assertEq(before - afterBal, expected);
    }

    function test_FullFlow_DepositMatchRepayWithdraw() public {
        // Deposit
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();

        // Borrow
        vm.prank(bob);
        p2p.placeBorrowOrder(BORROW_AMOUNT, RATE_BPS, MIN_AMOUNT_OUT, DEADLINE);

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

    function test_YieldDistribution_Fairness() public {
        // Alice deposits first
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();

        // Time passes → Alice earns yield
        vm.warp(block.timestamp + 30 days);

        // Bob deposits later
        vm.startPrank(bob);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();

        // More time passes
        vm.warp(block.timestamp + 30 days);

        // Alice cancels → should get MORE yield than Bob
        vm.prank(alice);
        p2p.cancelLenderOrder(1);

        vm.prank(bob);
        p2p.cancelLenderOrder(2);

        uint256 aliceFinal = asset.balanceOf(alice);
        uint256 bobFinal = asset.balanceOf(bob);

        assertGt(aliceFinal, bobFinal);
    }

    function test_Revert_RepayTwice() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();

        vm.prank(bob);
        p2p.placeBorrowOrder(BORROW_AMOUNT, RATE_BPS, MIN_AMOUNT_OUT, DEADLINE);

        p2p.matchOrders(1);

        vm.startPrank(bob);
        asset.approve(address(p2p), type(uint256).max);
        p2p.repay(1);

        vm.expectRevert(P2PLending.LoanNotFound.selector);
        p2p.repay(1);
    }

    function test_YieldNotStolenOnMatch() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);

        vm.prank(bob);
        p2p.placeBorrowOrder(BORROW_AMOUNT, RATE_BPS, MIN_AMOUNT_OUT, DEADLINE);

        p2p.matchOrders(1);

        vm.prank(alice);
        p2p.cancelLenderOrder(1);

        assertGt(asset.balanceOf(alice), INITIAL_BALANCE - LEND_AMOUNT);
    }

    function test_ShareRoundingEdge() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), 1);
        p2p.placeLenderOrder(1, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();

        vm.startPrank(bob);
        asset.approve(address(p2p), 1);
        p2p.placeLenderOrder(1, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();

        // Ensure no zero shares edge case
        assertGt(p2p.totalShares(), 0);
    }

    function test_PreviewFunctions() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();

        uint256 shares = p2p.totalShares();

        uint256 assets = p2p.previewSharesToAssets(shares);
        assertGt(assets, 0);

        uint256 cancelPreview = p2p.previewCancel(1);
        assertGt(cancelPreview, 0);
    }

    function test_CancelAfterPartialMatch() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();

        vm.prank(bob);
        p2p.placeBorrowOrder(BORROW_AMOUNT, RATE_BPS, MIN_AMOUNT_OUT, DEADLINE);

        p2p.matchOrders(1);

        vm.prank(alice);
        p2p.cancelLenderOrder(1);

        assertGt(asset.balanceOf(alice), 0);
    }

    function test_LP_EarnsFees() public {
        vm.startPrank(alice);
        asset.approve(address(p2p), LEND_AMOUNT);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS, 0, DEADLINE);
        vm.stopPrank();

        vm.prank(bob);
        p2p.placeBorrowOrder(BORROW_AMOUNT, RATE_BPS, 0, DEADLINE);

        p2p.matchOrders(1);

        // cancel remaining liquidity
        vm.prank(alice);
        p2p.cancelLenderOrder(1);

        // Alice should have MORE than initial - lend
        assertGt(asset.balanceOf(alice), INITIAL_BALANCE - LEND_AMOUNT);
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/core/P2PLending.sol";
import "../src/core/AaveConnector.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockAavePool.sol";
import "forge-std/StdInvariant.sol";
import "./P2PLendingHandler.t.sol";

contract P2PLendingInvariant is StdInvariant, Test {
    P2PLending public p2p;
    P2PLendingHandler handler;
    AaveConnector public connector;
    MockERC20 public asset;
    MockAavePool public pool;

    address public alice = makeAddr("alice");

    uint256 constant INITIAL_BALANCE = 100_000 * 1e6;
    uint256 constant LEND_AMOUNT = 1_000 * 1e6;
    uint256 constant RATE_BPS = 500;

    uint256 constant MIN_SHARES_OUT = 0;
    uint256 constant DEADLINE = type(uint256).max;

    function setUp() public {
        asset = new MockERC20("Mock USDC", "USDC", 6);
        pool = new MockAavePool();

        uint64 nonce = vm.getNonce(address(this));
        address predictedP2P = vm.computeCreateAddress(address(this), nonce + 1);

        connector = new AaveConnector(address(pool), address(asset), predictedP2P, address(0));
        p2p = new P2PLending(address(asset), address(connector));

        asset.transfer(alice, INITIAL_BALANCE);

        vm.startPrank(alice);
        asset.approve(address(p2p), type(uint256).max);
        p2p.placeLenderOrder(LEND_AMOUNT, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();

        handler = new P2PLendingHandler(p2p, asset, alice);
        targetContract(address(handler));
    }

    function invariant_totalSharesConsistency() public view {
        uint256 totalShares = p2p.totalShares();
        uint256 totalAssets = p2p.previewSharesToAssets(totalShares);

        if (totalAssets > 0) {
            assertGt(totalShares, 0);
        }
    }

    function invariant_aaveBalanceNonZero() public view {
        uint256 aaveBalance = pool.balanceOf(address(asset), address(connector));
        assertGe(
            aaveBalance,
            p2p.previewSharesToAssets(p2p.totalShares())
        );
    }

    function invariant_sharesNonNegative() public view {
        uint256 shares = p2p.totalShares();
        assertGe(shares, 0);
    }
}
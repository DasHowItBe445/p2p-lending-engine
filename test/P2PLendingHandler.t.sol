// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/core/P2PLending.sol";
import "../src/mocks/MockERC20.sol";

contract P2PLendingHandler is Test {
    P2PLending public p2p;
    MockERC20 public asset;
    address public user;

    uint256 constant RATE_BPS = 500;
    uint256 constant MIN_SHARES_OUT = 0;
    uint256 constant MIN_AMOUNT_OUT = 0;
    uint256 constant DEADLINE = type(uint256).max;

    constructor(P2PLending _p2p, MockERC20 _asset, address _user) {
        p2p = _p2p;
        asset = _asset;
        user = _user;
    }

    function deposit(uint256 amount) public {
        amount = bound(amount, 1, 1000 * 1e6);

        vm.startPrank(user);
        asset.approve(address(p2p), amount);
        p2p.placeLenderOrder(amount, RATE_BPS, MIN_SHARES_OUT, DEADLINE);
        vm.stopPrank();
    }

    function borrow(uint256 amount) public {
        amount = bound(amount, 1, 1000 * 1e6);

        vm.prank(user);
        p2p.placeBorrowOrder(amount, RATE_BPS, MIN_AMOUNT_OUT, DEADLINE);
    }

    function matchOrders() public {
        p2p.matchOrders(1);
    }
}
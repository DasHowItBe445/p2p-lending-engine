// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/OrderTypes.sol";
import "../interfaces/IPool.sol";
import "./AaveConnector.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title P2PLending
 * @notice Gas-efficient P2P lending matching engine with Aave integration
 */
contract P2PLending is ReentrancyGuard {

    IERC20 public immutable asset;
    AaveConnector public immutable aaveConnector;

    uint256 public nextLenderOrderId = 1;
    uint256 public nextBorrowOrderId = 1;
    uint256 public nextLoanId = 1;

    mapping(uint256 => OrderTypes.LenderOrder) public lenderOrders;
    mapping(uint256 => OrderTypes.BorrowOrder) public borrowOrders;
    mapping(uint256 => OrderTypes.LoanPosition) public loanPositions;

    // Lender queue: bucketed by minRateBps (bucket = rate / 25), FIFO per bucket
    uint256 public lenderBucketBitset;
    mapping(uint256 => uint256) public lenderHeadOrderId;
    mapping(uint256 => uint256) public lenderTailOrderId;
    mapping(uint256 => uint256) public lenderNextInBucket;

    // Borrow queue: bucketed by maxRateBps
    uint256 public borrowBucketBitset;
    mapping(uint256 => uint256) public borrowHeadOrderId;
    mapping(uint256 => uint256) public borrowTailOrderId;
    mapping(uint256 => uint256) public borrowNextInBucket;

    mapping(address => uint256) public lenderWithdrawable;

    event LenderOrderPlaced(uint256 indexed orderId, address indexed owner, uint256 amount, uint256 minRateBps);
    event BorrowOrderPlaced(uint256 indexed orderId, address indexed owner, uint256 amount, uint256 maxRateBps);
    event Matched(uint256 indexed lenderOrderId, uint256 indexed borrowOrderId, uint256 rateBps, uint256 amount);
    event LenderOrderCancelled(uint256 indexed orderId);
    event LoanRepaid(uint256 indexed loanId, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    error InvalidAmount();
    error InvalidRate();
    error Unauthorized();
    error NoMatch();

    constructor(address asset_, address aaveConnector_) {
        asset = IERC20(asset_);
        aaveConnector = AaveConnector(payable(aaveConnector_));
    }

    function _lenderBucket(uint256 minRateBps) internal pure returns (uint256) {
        uint256 b = minRateBps / OrderTypes.BUCKET_SIZE_BPS;
        return b > OrderTypes.MAX_BUCKET_INDEX ? OrderTypes.MAX_BUCKET_INDEX : b;
    }

    function _borrowBucket(uint256 maxRateBps) internal pure returns (uint256) {
        uint256 b = maxRateBps / OrderTypes.BUCKET_SIZE_BPS;
        return b > OrderTypes.MAX_BUCKET_INDEX ? OrderTypes.MAX_BUCKET_INDEX : b;
    }

    function _enqueueLender(uint256 orderId) internal {
        OrderTypes.LenderOrder storage o = lenderOrders[orderId];
        uint256 bucket = _lenderBucket(o.minRateBps);
        lenderBucketBitset |= (1 << bucket);
        if (lenderTailOrderId[bucket] == 0) {
            lenderHeadOrderId[bucket] = orderId;
            lenderTailOrderId[bucket] = orderId;
        } else {
            lenderNextInBucket[lenderTailOrderId[bucket]] = orderId;
            lenderTailOrderId[bucket] = orderId;
        }
    }

    function _dequeueLender(uint256 bucket) internal returns (uint256 orderId) {
        orderId = lenderHeadOrderId[bucket];
        if (orderId == 0) return 0;
        uint256 next = lenderNextInBucket[orderId];
        lenderNextInBucket[orderId] = 0;
        lenderHeadOrderId[bucket] = next;
        if (next == 0) {
            lenderTailOrderId[bucket] = 0;
            lenderBucketBitset &= ~(1 << bucket);
        }
        return orderId;
    }

    function _enqueueBorrow(uint256 orderId) internal {
        OrderTypes.BorrowOrder storage o = borrowOrders[orderId];
        uint256 bucket = _borrowBucket(o.maxRateBps);
        borrowBucketBitset |= (1 << bucket);
        if (borrowTailOrderId[bucket] == 0) {
            borrowHeadOrderId[bucket] = orderId;
            borrowTailOrderId[bucket] = orderId;
        } else {
            borrowNextInBucket[borrowTailOrderId[bucket]] = orderId;
            borrowTailOrderId[bucket] = orderId;
        }
    }

    function _dequeueBorrow(uint256 bucket) internal returns (uint256 orderId) {
        orderId = borrowHeadOrderId[bucket];
        if (orderId == 0) return 0;
        uint256 next = borrowNextInBucket[orderId];
        borrowNextInBucket[orderId] = 0;
        borrowHeadOrderId[bucket] = next;
        if (next == 0) {
            borrowTailOrderId[bucket] = 0;
            borrowBucketBitset &= ~(1 << bucket);
        }
        return orderId;
    }

    function placeLenderOrder(uint256 amount, uint256 minRateBps) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (minRateBps > 10000) revert InvalidRate();
        uint256 id = nextLenderOrderId++;
        asset.transferFrom(msg.sender, address(this), amount);
        asset.approve(address(aaveConnector), amount);
        aaveConnector.deposit(amount);
        lenderOrders[id] = OrderTypes.LenderOrder({
            owner: msg.sender,
            amount: uint128(amount),
            minRateBps: uint32(minRateBps),
            createdAt: uint32(block.timestamp),
            remaining: uint128(amount)
        });
        _enqueueLender(id);
        emit LenderOrderPlaced(id, msg.sender, amount, minRateBps);
    }

    function placeBorrowOrder(uint256 amount, uint256 maxRateBps) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (maxRateBps > 10000) revert InvalidRate();
        uint256 id = nextBorrowOrderId++;
        borrowOrders[id] = OrderTypes.BorrowOrder({
            owner: msg.sender,
            amount: uint128(amount),
            maxRateBps: uint32(maxRateBps),
            createdAt: uint32(block.timestamp),
            remaining: uint128(amount)
        });
        _enqueueBorrow(id);
        emit BorrowOrderPlaced(id, msg.sender, amount, maxRateBps);
    }

    function matchOrders(uint256 maxItems) external nonReentrant {
        for (uint256 i = 0; i < maxItems; i++) {
            uint256 lenderBucket = _nextLenderBucket();
            uint256 borrowBucket = _nextBorrowBucket();
            if (lenderBucket == type(uint256).max || borrowBucket == type(uint256).max) break;

            uint256 lid = lenderHeadOrderId[lenderBucket];
            uint256 bid = borrowHeadOrderId[borrowBucket];
            if (lid == 0 || bid == 0) break;

            OrderTypes.LenderOrder storage lo = lenderOrders[lid];
            OrderTypes.BorrowOrder storage bo = borrowOrders[bid];
            if (lo.minRateBps > bo.maxRateBps) break;

            uint256 fill = lo.remaining < bo.remaining ? lo.remaining : bo.remaining;
            uint32 rateBps = lo.minRateBps;

            aaveConnector.withdraw(fill, bo.owner);

            lo.remaining -= uint128(fill);
            bo.remaining -= uint128(fill);
            if (lo.remaining == 0) _dequeueLender(lenderBucket);
            if (bo.remaining == 0) _dequeueBorrow(borrowBucket);

            uint256 loanId = nextLoanId++;
            loanPositions[loanId] = OrderTypes.LoanPosition({
                lender: lo.owner,
                borrower: bo.owner,
                principal: uint128(fill),
                rateBps: rateBps,
                startTime: uint32(block.timestamp),
                remainingPrincipal: uint128(fill)
            });
            emit Matched(lid, bid, rateBps, fill);
        }
    }

    function _nextLenderBucket() internal view returns (uint256) {
        for (uint256 b = 0; b <= OrderTypes.MAX_BUCKET_INDEX; b++) {
            if ((lenderBucketBitset & (1 << b)) != 0 && lenderHeadOrderId[b] != 0) return b;
        }
        return type(uint256).max;
    }

    function _nextBorrowBucket() internal view returns (uint256) {
        for (uint256 b = OrderTypes.MAX_BUCKET_INDEX; ; b--) {
            if ((borrowBucketBitset & (1 << b)) != 0 && borrowHeadOrderId[b] != 0) return b;
            if (b == 0) break;
        }
        return type(uint256).max;
    }

    function cancelLenderOrder(uint256 orderId) external nonReentrant {
        OrderTypes.LenderOrder storage o = lenderOrders[orderId];
        if (o.owner != msg.sender) revert Unauthorized();
        if (o.remaining == 0) revert InvalidAmount();
        uint256 amount = o.remaining;
        uint256 bucket = _lenderBucket(o.minRateBps);
        _removeLenderFromQueue(orderId, bucket);
        delete lenderOrders[orderId];
        aaveConnector.withdraw(amount, msg.sender);
        emit LenderOrderCancelled(orderId);
    }

    function _removeLenderFromQueue(uint256 orderId, uint256 bucket) internal {
        uint256 head = lenderHeadOrderId[bucket];
        if (head == orderId) {
            _dequeueLender(bucket);
            return;
        }
        uint256 prev = 0;
        uint256 cur = head;
        while (cur != 0 && cur != orderId) {
            prev = cur;
            cur = lenderNextInBucket[cur];
        }
        if (cur != orderId) return;
        lenderNextInBucket[prev] = lenderNextInBucket[orderId];
        if (lenderTailOrderId[bucket] == orderId) lenderTailOrderId[bucket] = prev;
        lenderNextInBucket[orderId] = 0;
    }

    function repay(uint256 loanId, uint256 amount) external nonReentrant {
        OrderTypes.LoanPosition storage pos = loanPositions[loanId];
        if (pos.borrower != msg.sender) revert Unauthorized();
        if (amount > pos.remainingPrincipal) amount = pos.remainingPrincipal;
        if (amount == 0) revert InvalidAmount();
        asset.transferFrom(msg.sender, address(this), amount);
        pos.remainingPrincipal -= uint128(amount);
        lenderWithdrawable[pos.lender] += amount;
        emit LoanRepaid(loanId, amount);
    }

    function withdraw() external nonReentrant {
        uint256 amount = lenderWithdrawable[msg.sender];
        if (amount == 0) revert InvalidAmount();
        lenderWithdrawable[msg.sender] = 0;
        asset.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }
}
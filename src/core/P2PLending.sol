// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/OrderTypes.sol";
import "./AaveConnector.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract P2PLending is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    AaveConnector public immutable aaveConnector;
    uint256 private constant SHARES_SCALE = 1e18;
    uint256 private constant YEAR = 365 days;

    uint256 public nextLenderOrderId = 1;
    uint256 public nextBorrowOrderId = 1;
    uint256 public nextLoanId = 1;

    mapping(uint256 => OrderTypes.LenderOrder) public lenderOrders;
    mapping(uint256 => OrderTypes.BorrowOrder) public borrowOrders;
    mapping(uint256 => OrderTypes.LoanPosition) public loanPositions;

    uint256 public totalShares;
    mapping(uint256 => uint256) public lenderOrderShares;

    uint256 public lenderBucketBitset;
    mapping(uint256 => uint256) public lenderHeadOrderId;
    mapping(uint256 => uint256) public lenderTailOrderId;
    mapping(uint256 => uint256) public lenderNextInBucket;

    uint256 public borrowBucketBitset;
    mapping(uint256 => uint256) public borrowHeadOrderId;
    mapping(uint256 => uint256) public borrowTailOrderId;
    mapping(uint256 => uint256) public borrowNextInBucket;

    mapping(address => uint256) public lenderWithdrawable;

    event LenderOrderPlaced(uint256 indexed orderId, address indexed owner, uint256 amount, uint256 minRateBps);
    event BorrowOrderPlaced(uint256 indexed orderId, address indexed owner, uint256 amount, uint256 maxRateBps);
    event Matched(uint256 indexed lenderOrderId, uint256 indexed borrowOrderId, uint256 rateBps, uint256 amount, uint256 loanId);
    event LenderOrderCancelled(uint256 indexed orderId, uint256 refundedAmount);
    event LoanRepaid(uint256 indexed loanId, uint256 totalPaid, uint256 interestPaid);
    event Withdrawn(address indexed user, uint256 amount);

    error InvalidAmount();
    error InvalidRate();
    error Unauthorized();
    error LoanNotFound();
    error LoanAlreadyRepaid();

    constructor(address asset_, address aaveConnector_) {
        asset = IERC20(asset_);
        aaveConnector = AaveConnector(payable(aaveConnector_));
    }

    function _totalAssets() internal view returns (uint256) {
        return aaveConnector.totalAssets();
    }

    function _assetsToShares(uint256 assets) internal view returns (uint256) {
        uint256 ts = totalShares;
        if (ts == 0) return assets * SHARES_SCALE;
        uint256 ta = _totalAssets();
        if (ta == 0) return assets * SHARES_SCALE;
        return (assets * ts) / ta;
    }

    function _assetsToSharesUp(uint256 assets) internal view returns (uint256) {
        uint256 ts = totalShares;
        if (ts == 0) return assets * SHARES_SCALE;
        uint256 ta = _totalAssets();
        if (ta == 0) return assets * SHARES_SCALE;
        return (assets * ts + (ta - 1)) / ta;
    }

    function _sharesToAssets(uint256 shares) internal view returns (uint256) {
        uint256 ts = totalShares;
        if (ts == 0) return 0;
        uint256 ta = _totalAssets();
        return (shares * ta) / ts;
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

        uint256 tail = lenderTailOrderId[bucket];
        if (tail == 0) {
            lenderHeadOrderId[bucket] = orderId;
            lenderTailOrderId[bucket] = orderId;
        } else {
            lenderNextInBucket[tail] = orderId;
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
    }

    function _enqueueBorrow(uint256 orderId) internal {
        OrderTypes.BorrowOrder storage o = borrowOrders[orderId];
        uint256 bucket = _borrowBucket(o.maxRateBps);

        borrowBucketBitset |= (1 << bucket);

        uint256 tail = borrowTailOrderId[bucket];
        if (tail == 0) {
            borrowHeadOrderId[bucket] = orderId;
            borrowTailOrderId[bucket] = orderId;
        } else {
            borrowNextInBucket[tail] = orderId;
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
    }

    function placeLenderOrder(uint256 amount, uint256 minRateBps) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (minRateBps > 10_000) revert InvalidRate();

        uint256 id = nextLenderOrderId++;
        asset.safeTransferFrom(msg.sender, address(this), amount);

        uint256 shares = _assetsToShares(amount);
        totalShares += shares;
        lenderOrderShares[id] = shares;

        asset.safeIncreaseAllowance(address(aaveConnector), amount);
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
        if (maxRateBps > 10_000) revert InvalidRate();

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
        uint256 ts = block.timestamp;

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

            uint256 sharesToBurn = _assetsToSharesUp(fill);
            uint256 orderShares = lenderOrderShares[lid];
            if (sharesToBurn > orderShares) sharesToBurn = orderShares;
            lenderOrderShares[lid] = orderShares - sharesToBurn;
            totalShares -= sharesToBurn;

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
                startTime: uint32(ts)
            });

            emit Matched(lid, bid, rateBps, fill, loanId);
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

        uint256 remaining = o.remaining;
        uint256 bucket = _lenderBucket(o.minRateBps);

        _removeLenderFromQueue(orderId, bucket);
        delete lenderOrders[orderId];

        uint256 shares = lenderOrderShares[orderId];
        uint256 ts = totalShares;
        uint256 ta = _totalAssets();
        uint256 assetsOut = ts == 0 ? 0 : (shares * ta) / ts;

        delete lenderOrderShares[orderId];
        totalShares = ts - shares;

        // Safety: always withdraw at least principal remaining
        if (assetsOut < remaining) assetsOut = remaining;

        aaveConnector.withdraw(assetsOut, msg.sender);

        emit LenderOrderCancelled(orderId, assetsOut);
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

        if (lenderTailOrderId[bucket] == orderId) {
            lenderTailOrderId[bucket] = prev;
        }

        lenderNextInBucket[orderId] = 0;

        if (lenderHeadOrderId[bucket] == 0) {
            lenderBucketBitset &= ~(1 << bucket);
        }
    }

    /**
     * Full repayment only:
     * - Computes totalOwed = principal + simple interest since startTime
     * - Transfers exactly totalOwed
     * - Deletes the loan to clear storage
     */
    function repay(uint256 loanId) external nonReentrant {
        OrderTypes.LoanPosition storage pos = loanPositions[loanId];

        address borrower = pos.borrower;
        if (borrower == address(0)) revert LoanNotFound();
        if (borrower != msg.sender) revert Unauthorized();

        uint128 principal128 = pos.principal;
        if (principal128 == 0) revert LoanAlreadyRepaid();

        uint256 ts = block.timestamp;
        uint256 elapsed = ts - uint256(pos.startTime);

        uint256 principal = uint256(principal128);
        uint256 interest = (principal * uint256(pos.rateBps) * elapsed) / (10_000 * YEAR);
        uint256 totalOwed = principal + interest;

        address lender = pos.lender;
        delete loanPositions[loanId];

        asset.safeTransferFrom(msg.sender, address(this), totalOwed);
        lenderWithdrawable[lender] += totalOwed;

        emit LoanRepaid(loanId, totalOwed, interest);
    }

    function withdraw() external nonReentrant {
        uint256 amount = lenderWithdrawable[msg.sender];
        if (amount == 0) revert InvalidAmount();

        lenderWithdrawable[msg.sender] = 0;
        asset.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }
}
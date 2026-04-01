// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/OrderTypes.sol";
import "./AaveConnector.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./LPToken.sol";

contract P2PLending is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    AaveConnector public immutable aaveConnector;
    uint256 private constant SHARES_SCALE = 1e18;
    uint256 private constant YEAR = 365 days;

    uint256 public constant FEE_BPS = 30;

    uint256 public nextLenderOrderId = 1;
    uint256 public nextBorrowOrderId = 1;
    uint256 public nextLoanId = 1;

    LPToken public lpToken;

    mapping(uint256 => OrderTypes.LenderOrder) public lenderOrders;
    mapping(uint256 => OrderTypes.BorrowOrder) internal _borrowOrders;
    mapping(uint256 => OrderTypes.LoanPosition) public loanPositions;
    mapping(address => uint256) public lenderWithdrawable;
    mapping(uint256 => uint256) public lenderOrderShares;

    uint256 public totalShares;

    uint256 public lenderBucketBitset;
    mapping(uint256 => uint256) public lenderHeadOrderId;
    mapping(uint256 => uint256) public lenderTailOrderId;
    mapping(uint256 => uint256) public lenderNextInBucket;

    uint256 public borrowBucketBitset;
    mapping(uint256 => uint256) public borrowHeadOrderId;
    mapping(uint256 => uint256) public borrowTailOrderId;
    mapping(uint256 => uint256) public borrowNextInBucket;

    event LenderOrderPlaced(uint256 indexed orderId, address indexed owner, uint256 amount, uint256 minRateBps);
    event BorrowOrderPlaced(uint256 indexed orderId, address indexed owner, uint256 amount, uint256 maxRateBps);
    event Matched(uint256 indexed lenderOrderId, uint256 indexed borrowOrderId, uint256 rateBps, uint256 amount, uint256 loanId);
    event LenderOrderCancelled(uint256 indexed orderId, uint256 refundedAmount);
    event LoanRepaid(uint256 indexed loanId, uint256 totalPaid, uint256 interestPaid);

    error InvalidAmount();
    error InvalidRate();
    error Unauthorized();
    error LoanNotFound();
    error LoanAlreadyRepaid();

    constructor(address asset_, address aaveConnector_) {
        asset = IERC20(asset_);
        aaveConnector = AaveConnector(payable(aaveConnector_));
        lpToken = new LPToken();
    }

    function _totalAssets() internal view returns (uint256) {
        return aaveConnector.totalAssets();
    }

    function _assetsToShares(uint256 assets) internal view returns (uint256) {
        uint256 ts = totalShares;
        if (ts == 0) return assets * SHARES_SCALE;
        uint256 ta = _totalAssets();
        if (ta == 0) return assets * SHARES_SCALE;
        return (assets * ts + ta - 1) / ta;
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
        OrderTypes.BorrowOrder storage o = _borrowOrders[orderId];
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

    function placeLenderOrder(uint256 amount, uint256 minRateBps, uint256 minSharesOut, uint256 deadline) external nonReentrant {
        
        if (block.timestamp > deadline) revert("expired");
        if (amount == 0) revert InvalidAmount();
        if (minRateBps > 10_000) revert InvalidRate();

        uint256 id = nextLenderOrderId++;
        asset.safeTransferFrom(msg.sender, address(this), amount);

        uint256 shares = _assetsToShares(amount);
        if (shares < minSharesOut) revert("slippage");
        lpToken.mint(msg.sender, shares);
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

    function placeBorrowOrder(uint256 amount, uint256 maxRateBps, uint256 minAmountOut, uint256 deadline) external nonReentrant {
        if (block.timestamp > deadline) revert("expired");
        if (amount < minAmountOut) revert("slippage");

        if (amount == 0) revert InvalidAmount();
        if (maxRateBps > 10_000) revert InvalidRate();

        uint256 id = nextBorrowOrderId++;

        _borrowOrders[id] = OrderTypes.BorrowOrder({
            owner: msg.sender,
            amount: uint128(amount),
            maxRateBps: uint32(maxRateBps),
            createdAt: uint32(block.timestamp),
            remaining: uint128(amount),
            minAmountOut: uint128(minAmountOut)
        });

        _enqueueBorrow(id);
        emit BorrowOrderPlaced(id, msg.sender, amount, maxRateBps);
    }

    function matchOrders(uint256 maxItems) external nonReentrant {
        uint256 ts = block.timestamp;

        for (uint256 i = 0; i < maxItems; i++) {
            uint256 beforeLender = lenderBucketBitset;
            uint256 beforeBorrow = borrowBucketBitset;

            _matchSingle(ts);

            if (beforeLender == lenderBucketBitset && beforeBorrow == borrowBucketBitset) {
                break;
            }
        }
    }

    function _matchSingle(uint256 timestamp) internal {
        uint256 lenderBucket = _nextLenderBucket();
        uint256 borrowBucket = _nextBorrowBucket();
        if (lenderBucket == type(uint256).max || borrowBucket == type(uint256).max) return;

        uint256 lid = lenderHeadOrderId[lenderBucket];
        uint256 bid = borrowHeadOrderId[borrowBucket];
        if (lid == 0 || bid == 0) return;

        OrderTypes.LenderOrder storage lo = lenderOrders[lid];
        OrderTypes.BorrowOrder storage bo = _borrowOrders[bid];

        if (lo.minRateBps > bo.maxRateBps) return;

        uint256 fill = lo.remaining < bo.remaining ? lo.remaining : bo.remaining;

        uint32 rateBps = lo.minRateBps;

        uint256 orderShares = lenderOrderShares[lid];

        uint256 fee = (fill * FEE_BPS) / 10_000;
      
        uint256 amountOut = fill - fee;

        if (amountOut < bo.minAmountOut) revert("slippage");

        uint256 sharesToBurn = (orderShares * fill) / lo.amount;
        if (sharesToBurn > orderShares) sharesToBurn = orderShares;

        lenderOrderShares[lid] = orderShares - sharesToBurn;

        lpToken.burn(lo.owner, sharesToBurn);
        totalShares -= sharesToBurn;


        lo.remaining -= uint128(fill);
        bo.remaining -= uint128(fill);
        
        aaveConnector.withdraw(amountOut, bo.owner);

        if (lo.remaining == 0) _dequeueLender(lenderBucket);
        if (bo.remaining == 0) _dequeueBorrow(borrowBucket);

        uint256 loanId = nextLoanId++;
        loanPositions[loanId] = OrderTypes.LoanPosition({
            lender: lo.owner,
            borrower: bo.owner,
            principal: uint128(fill),
            rateBps: rateBps,
            startTime: uint32(timestamp)
        });

        emit Matched(lid, bid, rateBps, fill, loanId);
    }

    function _nextLenderBucket() internal view returns (uint256) {
        uint256 bits = lenderBucketBitset;
        if (bits == 0) return type(uint256).max;

        uint256 lsb = _lsb(bits); 
        return _bitIndex(lsb);
    }

    function _nextBorrowBucket() internal view returns (uint256) {
        uint256 bits = borrowBucketBitset;
        if (bits == 0) return type(uint256).max;

        uint256 msb = 1 << _msb(bits);
        return _bitIndex(msb);
    }

    function cancelLenderOrder(uint256 orderId) external nonReentrant {
        OrderTypes.LenderOrder storage o = lenderOrders[orderId];

        if (o.owner != msg.sender) revert Unauthorized();
        if (o.remaining == 0) revert InvalidAmount();

        uint256 bucket = _lenderBucket(o.minRateBps);
        _removeLenderFromQueue(orderId, bucket);

        uint256 shares = lenderOrderShares[orderId];
        uint256 assets = _sharesToAssets(shares);

        lpToken.burn(msg.sender, shares);
        totalShares -= shares;

        delete lenderOrderShares[orderId];
        delete lenderOrders[orderId];

        aaveConnector.withdraw(assets, msg.sender);

        emit LenderOrderCancelled(orderId, assets);
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

        uint256 elapsed = block.timestamp - uint256(pos.startTime);

        uint256 principal = uint256(principal128);
        uint256 interest = (principal * uint256(pos.rateBps) * elapsed) / (10_000 * YEAR);
        uint256 totalOwed = principal + interest;

        address lender = pos.lender;

        delete loanPositions[loanId];

        asset.safeTransferFrom(msg.sender, address(this), totalOwed);

        lenderWithdrawable[lender] += totalOwed;

        emit LoanRepaid(loanId, totalOwed, interest);
    }

    function _lsb(uint256 x) internal pure returns (uint256) {
        return x & (~x + 1);
    }

    function _msb(uint256 x) internal pure returns (uint256) {
        uint256 r = 0;
        if (x >= 2**128) { x >>= 128; r += 128; }
        if (x >= 2**64) { x >>= 64; r += 64; }
        if (x >= 2**32) { x >>= 32; r += 32; }
        if (x >= 2**16) { x >>= 16; r += 16; }
        if (x >= 2**8) { x >>= 8; r += 8; }
        if (x >= 2**4) { x >>= 4; r += 4; }
        if (x >= 2**2) { x >>= 2; r += 2; }
        if (x >= 2**1) { r += 1; }
        return r;
    }

    function _bitIndex(uint256 bit) internal pure returns (uint256) {
        uint256 index = 0;
        while (bit > 1) {
            bit >>= 1;
            index++;
        }
        return index;
    }

    function previewSharesToAssets(uint256 shares) external view returns (uint256) {
        return _sharesToAssets(shares);
    }

    function previewInterest(uint256 loanId) external view returns (uint256) {
        OrderTypes.LoanPosition storage pos = loanPositions[loanId];
        if (pos.borrower == address(0)) return 0;

        uint256 elapsed = block.timestamp - uint256(pos.startTime);

        return (uint256(pos.principal) * pos.rateBps * elapsed) / (10_000 * YEAR);
    }
    function removeLiquidity(uint256 shares) external nonReentrant {
        require(shares > 0, "invalid");
        require(lpToken.balanceOf(msg.sender) >= shares, "not enough LP");

        uint256 assets = _sharesToAssets(shares);

        lpToken.burn(msg.sender, shares);
        totalShares -= shares;

        aaveConnector.withdraw(assets, msg.sender);
    }

    function getLPPrice() external view returns (uint256) {
        if (totalShares == 0) return 0;
        return (_totalAssets() * 1e18) / totalShares;
    }

    function getLPToken() external view returns (address) {
        return address(lpToken);
    }

    function getWithdrawable(address user) external view returns (uint256) {
        return lenderWithdrawable[user];
    }

    function withdraw() external nonReentrant {
        uint256 amount = lenderWithdrawable[msg.sender];
        if (amount == 0) revert InvalidAmount();

        lenderWithdrawable[msg.sender] = 0;
        asset.safeTransfer(msg.sender, amount);
    }

    function previewCancel(uint256 orderId) external view returns (uint256) {
        uint256 shares = lenderOrderShares[orderId];
        return _sharesToAssets(shares);
    }

    function getFeeBps() external pure returns (uint256) {
        return FEE_BPS;
    }

    function previewFee(uint256 amount) external pure returns (uint256) {
        return (amount * FEE_BPS) / 10_000;
    }

    function borrowOrders(uint256 id)
        external
        view
        returns (
            address owner,
            uint128 amount,
            uint128 remaining,
            uint32 maxRateBps,
            uint32 createdAt
        )
    {
        OrderTypes.BorrowOrder storage o = _borrowOrders[id];
        return (o.owner, o.amount, o.remaining, o.maxRateBps, o.createdAt);
    }

    function getUtilization() external view returns (uint256) {
        uint256 total = _totalAssets();
        if (total == 0) return 0;

        uint256 idle = aaveConnector.totalAssets();
        return ((total - idle) * 1e18) / total;
    }

    function previewMatch(uint256 lenderId, uint256 borrowId)
        external
        view
        returns (uint256 fill, uint256 fee, uint256 amountOut)
    {
        OrderTypes.LenderOrder storage lo = lenderOrders[lenderId];
        OrderTypes.BorrowOrder storage bo = _borrowOrders[borrowId];

        if (lo.minRateBps > bo.maxRateBps) return (0, 0, 0);

        fill = lo.remaining < bo.remaining ? lo.remaining : bo.remaining;

        fee = (fill * FEE_BPS) / 10_000;
        amountOut = fill - fee;
    }

    function getTotalAssets() external view returns (uint256) {
        return _totalAssets();
    }
}
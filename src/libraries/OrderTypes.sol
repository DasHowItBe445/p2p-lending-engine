// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title OrderTypes
 * @notice Shared order and loan position types for the P2P lending protocol
 */
library OrderTypes {
    uint256 public constant BUCKET_SIZE_BPS = 25;
    uint256 public constant MAX_BUCKET_INDEX = 255; // 255 * 25 = 6375 bps max

    struct LenderOrder {
        address owner;        
        uint128 amount;       
        uint128 remaining;    
        uint32 minRateBps;    
        uint32 createdAt;     
    }

    struct BorrowOrder {
        address owner;
        uint128 amount;
        uint128 remaining;
        uint32 maxRateBps;
        uint32 createdAt;
        uint128 minAmountOut;
    }

    struct LoanPosition {
        address lender;
        address borrower;
        uint128 principal;
        uint32 rateBps;
        uint32 startTime;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AaveConnector
 * @notice Wraps Aave V3 supply/withdraw. Holds aTokens; only the protocol can deposit/withdraw.
 */
contract AaveConnector {
    IPool public immutable pool;
    address public immutable asset;
    address public immutable protocol;

    error OnlyProtocol();
    error TransferFailed();

    modifier onlyProtocol() {
        if (msg.sender != protocol) revert OnlyProtocol();
        _;
    }

    constructor(address pool_, address asset_, address protocol_) {
        pool = IPool(pool_);
        asset = asset_;
        protocol = protocol_;
    }

    /**
     * @notice Pulls `amount` of asset from caller (protocol) and supplies to Aave on behalf of this contract
     */
    function deposit(uint256 amount) external onlyProtocol {
        if (amount == 0) return;
        require(IERC20(asset).transferFrom(protocol, address(this), amount), "AaveConnector: transferFrom failed");
        IERC20(asset).approve(address(pool), amount);
        pool.supply(asset, amount, address(this), 0);
    }

    /**
     * @notice Withdraws `amount` of asset from Aave and sends to `to`
     */
    function withdraw(uint256 amount, address to) external onlyProtocol returns (uint256) {
        if (amount == 0) return 0;
        return pool.withdraw(asset, amount, to);
    }
}
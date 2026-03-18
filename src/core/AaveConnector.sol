// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPool.sol";
import "../interfaces/IAToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AaveConnector
 * @notice Wraps Aave V3 supply/withdraw. Holds aTokens; only the protocol can deposit/withdraw.
 */
contract AaveConnector {
    using SafeERC20 for IERC20;

    IPool public immutable pool;
    address public immutable asset;
    address public immutable protocol;
    address public immutable aToken;

    error OnlyProtocol();
    error BalanceQueryFailed();

    modifier onlyProtocol() {
        if (msg.sender != protocol) revert OnlyProtocol();
        _;
    }

    constructor(address pool_, address asset_, address protocol_, address aToken_) {
        pool = IPool(pool_);
        asset = asset_;
        protocol = protocol_;
        aToken = aToken_;
    }

    /**
     * @notice Pulls `amount` of asset from caller (protocol) and supplies to Aave on behalf of this contract
     */
    function deposit(uint256 amount) external onlyProtocol {
        if (amount == 0) return;
        IERC20(asset).safeTransferFrom(protocol, address(this), amount);
        IERC20(asset).safeIncreaseAllowance(address(pool), amount);
        pool.supply(asset, amount, address(this), 0);
    }

    /**
     * @notice Withdraws `amount` of asset from Aave and sends to `to`
     */
    function withdraw(uint256 amount, address to) external onlyProtocol returns (uint256) {
        if (amount == 0) return 0;
        return pool.withdraw(asset, amount, to);
    }

    function totalAssets() external view returns (uint256) {
        if (aToken != address(0)) {
            return IAToken(aToken).balanceOf(address(this));
        }

        // Supports MockAavePool-style view: balanceOf(address asset, address user)
        (bool ok, bytes memory data) = address(pool).staticcall(
            abi.encodeWithSignature("balanceOf(address,address)", asset, address(this))
        );
        if (!ok || data.length < 32) revert BalanceQueryFailed();
        return abi.decode(data, (uint256));
    }
}
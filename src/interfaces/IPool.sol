// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPool
 * @notice Minimal Aave V3 Pool interface for supply and withdraw
 */
interface IPool {
    /**
     * @notice Supplies an `amount` of underlying asset into the reserve, receiving aTokens in exchange
     * @param asset The address of the underlying asset to supply
     * @param amount The amount to supply
     * @param onBehalfOf The address that will receive the aTokens
     * @param referralCode Referral code (use 0 for none)
     */
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /**
     * @notice Withdraws an `amount` of underlying asset from the reserve
     * @param asset The address of the underlying asset to withdraw
     * @param amount The amount to withdraw
     * @param to The address that will receive the underlying asset
     * @return The amount actually withdrawn
     */
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);
}

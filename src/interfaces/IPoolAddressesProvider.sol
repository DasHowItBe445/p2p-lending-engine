// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPoolAddressesProvider
 * @notice Minimal Aave V3 Pool Addresses Provider interface
 */
interface IPoolAddressesProvider {
    /**
     * @notice Returns the address of the Pool
     */
    function getPool() external view returns (address);

    /**
     * @notice Returns the address of the pool data provider (optional)
     */
    function getPoolDataProvider() external view returns (address);
}
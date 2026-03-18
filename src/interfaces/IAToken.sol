// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAToken
 * @notice Minimal aToken interface (ERC20-like with balanceOf)
 */
interface IAToken {
    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

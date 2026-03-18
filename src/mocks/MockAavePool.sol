// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockAavePool
 * @notice Mock Aave V3 Pool for testing without testnet. Tracks supplied amounts and returns them on withdraw.
 */
contract MockAavePool is IPool {
    // asset => (onBehalfOf => supplied amount)
    mapping(address => mapping(address => uint256)) public supplied;

    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 /* referralCode */
    ) external override {
        require(asset != address(0), "MockAavePool: zero asset");
        require(amount > 0, "MockAavePool: zero amount");
        require(
            IERC20(asset).transferFrom(msg.sender, address(this), amount),
            "MockAavePool: transferFrom failed"
        );
        supplied[asset][onBehalfOf] += amount;
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external override returns (uint256) {
        require(asset != address(0), "MockAavePool: zero asset");
        uint256 balance = supplied[asset][msg.sender];
        if (amount > balance) amount = balance;
        require(amount > 0, "MockAavePool: zero amount");
        supplied[asset][msg.sender] -= amount;
        require(
            IERC20(asset).transfer(to, amount),
            "MockAavePool: transfer failed"
        );
        return amount;
    }
}

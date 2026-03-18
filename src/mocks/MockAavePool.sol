// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockAavePool is IPool {
    uint256 private constant RAY = 1e27;
    uint256 private constant YEAR = 365 days;

    // asset => liquidity index (ray)
    mapping(address => uint256) public liquidityIndexRay;
    // asset => last update timestamp
    mapping(address => uint256) public lastUpdate;
    // asset => per-year rate (bps)
    mapping(address => uint256) public aprBps;

    // asset => (user => scaled balance)
    mapping(address => mapping(address => uint256)) public scaledBalances;
    // asset => total scaled balance
    mapping(address => uint256) public totalScaled;

    error ZeroAsset();
    error ZeroAmount();
    error TransferFailed();

    constructor() {
        // Default APR = 5% in mocks
        // If you need per-asset APR, call setAprBps in tests.
    }

    function setAprBps(address asset, uint256 newAprBps) external {
        if (asset == address(0)) revert ZeroAsset();
        aprBps[asset] = newAprBps;
        _accrue(asset);
    }

    function _initIfNeeded(address asset) internal {
        if (liquidityIndexRay[asset] == 0) {
            liquidityIndexRay[asset] = RAY;
            lastUpdate[asset] = block.timestamp;
            if (aprBps[asset] == 0) aprBps[asset] = 500;
        }
    }

    function _accrue(address asset) internal {
        _initIfNeeded(asset);
        uint256 last = lastUpdate[asset];
        uint256 ts = block.timestamp;
        if (ts <= last) return;

        uint256 dt = ts - last;
        uint256 rateBps = aprBps[asset];

        // Simple interest on the index: index *= (1 + apr * dt / YEAR)
        // Using ray math: index = index * (RAY + RAY*aprBps*dt/(10000*YEAR)) / RAY
        uint256 idx = liquidityIndexRay[asset];
        uint256 linear = (RAY * rateBps * dt) / (10_000 * YEAR);
        uint256 newIdx = (idx * (RAY + linear)) / RAY;

        // Mint the yield delta into the pool so withdraws can be funded.
        // This assumes the underlying token is a mock with `mint(address,uint256)`.
        uint256 scaledTotal = totalScaled[asset];
        if (scaledTotal != 0) {
            uint256 oldUnderlying = (scaledTotal * idx) / RAY;
            uint256 newUnderlying = (scaledTotal * newIdx) / RAY;
            if (newUnderlying > oldUnderlying) {
                uint256 delta = newUnderlying - oldUnderlying;
                (bool ok, ) = asset.call(
                    abi.encodeWithSignature("mint(address,uint256)", address(this), delta)
                );
                ok;
            }
        }

        liquidityIndexRay[asset] = newIdx;
        lastUpdate[asset] = ts;
    }

    function balanceOf(address asset, address user) external view returns (uint256) {
        uint256 idx = liquidityIndexRay[asset];
        if (idx == 0) idx = RAY;

        uint256 last = lastUpdate[asset];
        if (last != 0) {
            uint256 ts = block.timestamp;
            if (ts > last) {
                uint256 dt = ts - last;
                uint256 rateBps = aprBps[asset];
                if (rateBps == 0) rateBps = 500;
                uint256 linear = (RAY * rateBps * dt) / (10_000 * YEAR);
                idx = (idx * (RAY + linear)) / RAY;
            }
        }

        return (scaledBalances[asset][user] * idx) / RAY;
    }

    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 /* referralCode */
    ) external override {
        if (asset == address(0)) revert ZeroAsset();
        if (amount == 0) revert ZeroAmount();
        _accrue(asset);

        bool ok = IERC20(asset).transferFrom(msg.sender, address(this), amount);
        if (!ok) revert TransferFailed();

        uint256 idx = liquidityIndexRay[asset];
        uint256 scaled = (amount * RAY) / idx;
        scaledBalances[asset][onBehalfOf] += scaled;
        totalScaled[asset] += scaled;
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external override returns (uint256) {
        if (asset == address(0)) revert ZeroAsset();
        _accrue(asset);

        uint256 idx = liquidityIndexRay[asset];
        uint256 userScaled = scaledBalances[asset][msg.sender];
        uint256 userUnderlying = (userScaled * idx) / RAY;

        if (amount > userUnderlying) amount = userUnderlying;
        if (amount == 0) revert ZeroAmount();

        uint256 scaledToBurn = (amount * RAY) / idx;
        scaledBalances[asset][msg.sender] = userScaled - scaledToBurn;
        totalScaled[asset] -= scaledToBurn;

        bool ok = IERC20(asset).transfer(to, amount);
        if (!ok) revert TransferFailed();
        return amount;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockAavePool.sol";
import "../src/core/AaveConnector.sol";
import "../src/core/P2PLending.sol";

/// @notice Deploy MockERC20 → MockAavePool → AaveConnector → P2PLending (mock stack).
contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        MockERC20 asset = new MockERC20("Mock USDC", "USDC", 6);
        MockAavePool pool = new MockAavePool();

        uint64 nonce = vm.getNonce(deployer);
        address predictedP2P = vm.computeCreateAddress(deployer, nonce + 1);

        AaveConnector connector = new AaveConnector(
            address(pool),
            address(asset),
            predictedP2P,
            address(0) // mock pool: use staticcall balanceOf(asset, user)
        );

        P2PLending p2p = new P2PLending(address(asset), address(connector));

        require(address(p2p) == predictedP2P, "Deploy: P2P address mismatch");

        vm.stopBroadcast();

        console2.log("Deployer", deployer);
        console2.log("MockERC20 ", address(asset));
        console2.log("MockAavePool", address(pool));
        console2.log("AaveConnector", address(connector));
        console2.log("P2PLending ", address(p2p));
    }
}
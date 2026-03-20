// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/core/AaveConnector.sol";
import "../src/core/P2PLending.sol";
import "forge-std/console2.sol";

contract DeployAave is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        address asset = vm.envAddress("ASSET");
        address pool = vm.envAddress("POOL");
        address aToken = vm.envAddress("ATOKEN");

        vm.startBroadcast(pk);

        uint64 nonce = vm.getNonce(deployer);
        address predictedP2P = vm.computeCreateAddress(deployer, nonce + 1);

        AaveConnector connector = new AaveConnector(
            pool,
            asset,
            predictedP2P,
            aToken
        );

        P2PLending p2p = new P2PLending(asset, address(connector));

        require(address(p2p) == predictedP2P, "Mismatch");

        vm.stopBroadcast();

        console2.log("Connector:", address(connector));
        console2.log("P2P:", address(p2p));
    }
}
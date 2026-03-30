// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LPToken is ERC20 {
    address public lendingContract;

    constructor() ERC20("P2P LP Token", "P2PLP") {
        lendingContract = msg.sender;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == lendingContract, "not allowed");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == lendingContract, "not allowed");
        _burn(from, amount);
    }
}
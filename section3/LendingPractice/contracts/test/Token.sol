// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";


contract TokenA is ERC20("TokenA", "TKA") {
    constructor() {
        _mint(msg.sender, 10000 ether);
    }
}

contract TokenB is ERC20("TokenB", "TKB") {
    constructor() {
        _mint(msg.sender, 10000 ether);
    }
}

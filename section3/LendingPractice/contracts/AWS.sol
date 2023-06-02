// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract AWS is ERC20("AppWorks School Token", "AWS") {
    constructor() {
        _mint(msg.sender, 10000 ether);
    }
}

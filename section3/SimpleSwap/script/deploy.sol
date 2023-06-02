// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.17;

import { Script } from "forge-std/Script.sol";
import { SimpleSwap } from "../contracts/SimpleSwap.sol";
import { TestERC20 } from "../contracts/test/TestERC20.sol";

contract SimpleSwapDeploy is Script {
    function run() external {
        uint key = vm.envUint("private_key");
        vm.startBroadcast(key);
        address tokenA = address(new TestERC20("token A", "TKA"));
        address tokenB = address(new TestERC20("token B", "TKB"));
        SimpleSwap swap = new SimpleSwap(tokenA, tokenB);
        vm.stopBroadcast();
    }
}

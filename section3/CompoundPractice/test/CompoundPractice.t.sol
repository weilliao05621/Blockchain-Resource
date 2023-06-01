// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import {EIP20Interface} from "compound-protocol/contracts/EIP20Interface.sol";
import {CErc20} from "compound-protocol/contracts/CErc20.sol";
import "test/helper/CompoundPracticeSetUp.sol";

interface IBorrower {
    function borrow() external;
}

contract CompoundPracticeTest is CompoundPracticeSetUp {
    EIP20Interface public USDC =
        EIP20Interface(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    CErc20 public cUSDC = CErc20(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
    address public user;

    IBorrower public borrower;

    function setUp() public override {
        super.setUp();

        // Deployed in CompoundPracticeSetUp helper
        borrower = IBorrower(borrowerAddress);

        user = makeAddr("User");

        uint256 initialBalance = 10000 * 10 ** USDC.decimals();
        deal(address(USDC), user, initialBalance);

        vm.label(address(cUSDC), "cUSDC");
        vm.label(borrowerAddress, "Borrower");
    }

    function test_compound_mint_interest() public {
        vm.startPrank(user);
        // TODO: 1. Mint some cUSDC with USDC
        uint256 preBalance = USDC.balanceOf(user);
        uint256 mintAmount = 100 * 10 ** USDC.decimals();
        USDC.approve(address(cUSDC), mintAmount);
        uint hasMintError = cUSDC.mint(mintAmount);
        assertEq(hasMintError, 0, "Mint Error");

        // TODO: 2. Modify block state to generate interest
        uint256 newBlockNumber = block.number + 5;
        vm.roll(newBlockNumber);

        // TODO: 3. Redeem and check the redeemed amount
        uint cTokenAmount = cUSDC.balanceOf(user);
        uint hasRedeemError = cUSDC.redeem(cTokenAmount);
        assertEq(hasRedeemError, 0, "Redeem Error");
        assertGt(USDC.balanceOf(user), preBalance, "Interest Error");
    }

    function test_compound_mint_interest_with_borrower() public {
        vm.startPrank(user);

        // TODO: 1. Mint some cUSDC with USDC
        uint256 preBalance = USDC.balanceOf(user);
        uint256 mintAmount = 100 * 10 ** USDC.decimals();
        USDC.approve(address(cUSDC), mintAmount);
        uint hasMintError = cUSDC.mint(mintAmount);
        assertEq(hasMintError, 0, "Mint Error");

        // 2. Borrower.borrow() will borrow some USDC
        borrower.borrow();

        // TODO: 3. Modify block state to generate interest
        uint256 newBlockNumber = block.number + 5;
        vm.roll(newBlockNumber);

        // TODO: 4. Redeem and check the redeemed amount
        uint cTokenAmount = cUSDC.balanceOf(user);
        uint hasRedeemError = cUSDC.redeem(cTokenAmount);
        assertEq(hasRedeemError, 0, "Redeem Error");
        assertGt(USDC.balanceOf(user), preBalance, "Interest Error");
    }
}

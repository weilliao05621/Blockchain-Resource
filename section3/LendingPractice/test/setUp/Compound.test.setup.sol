// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "compound-protocol/contracts/CErc20Delegate.sol";
import "compound-protocol/contracts/CErc20Delegator.sol";
import "compound-protocol/contracts/WhitePaperInterestRateModel.sol";
import "compound-protocol/contracts/Unitroller.sol";
import "compound-protocol/contracts/Comptroller.sol";
import "compound-protocol/contracts/SimplePriceOracle.sol";

import {AWS} from "../../contracts/test/AWS.sol";
import {TokenA, TokenB} from "../../contracts/test/Token.sol";

contract TestCompoundSetUp is Test {
    AWS comp;

    TokenA tokenA;
    CErc20Delegate cTokenADelegate;
    CErc20Delegator cTokenA;

    TokenB tokenB;
    CErc20Delegate cTokenBDelegate;
    CErc20Delegator cTokenB;

    WhitePaperInterestRateModel interestRateModel;

    Unitroller unitroller;
    Comptroller comptroller;
    Comptroller unitrollerProxy;
    SimplePriceOracle priceOracle;

    address Admin;
    address User1;
    address User2;

    function setUp() public {
        Admin = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        User1 = makeAddr("User1");
        User2 = makeAddr("User2");

        vm.startPrank(Admin);
        _deployCompound();
        tokenA.transfer(User1, 5000 ether);
        tokenA.transfer(User2, 5000 ether);
        tokenB.transfer(User1, 5000 ether);
        tokenB.transfer(User2, 5000 ether);
        vm.stopPrank();

        vm.startPrank(User1);
        tokenA.approve(address(cTokenA), 5000 ether);
        tokenB.approve(address(cTokenB), 5000 ether);
        vm.stopPrank();

        vm.startPrank(User2);
        tokenA.approve(address(cTokenA), 5000 ether);
        tokenB.approve(address(cTokenB), 5000 ether);
        vm.stopPrank();
    }

    function _deployCompound() public {
        priceOracle = new SimplePriceOracle();

        interestRateModel = new WhitePaperInterestRateModel(5e16, 12e16); // 0.05 & 0.12

        unitroller = new Unitroller();
        comptroller = new Comptroller();
        unitrollerProxy = Comptroller(address(unitroller));

        unitroller._setPendingImplementation(address(comptroller));

        comptroller._become(unitroller);

        unitrollerProxy._setPriceOracle(priceOracle);
        unitrollerProxy._setCloseFactor(5e16);
        unitrollerProxy._setLiquidationIncentive(108e16);

        tokenA = new TokenA();
        cTokenADelegate = new CErc20Delegate();

        cTokenA = new CErc20Delegator(
            address(tokenA),
            unitrollerProxy,
            interestRateModel,
            1e18,
            "Compound Token A",
            "cTokenA",
            18,
            payable(Admin),
            address(cTokenADelegate),
            ""
        );

        cTokenA._setImplementation(address(cTokenADelegate), false, "");
        cTokenA._setReserveFactor(75e15);

        tokenB = new TokenB();
        cTokenBDelegate = new CErc20Delegate();
        cTokenB = new CErc20Delegator(
            address(tokenB),
            unitrollerProxy,
            interestRateModel,
            1e18,
            "Compound Token B",
            "cTokenB",
            18,
            payable(Admin),
            address(cTokenBDelegate),
            ""
        );
        cTokenB._setImplementation(address(cTokenBDelegate), false, "");
        cTokenB._setReserveFactor(75e15);

        unitrollerProxy._supportMarket(CToken(address(cTokenA)));
        unitrollerProxy._supportMarket(CToken(address(cTokenB)));

        priceOracle.setUnderlyingPrice(CToken(address(cTokenA)), 1e18);
        priceOracle.setUnderlyingPrice(CToken(address(cTokenB)), 100e18);

        unitrollerProxy._setCollateralFactor(CToken(address(cTokenA)), 85e16);
        unitrollerProxy._setCollateralFactor(CToken(address(cTokenB)), 5e17);
    }

    function test_Setup() public {
        assertEq(cTokenA.totalReserves(), 0);
        assertEq(cTokenB.totalReserves(), 0);

        assertEq(tokenA.allowance(User1, address(cTokenA)), 5000 ether);
        assertEq(tokenA.allowance(User2, address(cTokenA)), 5000 ether);
        assertEq(tokenB.allowance(User1, address(cTokenB)), 5000 ether);
        assertEq(tokenB.allowance(User2, address(cTokenB)), 5000 ether);

        assertEq(tokenA.balanceOf(User1), 5000 ether);
        assertEq(tokenB.balanceOf(User1), 5000 ether);
        assertEq(tokenA.balanceOf(User2), 5000 ether);
        assertEq(tokenB.balanceOf(User2), 5000 ether);
    }
}

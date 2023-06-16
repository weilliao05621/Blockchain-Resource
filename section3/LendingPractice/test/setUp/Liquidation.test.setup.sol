// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "compound-protocol/contracts/CErc20Delegate.sol";
import "compound-protocol/contracts/CErc20Delegator.sol";
import "compound-protocol/contracts/WhitePaperInterestRateModel.sol";
import "compound-protocol/contracts/Unitroller.sol";
import "compound-protocol/contracts/Comptroller.sol";
import "compound-protocol/contracts/SimplePriceOracle.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import "../../contracts/Liquidation.sol";

contract TestLiquidationSetUp is Test {
    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNI_ADDRESS = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

    uint constant MINT_cUNI_AMOUNT = 1000 * 10 ** 18;
    uint constant BORROW_cUSDC_AMOUNT = 2500 * 10 ** 6;

    address ADMIN = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    WhitePaperInterestRateModel interestRateModel;
    Unitroller unitroller;
    Comptroller comptroller;
    Comptroller unitrollerProxy;
    SimplePriceOracle priceOracle;

    CErc20Delegate cUSDCDelegate;
    CErc20Delegator cUSDC;

    CErc20Delegate cUNIDelegate;
    CErc20Delegator cUNI;

    address User1;
    address User2;

    function setUp() public virtual {
        User1 = makeAddr("User1");
        User2 = makeAddr("User2");

        vm.label(User1, "User1");
        vm.label(User2, "User2");

        deal(USDC_ADDRESS, User2, BORROW_cUSDC_AMOUNT);
        deal(UNI_ADDRESS, User1, MINT_cUNI_AMOUNT);

        vm.startPrank(ADMIN);
        _setUpCompound();
        _setUpCTokens();
        vm.stopPrank();
    }

    function _setUpCompound() private {
        priceOracle = new SimplePriceOracle();

        interestRateModel = new WhitePaperInterestRateModel(5e16, 12e16); // 0.05 & 0.12

        unitroller = new Unitroller();
        comptroller = new Comptroller();
        unitrollerProxy = Comptroller(address(unitroller));

        unitroller._setPendingImplementation(address(comptroller));

        comptroller._become(unitroller);

        unitrollerProxy._setPriceOracle(priceOracle);
        unitrollerProxy._setCloseFactor(5e17);
        unitrollerProxy._setLiquidationIncentive(108e16);
    }

    function _setUpCTokens() private {
        _setUpCUsdc();
        _setUpCUni();
    }

    function _setUpCUsdc() private {
        cUSDCDelegate = new CErc20Delegate();
        cUSDC = new CErc20Delegator(
            address(USDC_ADDRESS),
            unitrollerProxy,
            interestRateModel,
            1e18,
            "Compound USDC",
            "cUSDC",
            18,
            payable(ADMIN),
            address(cUSDCDelegate),
            ""
        );

        cUSDC._setImplementation(address(cUSDCDelegate), false, "");
        cUSDC._setReserveFactor(75e15);

        unitrollerProxy._supportMarket(CToken(address(cUSDC)));
        priceOracle.setUnderlyingPrice(CToken(address(cUSDC)), 1e30);
        unitrollerProxy._setCollateralFactor(CToken(address(cUSDC)), 85e16);
    }

    function _setUpCUni() private {
        cUNIDelegate = new CErc20Delegate();
        cUNI = new CErc20Delegator(
            address(UNI_ADDRESS),
            unitrollerProxy,
            interestRateModel,
            1e18,
            "Compound UNI",
            "cUNI",
            18,
            payable(ADMIN),
            address(cUNIDelegate),
            ""
        );

        cUNI._setImplementation(address(cUNIDelegate), false, "");
        cUNI._setReserveFactor(75e15);

        unitrollerProxy._supportMarket(CToken(address(cUNI)));
        priceOracle.setUnderlyingPrice(CToken(address(cUNI)), 5e18);
        unitrollerProxy._setCollateralFactor(CToken(address(cUNI)), 5e17);
    }
}

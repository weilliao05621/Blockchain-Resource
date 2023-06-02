// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "compound-protocol/contracts/CErc20Delegate.sol";
import "compound-protocol/contracts/CErc20Delegator.sol";
import "compound-protocol/contracts/WhitePaperInterestRateModel.sol";
import "compound-protocol/contracts/Unitroller.sol";
import "compound-protocol/contracts/Comptroller.sol";
import "compound-protocol/contracts/SimplePriceOracle.sol";

import {AWS} from "../contracts/AWS.sol";

contract Compound is Script {
    AWS aws;
    AWS comp;
    CErc20Delegate cAwsDelegate;
    CErc20Delegator cAWS;
    WhitePaperInterestRateModel interestRateModel;

    Unitroller unitroller;
    Comptroller comptroller;
    Comptroller unitrollerProxy;
    SimplePriceOracle priceOracle;

    address payable alice;

    function setUp() public {
        address _alice = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        alice = payable(_alice);
        // 新增 Oracle
        priceOracle = new SimplePriceOracle();

        // 設定初始的最底利率與成長斜率
        interestRateModel = new WhitePaperInterestRateModel(5e16, 12e16); // 0.05 & 0.12

        // 新增 comptroller 與 comptroller proxy
        unitroller = new Unitroller();
        comptroller = new Comptroller();
        unitrollerProxy = Comptroller(address(unitroller));
        // 設定 comptroller proxy 的 logic contract
        unitroller._setPendingImplementation(address(comptroller));

        // 調用 comptroller logic 來設置 oracle 和 清算因子
        unitrollerProxy._setPriceOracle(priceOracle);
        unitrollerProxy._setCloseFactor(5e16); // 0.05
        unitrollerProxy._setLiquidationIncentive(108e16); // 1.08

        // 創造新的 cErc20 的池子
        aws = new AWS();
        cAwsDelegate = new CErc20Delegate();
        cAWS = new CErc20Delegator(
            address(aws), // underlyign
            unitrollerProxy,
            interestRateModel,
            1e18, // 初始利率
            "Compound AppWorks School Token",
            "cAWS",
            18,
            alice, // admin
            address(cAwsDelegate),
            ""
        );
        cAWS._setImplementation(address(cAwsDelegate), false, "");
        cAWS._setReserveFactor(25e16); // 0.25

        // 確認新增 cErc20
        unitrollerProxy._supportMarket(CToken(address(cAWS)));

        // 設置 cErc20 的報價與抵押後可使用的借貸比例
        priceOracle.setUnderlyingPrice(CToken(address(cAWS)), 1e18);
        unitrollerProxy._setCollateralFactor(
            CToken(address(cAWS)),
            6e17 // 0.6
        );
    }

    function run() public {
        // uint256 privateKey = vm.envUint("PRIVATE_KEY");
        // vm.broadcast(privateKey);
        setUp();
    }
}

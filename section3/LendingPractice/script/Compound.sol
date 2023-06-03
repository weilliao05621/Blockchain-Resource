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

    function setUp() public {
        uint privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);
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

        /*
        1. 設定 Oracle price (unitroller._setPriceOracle) 會被 revert 
            > 發現是少了調用 Comptroller 先 _become()，來改變 admin
                [_become(): 先讓 comptroller 執行，確認當前的 unitroller admin 也是 comptroller admin，才去完成 implementation logic ]
                因為合約可以分開部署，而設置 admin 初始是用 msg.sender

            Revert 沒有其他訊息，是因為在 unitroller 的 delegatecall 的 function 是只有寫 revert 的 opcode
            所以單從錯誤訊息來看：
                - 單純 Revert 沒訊息：是在執行 unitroller delegatecall 出錯
                - 有回傳錯誤代碼：是在執行 comptroller 邏輯出錯
                > 要記得檢查 error_code

        ---

        2. 執行後還是只有單純的 Revert 報錯，檢查當前 unitroller 的 storage
            > log 出 unitroller 的 admin & implementation，發現原來沒有設定完成 implementation
            > 但 _become() 裡面如果有了 pendingImplementation，會接著幫呼叫 _acceptImplementation() 來完成轉移 implementation

            再細看一次了 _acceptImplementation()，發現需要由 pendingImplementation 來呼叫才會過。
            改成 comptroller 調用 _become 後，就順利完成 implementation address 的設置
        */
        comptroller._become(unitroller);


        // 調用 comptroller logic 來設置 oracle 和 清算因子
        unitrollerProxy._setPriceOracle(priceOracle);
        unitrollerProxy._setCloseFactor(5e16); // 0.05: 清算部位
        unitrollerProxy._setLiquidationIncentive(108e16); // 1.08: 清算獎勵

        // 創造新的 cErc20 的池子
        aws = new AWS();
        cAwsDelegate = new CErc20Delegate();
        /*
        3. "CErc20Delegator::_setImplementation: Caller must be admin"
           兩邊設計 admin 的方式不一樣，所以在模擬環境會有 vm default account & 自己定義的 account
           自己 startPrank(alice) 不會有這個 error，broadcast 會有，所以決定改為 payable(msg.sender)
           
           > 更神奇的是，startBroadcast 如果「單獨放在 run」跟「直接放在 setUp」，會影響出來的值
           > 同時，如果在 foundry 的 Script.sol 下使用 msg.sender，也必須加上 --private-key <key> 才會讓直接使用 msg.sender 跟合約裡吃到的 msg.sender 一樣 
        */
        cAWS = new CErc20Delegator(
            address(aws), // underlyign
            unitrollerProxy,
            interestRateModel,
            /*
                為了保持 1:1，所以 mantissa 初始利率用 1e18，確保 1 顆 decimals 為 ERC-20 去除 exchangeRate 得到是 1 
                表示在池子剛創建時，1 Ether ERC20 也是換到 1 Ether cToken。
                但為了確保兩人的數量一致，所以讓 cToken 的 decimals 也為 18。
                這樣放入 1 wei 數量的 ERC-20，也是拿到 1 wei 的 cToken
            */
            1e18, // 初始利率
            "Compound AppWorks School Token",
            "cAWS",
            18, 
            payable(msg.sender), // admin: 記得加上 --private-key
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

        vm.stopBroadcast();
    }

    function run() public {
        setUp();
        /*
            vm.startBroadcast() 放在這邊的話會印出這樣的結果
                unitroller amdin  0x5b73C5498c1E3b4dbA84de0F1833c4a029d90519
                msg.sender  0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38

            加上 --private-key
                unitroller amdin  0x5b73C5498c1E3b4dbA84de0F1833c4a029d90519
                msg.sender  0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
        */ 
        // uint privateKey = vm.envUint("PRIVATE_KEY");
        // vm.startBroadcast(privateKey);
        // vm.stopBroadcast();
    }
}

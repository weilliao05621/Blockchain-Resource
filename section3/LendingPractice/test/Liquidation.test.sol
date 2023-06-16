// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// import "forge-std/console.sol";
import "forge-std/Test.sol";
import "compound-protocol/contracts/CTokenInterfaces.sol";

import "./setUp/Liquidation.test.setup.sol";

contract TestLiquidation is TestLiquidationSetUp {
    AaveFlashLoan liquidation;

    function setUp() public override {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        uint FORK_BLOCK_NUMBER = vm.envUint("FORK_BLOCK_NUMBER");

        uint256 forkId = vm.createFork(MAINNET_RPC_URL, FORK_BLOCK_NUMBER);
        vm.selectFork(forkId);

        super.setUp();

        liquidation = new AaveFlashLoan();
    }

    function testLiquidateUser1SinceUNIPriceFall() public {
        _provideLiquidityToPool();

        // UNI 價格下跌
        vm.prank(ADMIN);
        priceOracle.setUnderlyingPrice(CToken(address(cUNI)), 4e18);

        // // 計算 shortfall，確保要借多少錢來清償
        (, , uint shortfall) = unitrollerProxy.getAccountLiquidity(User1);
        assertEq(shortfall, 500e18);

        uint repayAmount = ((shortfall / 2 / 1e18) * 1e6) / 2;
        assertEq(repayAmount, 125e6);

        vm.startPrank(User2);

        liquidation.liquidate(
            USDC_ADDRESS, // address liquidateToken
            address(cUSDC), // address liquidateCToken
            UNI_ADDRESS, // address collateralToken
            address(cUNI), // address collateralCToken
            User1, // address borrower
            repayAmount // uint repayAmount
        );

        assertGt(IERC20(USDC_ADDRESS).balanceOf(User2), 63 * 10 ** 6);
    }

    function _provideLiquidityToPool() internal {
        _user1SupplyUNI();
        _user2SupplyUSDC();
        _user1BorrowUsdc();
    }

    function _user2SupplyUSDC() internal {
        vm.startPrank(User2);
        IERC20(USDC_ADDRESS).approve(address(cUSDC), BORROW_cUSDC_AMOUNT);
        assertEq(cUSDC.mint(BORROW_cUSDC_AMOUNT), 0, "mint cUSDC failed");
        assertEq(
            cUSDC.balanceOf(User2),
            BORROW_cUSDC_AMOUNT,
            "mint cUSDC failed on 1:1"
        );
        vm.stopPrank();
    }

    function _user1SupplyUNI() internal {
        vm.startPrank(User1);
        IERC20(UNI_ADDRESS).approve(address(cUNI), MINT_cUNI_AMOUNT);
        assertEq(cUNI.mint(MINT_cUNI_AMOUNT), 0, "mint cUNI failed");
        assertEq(
            cUNI.balanceOf(User1),
            MINT_cUNI_AMOUNT,
            "mint cUNI failed on 1:1"
        );
        vm.stopPrank();
    }

    function _user1BorrowUsdc() internal {
        vm.startPrank(User1);
        cUNI.approve(address(cUNI), MINT_cUNI_AMOUNT);
        address[] memory addressList = new address[](1);
        addressList[0] = address(cUNI);
        unitrollerProxy.enterMarkets(addressList);
        assertEq(cUSDC.borrow(BORROW_cUSDC_AMOUNT), 0, "borrow USDC failed");
        vm.stopPrank();
    }
}

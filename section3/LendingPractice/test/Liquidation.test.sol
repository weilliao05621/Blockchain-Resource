// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// import "forge-std/console.sol";
import "forge-std/Test.sol";
import "compound-protocol/contracts/CTokenInterfaces.sol";

import "./setUp/Liquidation.test.setup.sol";
import {ILiquidation} from "../contracts/ILiquidation.sol";

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

        (, , uint shortfall) = unitrollerProxy.getAccountLiquidity(User1);
        assertGt(shortfall, 0, "LIQUIDATE: shortfall should be positive");

        vm.startPrank(User2);

        ILiquidation.LiquidationParams memory _liquidation = ILiquidation
            .LiquidationParams({
                liquidateToken: USDC_ADDRESS,
                liquidateCToken: address(cUSDC),
                collateralToken: UNI_ADDRESS,
                collateralCToken: address(cUNI),
                borrower: User1,
                repayAmount: BORROW_cUSDC_AMOUNT / 2
            });

        liquidation.liquidate(_liquidation);
        console.log(IERC20(USDC_ADDRESS).balanceOf(User2));
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
        assertEq(cUSDC.mint(BORROW_cUSDC_AMOUNT), 0, "SUPPLY: mint cUSDC failed");
        assertEq(
            cUSDC.balanceOf(User2),
            BORROW_cUSDC_AMOUNT,
            "SUPPLY: mint cUSDC failed on 1:1"
        );
        vm.stopPrank();
    }

    function _user1SupplyUNI() internal {
        vm.startPrank(User1);
        IERC20(UNI_ADDRESS).approve(address(cUNI), MINT_cUNI_AMOUNT);
        assertEq(cUNI.mint(MINT_cUNI_AMOUNT), 0, "SUPPLY: mint cUNI failed");
        assertEq(
            cUNI.balanceOf(User1),
            MINT_cUNI_AMOUNT,
            "SUPPLY:  mint cUNI failed on 1:1"
        );
        vm.stopPrank();
    }

    function _user1BorrowUsdc() internal {
        vm.startPrank(User1);
        cUNI.approve(address(cUNI), MINT_cUNI_AMOUNT);
        address[] memory addressList = new address[](1);
        addressList[0] = address(cUNI);
        unitrollerProxy.enterMarkets(addressList);
        assertEq(cUSDC.borrow(BORROW_cUSDC_AMOUNT), 0, "BORROW: borrow USDC failed");
        vm.stopPrank();
    }
}

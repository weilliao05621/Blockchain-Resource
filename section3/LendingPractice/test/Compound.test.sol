// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// import "forge-std/Test.sol";

import "./setUp/Compound.test.setup.sol";
import "compound-protocol/contracts/CToken.sol";
import "compound-protocol/contracts/CTokenInterfaces.sol";

contract TestCompound is TestCompoundSetUp {
    function test_User1_mint_and_redeem_tokenA() public {
        vm.startPrank(User1);
        // mint 100 ether cTokenA to User1
        uint errorMint = cTokenA.mint(100 ether);
        assertEq(errorMint, 0);

        // check if User1's balances
        assertEq(cTokenA.balanceOf(User1), 100 ether);
        assertEq(tokenA.balanceOf(User1), 4900 ether);
        // redeem tokena with the same amount of cTokenA
        cTokenA.approve(address(cTokenA), 100 ether);
        uint errorRedeem = cTokenA.redeem(100 ether);
        assertEq(errorRedeem, 0);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(User1), 5000 ether);
    }

    function test_User1_borrow_and_repay() public {
        // User2 supply some tokenA
        vm.prank(User2);
        assertEq(cTokenA.mint(100 ether), 0);

        vm.startPrank(User1);
        // User1 supply 100 ether cTokenB
        assertEq(cTokenB.mint(1 ether), 0);

        // User1 enter cTokenB as collateral (v3 adjust this part)
        cTokenB.approve(address(cTokenB), 1 ether);
        address[] memory addressList = new address[](1);
        addressList[0] = address(cTokenB);
        unitrollerProxy.enterMarkets(addressList);

        // use 1 ether tokenB to borrow 50 ether tokenA
        assertEq(cTokenA.borrow(50 ether), 0);

        assertEq(tokenA.balanceOf(User1), 5050 ether);
        assertEq(cTokenA.borrowBalanceCurrent(User1), 50 ether);

        // 雖然已經 approve 過，但這邊再做一次來提醒自己
        tokenA.approve(address(cTokenA), 50 ether);
        cTokenA.repayBorrow(50 ether);

        assertEq(tokenA.balanceOf(User1), 5000 ether);
        assertEq(cTokenA.borrowBalanceCurrent(User1), 0 ether);
        assertEq(cTokenB.balanceOf(User1), 1 ether);
        assertEq(tokenB.balanceOf(User1), 4999 ether);
    }

    function test_Admin_change_tokenB_collateral_factor_and_User2_liquidate_User1()
        public
    {
        vm.prank(User2);
        assertEq(cTokenA.mint(100 ether), 0);

        vm.startPrank(User1);
        // User1 supply 100 ether cTokenB
        assertEq(cTokenB.mint(1 ether), 0);

        // User1 enter cTokenB as collateral (v3 adjust this part)
        cTokenB.approve(address(cTokenB), 1 ether);
        address[] memory addressList = new address[](1);
        addressList[0] = address(cTokenB);
        unitrollerProxy.enterMarkets(addressList);

        // use 1 ether tokenB to borrow 50 ether tokenA
        assertEq(cTokenA.borrow(50 ether), 0);
        vm.stopPrank();

        vm.prank(Admin);
        unitrollerProxy._setCollateralFactor(CToken(address(cTokenB)), 4e17); // 0.5 > 0.4

        // console.log(CTokenInterface(cTokenA).balanceOf(User1));
        (, , uint shortfall) = unitrollerProxy.getAccountLiquidity(User1);
        assertEq(shortfall, 10 ether);

        vm.startPrank(User2);
        // max repay amount = balance * close factor > 10 ether * 0.05 = 2.5 ether
        cTokenA.liquidateBorrow(User1, 2.5 ether, CTokenInterface(cTokenB));
    }

    function test_tokenB_price_fall_and_User2_liquidate_User1() public {
        vm.prank(User2);
        assertEq(cTokenA.mint(100 ether), 0);

        vm.startPrank(User1);
        // User1 supply 100 ether cTokenB
        assertEq(cTokenB.mint(1 ether), 0);

        // User1 enter cTokenB as collateral (v3 adjust this part)
        cTokenB.approve(address(cTokenB), 1 ether);
        address[] memory addressList = new address[](1);
        addressList[0] = address(cTokenB);
        unitrollerProxy.enterMarkets(addressList);

        // use 1 ether tokenB to borrow 50 ether tokenA
        assertEq(cTokenA.borrow(50 ether), 0);
        vm.stopPrank();

        vm.prank(Admin);
        priceOracle.setUnderlyingPrice(CToken(address(cTokenB)), 80e18); // 100 ether > 80 ether

        (, , uint shortfall) = unitrollerProxy.getAccountLiquidity(User1);
        assertEq(shortfall, 10 ether);

        vm.startPrank(User2);
        // max repay amount = balance * close factor > 10 ether * 0.05 = 2.5 ether
        cTokenA.liquidateBorrow(User1, 2.5 ether, CTokenInterface(cTokenB));
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { IUniswapV2Router01 } from "v2-periphery/interfaces/IUniswapV2Router01.sol";
import { IUniswapV2Factory } from "v2-core/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Pair } from "v2-core/interfaces/IUniswapV2Pair.sol";
import { TestERC20 } from "../contracts/test/TestERC20.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";


contract UniswapV2PracticeTest is Test {
    IUniswapV2Router01 public constant UNISWAP_V2_ROUTER =
        IUniswapV2Router01(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IUniswapV2Factory public constant UNISWAP_V2_FACTORY =
        IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address public constant WETH9 = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    TestERC20 public testUSDC;
    IUniswapV2Pair public WETHTestUSDCPair;
    address public taker = makeAddr("Taker");
    address public maker = makeAddr("Maker");

    function setUp() public {
        // fork block
        vm.createSelectFork("mainnet", 17254242);

        // deploy test USDC
        testUSDC = _create_erc20("Test USDC", "USDC", 6);

        // mint 100 ETH, 10000 USDC to maker
        deal(maker, 100 ether);
        testUSDC.mint(maker, 10000 * 10 ** testUSDC.decimals());

        // mint 1 ETH to taker
        deal(taker, 100 ether);

        // create ETH/USDC pair
        WETHTestUSDCPair = IUniswapV2Pair(UNISWAP_V2_FACTORY.createPair(address(WETH9), address(testUSDC)));

        vm.label(address(UNISWAP_V2_ROUTER), "UNISWAP_V2_ROUTER");
        vm.label(address(UNISWAP_V2_FACTORY), "UNISWAP_V2_FACTORY");
        vm.label(address(WETH9), "WETH9");
        vm.label(address(testUSDC), "TestUSDC");
    }

    // # Practice 1: maker add liquidity (100 ETH, 10000 USDC)
    function test_maker_addLiquidityETH() public {
        // Implement here
        vm.startPrank(maker);
        testUSDC.approve(address(UNISWAP_V2_ROUTER),10000 * 10 ** testUSDC.decimals());
        UNISWAP_V2_ROUTER.addLiquidityETH{value: 100 ether}(address(testUSDC),10000 * 10 ** testUSDC.decimals(),0,0,maker,block.timestamp);
        vm.stopPrank();

        // Checking
        IUniswapV2Pair wethUsdcPair = IUniswapV2Pair(UNISWAP_V2_FACTORY.getPair(address(WETH9), address(testUSDC)));
        (uint112 reserve0, uint112 reserve1, ) = wethUsdcPair.getReserves();
        assertEq(reserve0, 10000 * 10 ** testUSDC.decimals());
        assertEq(reserve1, 100 ether);
    }

    // # Practice 2: taker swap exact 100 ETH for testUSDC
    function test_taker_swapExactETHForTokens() public {
        // Impelement here
        vm.startPrank(maker);
        testUSDC.approve(address(UNISWAP_V2_ROUTER),10000 * 10 ** testUSDC.decimals());
        UNISWAP_V2_ROUTER.addLiquidityETH{value: 100 ether}(address(testUSDC),10000 * 10 ** testUSDC.decimals(),0,0,maker,block.timestamp);
        vm.stopPrank();


        vm.startPrank(taker);
        address[] memory _path = new address[](2); // 一定要指定好 array 長度
        _path[0] = address(WETH9);
        _path[1] = address(testUSDC);

        UNISWAP_V2_ROUTER.swapExactETHForTokens{value: 100 ether}(0,_path,taker,block.timestamp);
        vm.stopPrank();

        // Checking
        // # Disscussion 1: discuss why 4992488733 ?
        assertEq(testUSDC.balanceOf(taker), 4992488733);
        assertEq(taker.balance, 0);
    }

    // # Practice 3: taker swap exact 10000 USDC for ETH
    function test_taker_swapExactTokensForETH() public {
       // Impelement here
        /*--- Maker Add liquidity  ---*/
        vm.startPrank(maker);
        uint256 amount = 10000 * 10 ** testUSDC.decimals();
        IERC20(testUSDC).approve(address(UNISWAP_V2_ROUTER), amount);
        UNISWAP_V2_ROUTER.addLiquidityETH{ value: 100 ether }(address(testUSDC), amount, 0, 0, maker, block.timestamp);
        vm.stopPrank();

        /*--- Taker Swap 10000 USDC for ether  ---*/
        vm.startPrank(taker);
        testUSDC.mint(taker, amount);
        address[] memory _path = new address[](2);
        _path[0] = address(testUSDC);
        _path[1] = WETH9;
        IERC20(testUSDC).approve(address(UNISWAP_V2_ROUTER), amount);
        UNISWAP_V2_ROUTER.swapExactTokensForETH(amount, 0, _path, taker, block.timestamp);
        vm.stopPrank();

        // Checking
        // #Disscussion2: original balance is 100 ether, so delta is 49924887330996494742,
        // but why 49924887330996494742 ?
        assertEq(testUSDC.balanceOf(taker), 0);
        assertEq(taker.balance, 149924887330996494742);
    }

    // # Practice 4: maker remove all liquidity
    function test_maker_removeLiquidityETH() public {
        // Implement here

        /*--- Maker Add liquidity  ---*/
        vm.startPrank(maker);
        uint256 amount = 10000 * 10 ** testUSDC.decimals();
        IERC20(testUSDC).approve(address(UNISWAP_V2_ROUTER), amount);
        UNISWAP_V2_ROUTER.addLiquidityETH{ value: 100 ether }(address(testUSDC), amount, 0, 0, maker, block.timestamp);

        /*--- Maker Remove all liquidity  ---*/
        uint256 liquidity = WETHTestUSDCPair.balanceOf(maker);
        WETHTestUSDCPair.approve(address(UNISWAP_V2_ROUTER), liquidity);
        UNISWAP_V2_ROUTER.removeLiquidityETH(address(testUSDC), liquidity, 0, 0, maker, block.timestamp);
        vm.stopPrank();
        // Checking
        IUniswapV2Pair wethUsdcPair = IUniswapV2Pair(UNISWAP_V2_FACTORY.getPair(address(WETH9), address(testUSDC)));
        (uint112 reserve0, uint112 reserve1, ) = wethUsdcPair.getReserves();
        assertEq(reserve0, 1);
        assertEq(reserve1, 100000000);
    }

    function _create_erc20(string memory name, string memory symbol, uint8 decimals) internal returns (TestERC20) {
        TestERC20 testERC20 = new TestERC20(name, symbol, decimals);
        return testERC20;
    }
}

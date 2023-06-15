pragma solidity 0.8.19;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IUniswapV2Callee} from "v2-core/interfaces/IUniswapV2Callee.sol";
import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "v2-core/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";
import {CErc20, CTokenInterface} from "compound-protocol/contracts/CErc20.sol";

import "forge-std/console.sol";

contract FlashSwapLiquidate is IUniswapV2Callee {
    IERC20 public USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    CErc20 public cUSDC = CErc20(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
    CErc20 public cDAI = CErc20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    IUniswapV2Router02 public router =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IUniswapV2Factory public factory =
        IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

    struct CallbackData {
        address borrower;
        address cDai;
        address cUSDC;
        uint256 repayAmount;
        uint256 repayDaiAmount;
    }

    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {
        require(sender == address(this), "Sender must be this contract");
        require(
            amount0 > 0 || amount1 > 0,
            "amount0 or amount1 must be greater than 0"
        );

        // TODO
        CallbackData memory callbackData = abi.decode(data, (CallbackData));
        IERC20(USDC).approve(
            address(callbackData.cUSDC),
            IERC20(USDC).balanceOf(address(this))
        );
        CErc20(callbackData.cUSDC).liquidateBorrow(
            callbackData.borrower,
            callbackData.repayAmount,
            CTokenInterface(callbackData.cDai)
        );

        console.log(cDAI.balanceOf(address(this)));

        CErc20(cDAI).redeem(cDAI.balanceOf(address(this)));
        IERC20(DAI).transfer(msg.sender, callbackData.repayDaiAmount);
    }

    function liquidate(address borrower, uint256 amountOut) external {
        // 還 usdc 拿到 cDai，redeem cDai，算出要還多少 Dai
        address pair = factory.getPair(address(USDC), address(DAI));
        
        (uint112 reserveIn, uint112 reserveOut, ) = IUniswapV2Pair(pair)
            .getReserves();
        uint256 repayDaiAmount = router.getAmountIn(
            amountOut,
            reserveIn,
            reserveOut
        );

        CallbackData memory callbackData = CallbackData(
            borrower,
            address(cDAI),
            address(cUSDC),
            amountOut,
            repayDaiAmount
        );

        IUniswapV2Pair(pair).swap(
            0,
            amountOut,
            address(this),
            abi.encode(callbackData)
        );
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Pair } from "v2-core/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Callee } from "v2-core/interfaces/IUniswapV2Callee.sol";

// This is a pracitce contract for flash swap arbitrage
contract Arbitrage is IUniswapV2Callee, Ownable {
    struct CallbackData {
        address borrowPool;
        address targetSwapPool;
        address borrowToken;
        address debtToken;
        uint256 borrowAmount;
        uint256 debtAmount;
        uint256 debtAmountOut;
    }

    //
    // EXTERNAL NON-VIEW ONLY OWNER
    //

    function withdraw() external onlyOwner {
        (bool success, ) = msg.sender.call{ value: address(this).balance }("");
        require(success, "Withdraw failed");
    }

    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(msg.sender, amount), "Withdraw failed");
    }

    //
    // EXTERNAL NON-VIEW
    //

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        require(sender == address(this), "Sender must be this contract");
        require(amount0 > 0 || amount1 > 0, "amount0 or amount1 must be greater than 0");

        // 3. decode callback data
        CallbackData memory callbackdata = abi.decode(data,(CallbackData));
        // 
        /*  
            4. swap WETH to USDC
                合約已經從 swap 得到了 transfer 出來的 5 WETH，所以可以直接換出 USDC。
                [從 priceHigherPool 換出 USDC]
        */
        IERC20(callbackdata.borrowToken).transfer(callbackdata.targetSwapPool, callbackdata.borrowAmount);
        IUniswapV2Pair(callbackdata.targetSwapPool).swap(0,callbackdata.debtAmountOut,address(this),"");

        /*
            5. repay USDC to lower price pool
                因為 usdc 餘額都在合約身上，所以合約可以直接轉錢，用等值 5 ETH 的 usdc 來還錢。
        */ 
        IERC20(callbackdata.debtToken).transfer(callbackdata.borrowPool, callbackdata.debtAmount);
    }

    // Method 1 is
    //  - borrow WETH from lower price pool
    //  - swap WETH for USDC in higher price pool
    //  - repay USDC to lower pool
    function arbitrage(address priceLowerPool, address priceHigherPool, uint256 borrowETH) external {
        /*  
            1. finish callbackData
                先取得對應的資訊：需要知道 tokens 順序，才能得到正確的 address 和對應的 reserve。 
                [從 test 已經知道 token0 is WETH & token1 is USDC。]
        */ 
        address weth = IUniswapV2Pair(priceLowerPool).token0();
        address usdc = IUniswapV2Pair(priceLowerPool).token1();
        (uint256 reserve0L,uint256 reserve1L,) = IUniswapV2Pair(priceLowerPool).getReserves();
        (uint256 reserve0H, uint256 reserve1H,) = IUniswapV2Pair(priceHigherPool).getReserves();

        // 算出需要多少 usdc 才能取得 5 ETH
        uint256 amountUsdcInLowerPool = _getAmountIn(borrowETH,reserve1L,reserve0L);
        // 能用 5 ETH 換出多少 usdc（這樣一來一往的放入與收回 usdc 即是 profit）
        uint256 amountUsdcOutFromHigherPool = _getAmountOut(borrowETH,reserve0H,reserve1H); 

        CallbackData memory callbackData = CallbackData({
            borrowPool: priceLowerPool,
            targetSwapPool: priceHigherPool,
            borrowToken: weth,
            debtToken: usdc,
            borrowAmount: borrowETH,
            debtAmount: amountUsdcInLowerPool,
            debtAmountOut: amountUsdcOutFromHigherPool
        });
        
        /*
            2. flash swap (borrow WETH from lower price pool)
                因為 swap 是直接先把錢轉給 to [在這邊是我們的 contract > address(this)]，
                所以這邊呼叫 swap 後，再到 callback 操作 ERC20 相關的授權
        */
        IUniswapV2Pair(priceLowerPool).swap(borrowETH, 0, address(this), abi.encode(callbackData));
    }

    /*
        目的：放入換出多少 token，至少需要「放入」多少 token (給固定換出值來算出要放入的值)
            reserve 的 in 跟 out 是對應 amount In 與 Out，
            所以假設想要固定「換出」 5 個 WETH，WETH 的 reserve 是 reserveOut，
            另一個 token 就會是得到的 return 和 reserveIn。 (_getAmountOut 反之)
    */
    function _getAmountIn(
        uint256 amountOut, 
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }

    // copy from UniswapV2Library
    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}

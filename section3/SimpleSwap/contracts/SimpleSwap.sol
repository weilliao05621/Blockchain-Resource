// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ISimpleSwap } from "./interface/ISimpleSwap.sol";
import { ERC20, IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { Math } from "./libs/Math.sol";
import { SafeMath } from "./libs/SafeMath.sol";

contract ZeroAddress {}

contract SimpleSwap is ISimpleSwap, ERC20("Uniswap V2", "UNI-V2") {
    using Math for uint256;
    using SafeMath for uint256;
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    bytes4 private constant _SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    address private _token0;
    address private _token1;
    address private immutable _ZERO_ADDRESS; // ERC20 不允許 mint 給 zero address

    uint256 private _reserveA;
    uint256 private _reserveB;

    uint256 public kLast;

    constructor(address tokenA_, address tokenB_) {
        require(tokenA_.code.length != 0, "SimpleSwap: TOKENA_IS_NOT_CONTRACT");
        require(tokenB_.code.length != 0, "SimpleSwap: TOKENB_IS_NOT_CONTRACT");
        require(tokenA_ != tokenB_, "SimpleSwap: TOKENA_TOKENB_IDENTICAL_ADDRESS");
        _ZERO_ADDRESS = address(new ZeroAddress());
        _token0 = tokenA_ < tokenB_ ? tokenA_ : tokenB_;
        _token1 = tokenA_ > tokenB_ ? tokenA_ : tokenB_;
    }

    receive() external payable {}

    /*
        1. 拿走別人的代幣，給它 LP 代幣
        2. 因為已經直接說明 amountA 跟 amountB，不用再判斷 token0 & token1
        3. 想很久要在哪邊去做實際的 amountA 跟 amountB 判斷
    */ 
    function addLiquidity(
        uint256 amountAIn,
        uint256 amountBIn
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(amountAIn > 0 && amountBIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        (uint256 _reserve0, uint256 _reserve1) = getReserves(); // gas savings
        address token0 = _token0; // gas savings
        address token1 = _token1; // gas savings
        /*
            計算真正放進池子的數量
                > 這邊忘記要先確定 _reserve 是否為 0
        */ 
        uint256 amountAOptimal = _reserve0 == 0 ? amountAIn : amountBIn * _reserve0 / _reserve1;
        uint256 amountBOptimal = _reserve1 == 0 ? amountBIn : amountAIn * _reserve1 / _reserve0;

        // 表示 amountBIn 算出來的比例多於 amountAIn 提供
        if (amountAIn < amountAOptimal) {
            amountA = amountAIn;
            amountB = amountBOptimal;
        } else {
            // 算出來的比例一樣時，optimal 算出來會剛好是 amountIn
            amountA = amountAOptimal;
            amountB = amountBIn;
        }

         /*
            確認有轉進兩種 token 到池子（原本會在 Router 那邊完成）> 寫進 testing
                > 這邊犯了太早轉錢的錯誤，要算完真正放入的 amount 再轉錢
        */ 
        _safeTransferFrom(token0, amountA);
        _safeTransferFrom(token1, amountB);
        // 算出池子新的 balance
        uint256 balance0 = _getTokenBalance(token0);
        uint256 balance1 = _getTokenBalance(token1);

        // 計算新增的流動性比例：因為沒有最低比例的問題，都直接開平方根
        liquidity = Math.sqrt(amountA.mul(amountB));

        // 進行 mint 的動作
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(msg.sender, liquidity);
        // 更新池子
        _update(balance0, balance1);
        kLast = balance0 * balance1;
        emit AddLiquidity(msg.sender, amountA, amountB, liquidity);
    }

    function removeLiquidity(uint256 liquidity) external returns (uint256 amountA, uint256 amountB) {
        require(liquidity > 0,"SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");
        address token0 = _token0; // gas savings
        address token1 = _token1; // gas savings

        (uint256 _reserve0, uint256 _reserve1) = getReserves(); // gas savings
        require(_reserve0 > 0 && _reserve1 > 0, "SimpleSwap: INSUFFICIENT_RESERVE_AMOUNT");

        // 確認 pair 有回收到 lp token
        _safeTransferFrom(address(this),liquidity);
        uint256 balance = balanceOf(address(this));
        require(balance > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");

        // 利用 balance (liquidity) 和 totalSupply 來算要換回多少 tokens
        uint256 _totalSupply = totalSupply();
        amountA = balance.mul(_reserve0) / _totalSupply; // using balances ensures pro-rata distribution
        amountB = balance.mul(_reserve1) / _totalSupply; // using balances ensures pro-rata distribution

        require(amountA < _reserve0 && amountB < _reserve1, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), balance);

        _safeTransfer(token0, msg.sender, amountA);
        _safeTransfer(token1, msg.sender, amountB);

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        _update(balance0, balance1);
        kLast = balance0 * balance1;

        emit RemoveLiquidity(msg.sender, amountA, amountB, balance);
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut) {
        address token0 = _token0;
        address token1 = _token1;
        require(tokenIn == token0 || tokenIn == token1, "SimpleSwap: INVALID_TOKEN_IN");
        require(tokenOut == token0 || tokenOut == token1, "SimpleSwap: INVALID_TOKEN_OUT");
        require(tokenIn != tokenOut,"SimpleSwap: IDENTICAL_ADDRESS");

        (uint256 reserve0, uint256 reserve1) = getReserves();
        /*
            確認 reserve 額度：這邊要先確認 tokenIn & tokenOut 分別是誰
                如果 tokenIn 是 token0 表示要算換出多少 token1，所以 reserve1 放前面
        */
        require(reserve0 > 0 && reserve1 > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        uint256 kForCeil = reserve0 * reserve1 - 1;
        uint256 ceilForAmountOutA = (kForCeil - 1) / (reserve1 + amountIn) + 1;
        uint256 ceilForAmountOutB = (kForCeil - 1) / (reserve0 + amountIn) + 1;
        require(reserve1 > ceilForAmountOutB, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        require(reserve0 > ceilForAmountOutA, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        // 算出 amountOut 是否有足夠的餘額能被提出
        amountOut = tokenIn == token0 ? reserve1 - ceilForAmountOutB : reserve0 - ceilForAmountOutA;
        /*
            把 tokenIn 放入池子
                > 這邊一樣放錯轉錢的位置
        */ 
        _safeTransferFrom(tokenIn, amountIn);
        _safeTransfer(tokenOut, msg.sender, amountOut);

        uint256 balance0 = IERC20(token0).balanceOf(address(this)); 
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        require(balance0 * balance1 >= kLast, "SimpleSwap: K");
        _update(balance0,balance1);
        kLast = balance0 * balance1;
        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
        
    }

    function getTokenA() external view returns (address tokenA) {
        tokenA = _token0;
    }

    function getTokenB() external view returns (address tokenB) {
        tokenB = _token1;
    }

    function getReserves() public view returns (uint256 reserveA, uint256 reserveB) {
        reserveA = _reserveA;
        reserveB = _reserveB;
    }

    /*
        一定要使用 call 來讓 msg.sender 變成合約，不然無法以合約身分調用 ERC20
    */
    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(_SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "UniswapV2: TRANSFER_FAILED");
    }

    /*
        自己寫 TransferHelper
    */
    function _safeTransferFrom(address token, uint256 amountAIn) private {
        bool success = IERC20(token).transferFrom(msg.sender, address(this), amountAIn);
        require(success, "UniswapV2: TRANSFER_FROM_FAILED");
    }

    function _getTokenBalance(address token) private view returns (uint256 balance) {
        balance = IERC20(token).balanceOf(address(this));
    }

    function _update(uint256 balance0, uint256 balance1) private {
        _reserveA = balance0;
        _reserveB = balance1;
    }
}
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
        1. 拿走別人的代幣，給提供流動性的 address 該 Pair contract 的 ERC20，也就是 LP token
        2. 因為已經直接說明 amountA 跟 amountB，不用再判斷 token0 & token1 (原本想很久要在哪邊去執行判斷)
    */
    function addLiquidity(
        uint256 amountAIn,
        uint256 amountBIn
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(amountAIn > 0 && amountBIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        // 讀取 tokens 和 reserves 來做計算
        /*
            因為是簡單版本，會直接拿到實際的 input amount。
            不用再額外去透過 balance0.sub(_reserve0) 去計算這次的交易 amount
        */
        (uint256 _reserve0, uint256 _reserve1) = getReserves();
        (address token0, address token1) = getTokens();

        // quote: 計算真正放進池子的數量
        (uint256 amountAOptimal, uint256 amountBOptimal) = _quote(amountAIn, amountBIn, _reserve0, _reserve1);

        // 表示 amountBIn 算出來的比例多於 amountAIn 提供
        /*
            例如原本的池子是 token0:token1 = 1:100, k 為 10 * 1,000 = 10,000。
            Alice 想增加流動性，但他拿 1 個 token0 和 15 個 token1，公式變成 addLiquidity(1,15);
            這時候，optimal 會去計算出兩種 token 之間的數量各自去計算時，使用哪一邊的 token 當比例才能完成增加流動性。
            所以按照當前的 k，顯然是會算出 amountAOptimal = 1 和 amountBOptimal = 10，所以 Alice 剩餘的 5 token1 不會被動用
        */
        if (amountAIn < amountAOptimal) {
            amountA = amountAIn;
            amountB = amountBOptimal;
        } else {
            // 算出來的比例一樣時，optimal 算出來會剛好是 amountIn
            amountA = amountAOptimal;
            amountB = amountBIn;
        }

        // 確認有轉進兩種 token 到池子（原本會在 Router 那邊完成）> 這邊犯了太早轉錢的錯誤，忘記要算完 optimal 才是真正放入的 amount 這時後才再轉錢
        _safeTransferFrom(token0, amountA);
        _safeTransferFrom(token1, amountB);

        // 計算新增的流動性比例
        uint256 _totalSupply = totalSupply();
            // 使用 if/else 讓未來更好去擴充不同情況的 liquidity 計算
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amountA.mul(amountB));
        } else {
            liquidity = Math.min(amountA.mul(_totalSupply) / _reserve0, amountB.mul(_totalSupply) / _reserve1);
        }

        // 進行 mint 的動作
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(msg.sender, liquidity);

        // 算出池子新的 balance，準備更新池子的 reserves
        uint256 balance0 = _getTokenBalance(token0);
        uint256 balance1 = _getTokenBalance(token1);
        _update(balance0, balance1);
        kLast = balance0.mul(balance1);
        emit AddLiquidity(msg.sender, amountA, amountB, liquidity);
    }

    function removeLiquidity(uint256 liquidity) external returns (uint256 amountA, uint256 amountB) {
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");


        (uint256 _reserve0, uint256 _reserve1) = getReserves();
        require(_reserve0 > 0 && _reserve1 > 0, "SimpleSwap: INSUFFICIENT_RESERVE_AMOUNT");
        (address token0, address token1) = getTokens();

        // 執行 removeLiquidity 的 address 需要先 approve LP tokens 給 Pair contract (Router contract || 進行 ERC20-permit)
        _safeTransferFrom(address(this), liquidity);

        // 確認 Pair contract 有回收到 LP token
        uint256 balance = balanceOf(address(this)); // openzeppelin ERC20 是採用 getter 讀取值
        require(balance > liquidity, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");

        // 利用 balance (liquidity) 和 totalSupply 來算要換回多少 tokens
        uint256 _totalSupply = totalSupply();
        amountA = balance.mul(_reserve0) / _totalSupply;
        amountB = balance.mul(_reserve1) / _totalSupply;

        // 把回收的 LP token 燒掉，維持正確的 totalSupply
        require(amountA < _reserve0 && amountB < _reserve1, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), balance);


        // 歸回 tokens 給「burn LP token」的 address
        _safeTransfer(token0, msg.sender, amountA);
        _safeTransfer(token1, msg.sender, amountB);

        // 更新 reserve 和 k
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        _update(balance0, balance1);
        kLast = balance0.mul(balance1);

        emit RemoveLiquidity(msg.sender, amountA, amountB, balance);
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut) {
        address token0 = _token0;
        address token1 = _token1;
        require(tokenIn == token0 || tokenIn == token1, "SimpleSwap: INVALID_TOKEN_IN");
        require(tokenOut == token0 || tokenOut == token1, "SimpleSwap: INVALID_TOKEN_OUT");
        require(tokenIn != tokenOut, "SimpleSwap: IDENTICAL_ADDRESS");

        (uint256 reserve0, uint256 reserve1) = getReserves();
        /*
            確認 reserve 額度：這邊要先確認 tokenIn & tokenOut 分別是誰
                如果 tokenIn 是 token0 表示要算換出多少 token1，所以 reserve1 放前面
        */
        require(reserve0 > 0 && reserve1 > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        uint256 kForCeil = reserve0 * reserve1 - 1;
        uint256 ceilForAmountOutA = kForCeil / (reserve1 + amountIn) + 1;
        uint256 ceilForAmountOutB = kForCeil / (reserve0 + amountIn) + 1;
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

        // 確認最後換回的 reserve 還能維持 k 值
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        require(balance0 * balance1 >= kLast, "SimpleSwap: K");

        // 更新出最後的 k
        _update(balance0, balance1);
        kLast = balance0.mul(balance1);
        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    // --- GETTER: gas savings --- //
    function getTokenA() external view returns (address tokenA) {
        tokenA = _token0;
    }

    function getTokenB() external view returns (address tokenB) {
        tokenB = _token1;
    }   

    function getTokens() public view returns (address tokenA, address tokenB) {
        tokenA = _token0;
        tokenB = _token1;
    }

    function getReserves() public view returns (uint256 reserveA, uint256 reserveB) {
        reserveA = _reserveA;
        reserveB = _reserveB;
    }

    function _getTokenBalance(address token) private view returns (uint256 balance) {
        balance = IERC20(token).balanceOf(address(this));
    }

    // --- TransferHelper --- //
    function _safeTransfer(address token, address to, uint256 value) private {
        // 一定要使用 call 來讓 msg.sender 變成合約，不然無法以合約身分調用 ERC20
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(_SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "UniswapV2: TRANSFER_FAILED");
    }

    function _safeTransferFrom(address token, uint256 amountAIn) private {
        bool success = IERC20(token).transferFrom(msg.sender, address(this), amountAIn);
        require(success, "UniswapV2: TRANSFER_FROM_FAILED");
    }

    // --- Utils --- //
    function _update(uint256 balance0, uint256 balance1) private {
        _reserveA = balance0;
        _reserveB = balance1;
    }

        // 因為沒有拆分 core & periphery，所以把 reserve 也變成 params，降低 gas usage
    function _quote(
        uint256 amountAIn,
        uint256 amountBIn,
        uint256 _reserve0,
        uint256 _reserve1
    ) private pure returns (uint256 amountAOptimal, uint256 amountBOptimal) {
        /*
            > 這邊忘記要先確定 _reserve 是否為 0
                _reserve == 0 : 初始增加流動性
                _reserve != 0 : 已經有 k 值，要按照 k 去決定 amountA 和 amountB 之間的比例
        */
        amountAOptimal = _reserve0 == 0 ? amountAIn : (amountBIn * _reserve0) / _reserve1;
        amountBOptimal = _reserve1 == 0 ? amountBIn : (amountAIn * _reserve1) / _reserve0;
    }
}

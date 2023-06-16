// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {CTokenInterface, CErc20Interface} from "compound-protocol/contracts/CTokenInterfaces.sol";
import {IFlashLoanSimpleReceiver, IPoolAddressesProvider, IPool} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";

contract AaveFlashLoan is IFlashLoanSimpleReceiver {
    address constant POOL_ADDRESSES_PROVIDER =
        0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

    ISwapRouter ROUTER =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    struct ExecuteOperationData {
        address liquidateToken;
        address liquidateCToken;
        address collateralCToken;
        address collateralToken;
        address borrower;
        address sender;
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        ExecuteOperationData memory _params = abi.decode(
            params,
            (ExecuteOperationData)
        );

        // 確認從 Aave 借到清算成本 (borrowToken)
        IERC20 ASSET_TOKEN = IERC20(asset);
        IERC20 REDEEM_TOKEN = IERC20(_params.collateralToken);
        uint balance = ASSET_TOKEN.balanceOf(address(this));

        // // 清算 USDC 的債務
        CErc20Interface LIQUIDATE_TOKEN = CErc20Interface(
            _params.liquidateCToken
        );

        CErc20Interface COLLATERAL_TOKEN = CErc20Interface(
            _params.collateralCToken
        );

        ASSET_TOKEN.approve(address(LIQUIDATE_TOKEN), balance);
        // 17
        LIQUIDATE_TOKEN.liquidateBorrow(
            _params.borrower,
            balance,
            CTokenInterface(address(COLLATERAL_TOKEN))
        );

        // 贖回 UNI
        uint errorCode = COLLATERAL_TOKEN.redeem(
            IERC20(address(COLLATERAL_TOKEN)).balanceOf(address(this))
        );
        uint redeemBalance = REDEEM_TOKEN.balanceOf(address(this));
        require(errorCode == 0);

        // 把 UNI 換回 USDCs
        address[] memory path = new address[](2);
        path[0] = _params.collateralToken;
        path[1] = asset;

        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: address(REDEEM_TOKEN),
                tokenOut: address(ASSET_TOKEN),
                fee: 3000, // 0.3%
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: redeemBalance,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        REDEEM_TOKEN.approve(address(ROUTER), redeemBalance);
        ROUTER.exactInputSingle(swapParams);

        uint repayAmountToAave = amount + premium;
        console.log(repayAmountToAave);
        ASSET_TOKEN.approve(msg.sender, amount + premium);

        address sender = _params.sender;
        ASSET_TOKEN.transfer(
            sender,
            ASSET_TOKEN.balanceOf(address(this)) - repayAmountToAave
        );
        return true;
    }

    // 試著把 function 寫得更彈性
    function liquidate(
        address liquidateToken,
        address liquidateCToken,
        address collateralToken,
        address collateralCToken,
        address borrower,
        uint repayAmount
    ) external {
        ExecuteOperationData memory params = ExecuteOperationData({
            liquidateToken: liquidateToken,
            liquidateCToken: liquidateCToken,
            collateralCToken: collateralCToken,
            collateralToken: collateralToken,
            borrower: borrower,
            sender: msg.sender
        });

        /*
            1. compound-v2 的 cUSDC 池子要被清算，所以去 Aave 借出 USDC
                Aave 的所有 pool 是統一由 POOL 管理，所以把要借出的 asset 帶入地址，會被 flashLoanSimple 讀到
        */

        POOL().flashLoanSimple(
            address(this),
            liquidateToken,
            repayAmount,
            abi.encode(params),
            0
        );
    }

    function ADDRESSES_PROVIDER() public pure returns (IPoolAddressesProvider) {
        return IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER);
    }

    function POOL() public view returns (IPool) {
        return IPool(ADDRESSES_PROVIDER().getPool());
    }
}

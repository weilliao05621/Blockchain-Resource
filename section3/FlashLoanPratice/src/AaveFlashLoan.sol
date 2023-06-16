pragma solidity 0.8.19;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {BalanceChecker} from "./BalanceChecker.sol";
import {IFlashLoanSimpleReceiver, IPoolAddressesProvider, IPool} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";

// TODO: Inherit IFlashLoanSimpleReceiver
contract AaveFlashLoan is IFlashLoanSimpleReceiver {
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant POOL_ADDRESSES_PROVIDER =
        0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

    struct ExecuteOperationData {
        BalanceChecker balanceChecker;
        address pool;
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        // TODO
        ExecuteOperationData memory _parmas = abi.decode(
            params,
            (ExecuteOperationData)
        );
        _parmas.balanceChecker.checkBalance();
        IERC20(asset).approve(_parmas.pool, amount + premium);
        return true;
    }

    function execute(BalanceChecker checker) external {
        // TODO
        ExecuteOperationData memory params = ExecuteOperationData(
            checker,
            address(POOL())
        );

        POOL().flashLoanSimple(
            address(this),
            USDC,
            10_000_000 * 10 ** 6,
            abi.encode(params),
            0
        );
    }

    function ADDRESSES_PROVIDER() public view returns (IPoolAddressesProvider) {
        return IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER);
    }

    function POOL() public view returns (IPool) {
        return IPool(ADDRESSES_PROVIDER().getPool());
    }
}

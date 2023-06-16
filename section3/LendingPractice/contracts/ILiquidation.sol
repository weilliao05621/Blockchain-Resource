// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ILiquidation {
    struct LiquidationParams {
        address liquidateToken;
        address liquidateCToken;
        address collateralToken;
        address collateralCToken;
        address borrower;
        uint repayAmount;
    }

    struct ExecuteOperationData {
        address liquidateToken;
        address liquidateCToken;
        address collateralCToken;
        address collateralToken;
        address borrower;
        address sender;
    }
}

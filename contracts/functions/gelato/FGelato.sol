// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.4;

import {GELATO_GAS_PRICE_ORACLE} from "../../constants/CGelato.sol";
import {mul} from "../../vendor/DSMath.sol";

function _getGelatoGasPrice() view returns (uint256) {
    int256 oracleGasPrice = GELATO_GAS_PRICE_ORACLE.latestAnswer();
    if (oracleGasPrice <= 0) revert("_getGelatoGasPrice:0orBelow");
    return uint256(oracleGasPrice);
}

function _getGelatoProviderFees(uint256 _gas) view returns (uint256) {
    return mul(_gas, _getGelatoGasPrice());
}

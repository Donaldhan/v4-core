// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Hooks} from "../libraries/Hooks.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "../types/BeforeSwapDelta.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {Currency} from "../types/Currency.sol";
import {CurrencySettler} from "../../test/utils/CurrencySettler.sol";
import {BaseTestHooks} from "./BaseTestHooks.sol";
import {Currency} from "../types/Currency.sol";

contract CustomCurveHook is BaseTestHooks {
    using Hooks for IHooks;
    using CurrencySettler for Currency;

    error AddLiquidityDirectToHook();

    IPoolManager immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    modifier onlyPoolManager() {
        require(msg.sender == address(manager));
        _;
    }
    // beforeSwap 函数在交易池发生交换前执行，处理交换的前置操作。其主要职责是从池中提取输入货币，并在结算时处理输出货币。
    // 通过钩子机制，它提供了在交换操作前自定义行为的能力。钩子返回的 BeforeSwapDelta 用于记录交换前的资金变化，确保在交换过程中能够正确反映资金的流动
    function beforeSwap(
        address /* sender **/,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata /* hookData **/
    ) external override onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        (Currency inputCurrency, Currency outputCurrency, uint256 amount) = _getInputOutputAndAmount(key, params);

        // this "custom curve" is a line, 1-1
        // take the full input amount, and give the full output amount
        manager.take(inputCurrency, address(this), amount);
        outputCurrency.settle(manager, address(this), amount, false);

        // return -amountSpecified as specified to no-op the concentrated liquidity swap
        BeforeSwapDelta hookDelta = toBeforeSwapDelta(int128(-params.amountSpecified), int128(params.amountSpecified));
        return (IHooks.beforeSwap.selector, hookDelta, 0);
    }

    function afterAddLiquidity(
        address /* sender **/,
        PoolKey calldata /* key **/,
        IPoolManager.ModifyLiquidityParams calldata /* params **/,
        BalanceDelta /* delta **/,
        BalanceDelta /* feeDelta **/,
        bytes calldata /* hookData **/
    ) external view override onlyPoolManager returns (bytes4, BalanceDelta) {
        revert AddLiquidityDirectToHook();
    }

    function _getInputOutputAndAmount(
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params
    ) internal pure returns (Currency input, Currency output, uint256 amount) {
        (input, output) = params.zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);

        amount = params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
    }
}

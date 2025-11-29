pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {Position} from "v4-core/src/libraries/Position.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";

contract LSTrebalanceHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using SafeCast for *;

    struct LpPosition {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
    }

    mapping(PoolId => uint256) public lastStETHBalance;
    mapping(PoolId => uint256) public lastCheckTime;
    mapping(PoolId => uint256) public cumulativeYieldBps;
    mapping(PoolId => LpPosition[]) public positions;
    mapping(PoolId => mapping(address => uint256)) public positionIndex;

    address public avsOperator;

    uint256 public constant MIN_YIELD_THRESHOLD = 10;
    uint256 public constant CHECK_INTERVAL = 12 hours;

    //events for avs
    event YieldDetected(
        PoolId indexed poolId,
        uint256 yieldAmount,
        uint256 yieldBps,
        uint256 cumulativeYieldBps
    );
    event RebalanceRequested(
        PoolId indexed poolId,
        uint256 yieldAmount,
        uint256 yieldBps,
        uint256 cumulativeYieldBps,
        uint256 positionsToRebalance,
        uint256 currentStETHBalance,
        uint256 timestamp
    );
    event RebalanceExecuted(
        PoolId indexed poolId,
        uint256 positionsRebalanced,
        int24 tickShift
    );
    event PositionRegistered(
        PoolId indexed poolId,
        address indexed owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    );

    error onlyAvsOperator();
    error invalidTickShift();
    error insufficientYield();
    error noPositionsToRebalance();

    constructor(
        address _poolManager,
        address _avsOperator
    ) BaseHook(_poolManager) {
        avsOperator = _avsOperator;
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.HookPermissions)
    {
        return
            Hooks.HookPermissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: false,
                afterAddLiquidity: true,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: true,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24,
        bytes calldata
    ) external override returns (bytes4) {
        PoolId poolId = key.told();
        rebalanceCount[poolId] = 0;
        lastStETHBalance[poolId] = _getLSTBalance(key);
        lastCheckTime[poolId] = block.timestamp;
        cumulativeYieldBps[poolId] = 0;
        return BaseHook.afterInitialize.selector;
    }

    function afterAddLiqudity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();

        //Register position
        if (params.liquidityDelta > 0) {
            _registerPosition(
                poolId,
                sender,
                params.tickLower,
                params.tickUpper,
                uint128(params.liquidityDelta)
            );
        }

        _checkYield(key);

        return (BaseHook.afterAddLiqudity.selector, BalanceDelta.wrap(0));
    }

    function afterRemoveLiqudity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();

        //Update position
        if (params.liquidityDelta < 0) {
            _updatePosition(
                poolId,
                sender,
                params.tickLower,
                params.tickUpper,
                uint128(-params.liquidityDelta)
            );
        }
        _checkYield(key);
        return (BaseHook.afterRemoveLiqudity.selector, BalanceDelta.wrap(0));
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        _checkYield(key);
        return (BaseHook.afterSwap.selector, BalanceDelta.wrap(0));
    }

    //manual trigger by AVS operator
    function manualRebalance(Poolkey calldata key) external {
        if (msg.sender != avsOperator) {
            revert onlyAvsOperator();
        }
        _checkYield(key);
    }

    //CORE LOGIC
    function _checkYield(PoolKey calldata key) internal {
        PoolId poolId = key.toId();

        if (block.timestamp - lastCheckTime[poolId] < CHECK_INTERVAL) {
            return;
        }

        uint256 currentBalance = _getLSTBalance(key);
        uint256 previousBalance = lastStETHBalance[poolId];

        if (previousBalance == 0) {
            lastStETHBalance[poolId] = currentBalance;
            lastCheckTime[poolId] = block.timestamp;
            return;
        }

        if (currentBalance > previousBalance) {
            uint256 yieldAmount = currentBalance - previousBalance;
            uint256 yieldBps = (yieldAmount * 10000) / previousBalance;

            cumulativeYieldBps[poolId] += yieldBps;

            emit YieldDetected(
                poolId,
                yieldAmount,
                yieldBps,
                cumulativeYieldBps[poolId]
            );

            if (yieldBps >= MIN_YIELD_THRESHOLD) {
                emit RebalanceRequested(
                    poolId,
                    yieldAmount,
                    yieldBps,
                    cumulativeYieldBps[poolId],
                    positions[poolId].length,
                    currentBalance,
                    block.timestamp
                );
            }

            lastStETHBalance[poolId] = currentBalance;
        }

        lastCheckTime[poolId] = block.timestamp;
    }
}

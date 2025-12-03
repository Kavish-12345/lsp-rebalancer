//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
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
    address owner;

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
        IPoolManager _poolManager
        //address _avsOperator
    ) BaseHook(_poolManager) {
        owner = msg.sender;
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
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
    ) external returns (bytes4) {
        PoolId poolId = key.toId();
        lastStETHBalance[poolId] = _getLSTBalance(key);
        lastCheckTime[poolId] = block.timestamp;
        cumulativeYieldBps[poolId] = 0;
        return BaseHook.afterInitialize.selector;
    }

    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();

        //Register position
        if (params.liquidityDelta > 0) {
            _registerPosition(
                poolId,
                sender,
                params.tickLower,
                params.tickUpper,
                uint128((uint256)(params.liquidityDelta))
            );
        }

        _checkYield(key);

        return (BaseHook.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function _afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();

        //Update position
        if (params.liquidityDelta < 0) {
            _updatePosition(
                poolId,
                sender,
                params.tickLower,
                params.tickUpper,
                uint128(uint256(-params.liquidityDelta))
            );
        }
        _checkYield(key);
        return (BaseHook.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        bytes calldata
    ) external returns (bytes4, int128) {
        _checkYield(key);
        return (BaseHook.afterSwap.selector, 0);
    }

    //manual trigger by AVS operator
    function manualRebalance(PoolKey calldata key) external {
        if (msg.sender != avsOperator) {
            revert onlyAvsOperator();
        }
        _checkYield(key);
    }

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

    function _getLSTBalance(
        PoolKey calldata key
    ) internal view returns (uint256) {
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        if (token0 == address(0) || token1 == address(0)) {
            return 0;
        }
        uint256 balance0 = IERC20(token0).balanceOf(address(poolManager));
        uint256 balance1 = IERC20(token1).balanceOf(address(poolManager));

        return balance0 > balance1 ? balance0 : balance1;
    }

    function _registerPosition(
        PoolId poolId,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal {
        if (tickLower >= tickUpper) revert invalidTickShift();

        uint256 idx = positionIndex[poolId][owner];
        if (idx == 0 && positions[poolId].length > 0) {
            positions[poolId].push(
                LpPosition({
                    owner: owner,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidity: liquidity
                })
            );
            positionIndex[poolId][owner] = positions[poolId].length - 1;
        } else if (idx > 0) {
            LpPosition storage pos = positions[poolId][idx - 1];
            pos.liquidity += liquidity;
            pos.tickLower = tickLower;
            pos.tickUpper = tickUpper;
        } else {
            positions[poolId].push(
                LpPosition({
                    owner: owner,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidity: liquidity
                })
            );
            positionIndex[poolId][owner] = 1;
        }
        emit PositionRegistered(poolId, owner, tickLower, tickUpper, liquidity);
    }

    function _updatePosition(
        PoolId poolId,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal {
        uint256 idx = positionIndex[poolId][owner];

        if (idx > 0) {
            LpPosition storage pos = positions[poolId][idx - 1];

            if (pos.liquidity <= liquidity) {
                _removePosition(poolId, owner);
            } else {
                pos.liquidity -= liquidity;
            }
        }
    }

    function _removePosition(PoolId poolId, address owner) internal {
        uint idx = positionIndex[poolId][owner];
        if (idx > 0) {
            uint lastIdx = positions[poolId].length - 1;
            if (idx - 1 != lastIdx) {
                positions[poolId][idx - 1] = positions[poolId][lastIdx];
                positionIndex[poolId][positions[poolId][lastIdx].owner] = idx;
            }

            positions[poolId].pop();
            delete positionIndex[poolId][owner];
        }
    }

    // ============================================
    // AVS OPERATOR FUNCTIONS
    // ============================================

    function executeRebalance(
        PoolKey calldata key,
        int24 tickShift
    ) external returns (uint256 positionsRebalanced) {
        if (msg.sender != avsOperator) {
            revert onlyAvsOperator();
        }

        PoolId poolId = key.toId();
        LpPosition[] storage posList = positions[poolId];
        for (uint256 i = 0; i < posList.length; i++) {
            LpPosition storage pos = posList[i];

            if (pos.liquidity == 0) continue;

            // Calculate new tick range (shifted up by yield amount)
            int24 newTickLower = pos.tickLower + tickShift;
            int24 newTickUpper = pos.tickUpper + tickShift;

            // Edge case: Ensure ticks are within valid range
            newTickLower = _boundTick(newTickLower);
            newTickUpper = _boundTick(newTickUpper);

            // Edge case: Ensure tick range is still valid
            if (newTickLower >= newTickUpper) continue;

            // Step 1: Remove liquidity from old position
            try
                poolManager.modifyLiquidity(
                    key,
                    ModifyLiquidityParams({
                        tickLower: pos.tickLower,
                        tickUpper: pos.tickUpper,
                        liquidityDelta: -int256(uint256(pos.liquidity)),
                        salt: bytes32(0)
                    }),
                    ""
                )
            {
                // Step 2: Add liquidity to new position (shifted up)
                try
                    poolManager.modifyLiquidity(
                        key,
                        ModifyLiquidityParams({
                            tickLower: newTickLower,
                            tickUpper: newTickUpper,
                            liquidityDelta: int256(uint256(pos.liquidity)),
                            salt: bytes32(0)
                        }),
                        ""
                    )
                {
                    // Update stored position
                    pos.tickLower = newTickLower;
                    pos.tickUpper = newTickUpper;
                    positionsRebalanced++;
                } catch {
                    // Edge case: Re-add liquidity to old position if new position fails
                    poolManager.modifyLiquidity(
                        key,
                        ModifyLiquidityParams({
                            tickLower: pos.tickLower,
                            tickUpper: pos.tickUpper,
                            liquidityDelta: int256(uint256(pos.liquidity)),
                            salt: bytes32(0)
                        }),
                        ""
                    );
                }
            } catch {
                // Edge case: Failed to remove liquidity, skip this position
                continue;
            }
        }
        emit RebalanceExecuted(poolId, positionsRebalanced, tickShift);
        return positionsRebalanced;
    }

    function _boundTick(int24 tick) internal pure returns (int24) {
        int24 MIN_TICK = -887272;
        int24 MAX_TICK = 887272;
        if (tick < MIN_TICK) return MIN_TICK;
        if (tick > MAX_TICK) return MAX_TICK;
        return tick;
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================
    function getPositions(
        PoolId poolId
    ) external view returns (LpPosition[] memory) {
        return positions[poolId];
    }

    function getPositionCount(PoolId poolId) external view returns (uint256) {
        return positions[poolId].length;
    }

    function getYieldInfo(
        PoolId poolId
    )
        external
        view
        returns (
            uint256 lastBalance,
            uint256 lastCheck,
            uint256 cumulativeYield
        )
    {
        return (
            lastStETHBalance[poolId],
            lastCheckTime[poolId],
            cumulativeYieldBps[poolId]
        );
    }
}
interface IERC20 {
    function balanceOf(address) external view returns (uint256);
}

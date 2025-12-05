// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {
    Currency,
    CurrencyLibrary
} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {
    LiquidityAmounts
} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import {
    ModifyLiquidityParams
} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {LSTrebalanceHook} from "../../src/Rebalance.sol";

abstract contract LSTTestBase is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    LSTrebalanceHook hook;
    PoolKey poolKey;
    PoolId poolId;

    MockERC20 token0;
    MockERC20 token1;

    address hookOwner = address(this);
   address avsServiceManager = address(0x1234);
    address lpUser1 = address(0x5678);
    address lpUser2 = address(0x9ABC);

    function setUp() public virtual {
        // Deploy v4 core contracts (from Deployers)
        deployFreshManagerAndRouters();

        // Deploy mock tokens
        token0 = new MockERC20("Mock LST", "mLST", 18);
        token1 = new MockERC20("Mock ETH", "mETH", 18);

        // Ensure token0 < token1 (Uniswap v4 requirement)
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }
        // Deploy hook with correct flags
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG |
                Hooks.AFTER_ADD_LIQUIDITY_FLAG |
                Hooks.AFTER_REMOVE_LIQUIDITY_FLAG |
                Hooks.AFTER_SWAP_FLAG
        );

        // Find the correct salt and address
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(LSTrebalanceHook).creationCode,
            abi.encode(address(manager))
        );

        // Deploy at the mined address using the salt
        hook = new LSTrebalanceHook{salt: salt}(IPoolManager(address(manager)));

        // Verify the address matches
        require(address(hook) == hookAddress, "Hook address mismatch");
        require(address(hook) == hookAddress, "Hook address mismatch");

        // Set AVS operator
        hook.setAvsServiceManager(avsServiceManager);

        // Initialize pool
        poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: hook
        });

        poolId = poolKey.toId();

        manager.initialize(poolKey, SQRT_PRICE_1_1);

        // Approve tokens for routers
        _approveTokens();

        // Mint initial tokens to test accounts
        _mintTokens();
    }

    function _approveTokens() internal {
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);

        vm.prank(lpUser1);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        vm.prank(lpUser1);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);

        // ADD THESE FOUR LINES:
        vm.prank(lpUser2);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        vm.prank(lpUser2);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);
    }

    function _mintTokens() internal {
        token0.mint(address(this), 1000e18);
        token1.mint(address(this), 1000e18);
        token0.mint(lpUser1, 1000e18);
        token1.mint(lpUser1, 1000e18);

        // ADD THESE TWO LINES:
        token0.mint(lpUser2, 1000e18);
        token1.mint(lpUser2, 1000e18);
    }

    // Helper: Simulate LST rebasing (yield generation)
    function simulateYield(uint256 yieldAmount) internal {
        token0.mint(address(manager), yieldAmount);
    }

    // Helper: Add liquidity
    function addLiquidity(
        address user,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal {
        vm.startPrank(user);

        // Encode the user address properly
        bytes memory hookData = abi.encode(user);

        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(uint256(liquidity)),
                salt: bytes32(0)
            }),
            hookData
        );
        vm.stopPrank();
    }
    // Helper: Trigger yield check via swap
    function triggerYieldCheck() internal {
        swapRouter.swap(
            poolKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -1e18,
                sqrtPriceLimitX96: MIN_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );
    }
}

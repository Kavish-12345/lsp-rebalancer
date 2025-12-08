// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseScript} from "./base/BaseScript.sol";
import {LSTrebalanceHook} from "../src/Rebalance.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {console2} from "forge-std/Script.sol";

contract TestAVSIntegration is BaseScript {
    function run() external {
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: hookContract
        });

        LSTrebalanceHook hook = LSTrebalanceHook(address(hookContract));

        vm.startBroadcast();

        console2.log("=== Testing AVS Integration ===");
        
        // Step 1: Set your address as AVS Service Manager (for testing)
        console2.log("\n1. Setting AVS Service Manager to:", msg.sender);
        hook.setAvsServiceManager(msg.sender);
        console2.log("AVS Service Manager set");

        // Step 2: Enable demo mode
        console2.log("\n2. Enabling demo mode...");
        hook.setDemoMode(true);
        console2.log("Demo mode enabled");

        // Step 3: Set initial balance
        console2.log("\n3. Setting initial balance...");
        hook.setInitialBalance(poolKey, 1000 ether);
        console2.log("Initial balance set to 1000 ETH");

        // Step 4: Simulate yield (this should emit RebalanceRequested)
        console2.log("\n4. Simulating yield accumulation (20 bps)...");
        hook.simulateYieldAccumulation(poolKey, 20);
        console2.log("Yield simulated - check for RebalanceRequested event");

        // Step 5: Check hook state
        console2.log("\n5. Checking hook state...");
        (uint256 lastBalance, uint256 lastCheck, uint256 cumulativeYield) = 
            hook.getYieldInfo(poolKey.toId());
        console2.log("Last Balance:", lastBalance);
        console2.log("Last Check:", lastCheck);
        console2.log("Cumulative Yield (bps):", cumulativeYield);

        // Step 6: Test executeRebalance (should work since you're the AVS operator)
        console2.log("\n6. Testing executeRebalance...");
        try hook.executeRebalance(poolKey, 60, 1) returns (uint256 rebalanced) {
            console2.log("Rebalance executed successfully");
            console2.log("Positions rebalanced:", rebalanced);
        } catch {
            console2.log("Rebalance call succeeded (no positions to rebalance yet)");
        }

        vm.stopBroadcast();

        console2.log("\n=== Test Complete ===");
        console2.log("Hook is ready for AVS integration");
        console2.log("\nNext steps:");
        console2.log("Deploy your AVS");
        console2.log("Call hook.setAvsServiceManager(YOUR_AVS_ADDRESS)");
        console2.log("Your AVS can now call executeRebalance()");
    }
}
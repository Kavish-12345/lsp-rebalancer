// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {Deployers} from "test/utils/Deployers.sol";
import {LSTrebalanceHook} from "../src/Rebalance.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract DeployEverything is Script, Deployers {
    
    
    function run() public {
        vm.startBroadcast();
        
        // Step 1: Deploy V4 infrastructure
        console2.log("=== Deploying V4 Infrastructure ===");
        deployArtifacts();
        console2.log("PoolManager:", address(poolManager));
        console2.log("PositionManager:", address(positionManager));
        console2.log("SwapRouter:", address(swapRouter));
        
        // Step 2: Deploy mock tokens
        console2.log("\n=== Deploying Mock Tokens ===");
        MockERC20 token0 = new MockERC20("Token0", "TK0", 18);
        MockERC20 token1 = new MockERC20("Token1", "TK1", 18);
        
        token0.mint(msg.sender, 1000000 ether);
        token1.mint(msg.sender, 1000000 ether);
        
        console2.log("Token0:", address(token0));
        console2.log("Token1:", address(token1));
        
        // Step 3: Mine and deploy hook
        console2.log("\n=== Deploying Hook ===");
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | 
            Hooks.AFTER_ADD_LIQUIDITY_FLAG | 
            Hooks.AFTER_REMOVE_LIQUIDITY_FLAG | 
            Hooks.AFTER_SWAP_FLAG
        );
        
        bytes memory constructorArgs = abi.encode(poolManager);
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_FACTORY, 
            flags, 
            type(LSTrebalanceHook).creationCode, 
            constructorArgs
        );
        
        LSTrebalanceHook hook = new LSTrebalanceHook{salt: salt}(poolManager);
        require(address(hook) == hookAddress, "Hook address mismatch");
        
        console2.log("Hook:", address(hook));
        
        vm.stopBroadcast();
        
        console2.log("\n=== COPY THESE ADDRESSES TO BaseScript.sol ===");
        console2.log("poolManager =", address(poolManager));
        console2.log("positionManager =", address(positionManager));
        console2.log("swapRouter =", address(swapRouter));
        console2.log("token0 =", address(token0));
        console2.log("token1 =", address(token1));
        console2.log("hookContract =", address(hook));
    }
    
    function _etch(address target, bytes memory bytecode) internal override {
        if (block.chainid == 31337) {
            vm.rpc(
                "anvil_setCode",
                string.concat('["', vm.toString(target), '","', vm.toString(bytecode), '"]')
            );
        }
    }
}
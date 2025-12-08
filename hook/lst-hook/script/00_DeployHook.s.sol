// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {BaseScript} from "./base/BaseScript.sol";

import {LSTrebalanceHook} from "../src/Rebalance.sol";

/// @notice Mines the address and deploys the Counter.sol Hook contract
contract DeployHookScript is BaseScript {
   // In script/00_DeployHook.s.sol

function run() public {
    uint160 flags = uint160(
        Hooks.AFTER_INITIALIZE_FLAG | 
        Hooks.AFTER_ADD_LIQUIDITY_FLAG | 
        Hooks.AFTER_REMOVE_LIQUIDITY_FLAG | 
        Hooks.AFTER_SWAP_FLAG
    );
    
    // Include owner in constructor args
    bytes memory constructorArgs = abi.encode(poolManager);

    (address hookAddress, bytes32 salt) =
        HookMiner.find(CREATE2_FACTORY, flags, type(LSTrebalanceHook).creationCode, constructorArgs);

    vm.startBroadcast();
    LSTrebalanceHook hook = new LSTrebalanceHook{salt: salt}(poolManager);
    vm.stopBroadcast();

    require(address(hook) == hookAddress, "DeployHookScript: Hook Address Mismatch");
}
}
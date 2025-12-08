// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/mocks/MockERC20.sol";

contract DeployMocks is Script {
    function run() external returns (MockERC20 token0, MockERC20 token1) {
        vm.startBroadcast();

        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);

        console.log("Token0 deployed at:", address(token0));
        console.log("Token1 deployed at:", address(token1));

        vm.stopBroadcast();
    }
}

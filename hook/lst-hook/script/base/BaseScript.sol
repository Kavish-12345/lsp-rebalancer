// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {
    IPositionManager
} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

import {
    IUniswapV4Router04
} from "hookmate/interfaces/router/IUniswapV4Router04.sol";
import {AddressConstants} from "hookmate/constants/AddressConstants.sol";

import {Deployers} from "test/utils/Deployers.sol";

/// @notice Shared configuration between scripts
contract BaseScript is Script, Deployers {
    address immutable deployerAddress;

    /////////////////////////////////////
    // --- UPDATED ADDRESSES --- //
    /////////////////////////////////////
    IERC20 internal constant token0 =
        IERC20(0x8C4c13856e935d33c0d3C3EF5623F2339f17d4f5);
    IERC20 internal constant token1 =
        IERC20(0xfbBB81A58049F92C340F00006D6B1BCbDfD5ec0d);
    IHooks constant hookContract =
        IHooks(0x38194911eE4390e4cC52D97DE9bDDAa86AE25540);

    Currency immutable currency0;
    Currency immutable currency1;

    constructor() {
        // Use deployed addresses - DO NOT call deployArtifacts()!
        permit2 = IPermit2(AddressConstants.getPermit2Address());
        poolManager = IPoolManager(0x0D9BAf34817Fccd3b3068768E5d20542B66424A5);
        positionManager = IPositionManager(
            0x90aAE8e3C8dF1d226431D0C2C7feAaa775fAF86C
        );
        swapRouter = IUniswapV4Router04(
            payable(0xB61598fa7E856D43384A8fcBBAbF2Aa6aa044FfC)
        );

        deployerAddress = getDeployer();
        (currency0, currency1) = getCurrencies();

        vm.label(address(permit2), "Permit2");
        vm.label(address(poolManager), "V4PoolManager");
        vm.label(address(positionManager), "V4PositionManager");
        vm.label(address(swapRouter), "V4SwapRouter");
        vm.label(address(token0), "Currency0");
        vm.label(address(token1), "Currency1");
        vm.label(address(hookContract), "HookContract");
    }

    function _etch(address target, bytes memory bytecode) internal override {
        if (block.chainid == 31337) {
            vm.rpc(
                "anvil_setCode",
                string.concat(
                    '["',
                    vm.toString(target),
                    '",',
                    '"',
                    vm.toString(bytecode),
                    '"]'
                )
            );
        } else {
            revert("Unsupported etch on this network");
        }
    }

    function getCurrencies() internal pure returns (Currency, Currency) {
        require(address(token0) != address(token1));

        if (token0 < token1) {
            return (
                Currency.wrap(address(token0)),
                Currency.wrap(address(token1))
            );
        } else {
            return (
                Currency.wrap(address(token1)),
                Currency.wrap(address(token0))
            );
        }
    }

    function getDeployer() internal returns (address) {
        address[] memory wallets = vm.getWallets();

        if (wallets.length > 0) {
            return wallets[0];
        } else {
            return msg.sender;
        }
    }
}

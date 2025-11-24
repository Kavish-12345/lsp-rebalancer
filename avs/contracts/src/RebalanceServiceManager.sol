// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@eigenlayer/contracts/libraries/BytesLib.sol";
import "./IRebalanceTaskManager.sol";
import "@eigenlayer-middleware/src/ServiceManagerBase.sol";
import {
    IAllocationManager,
    IAllocationManagerTypes
} from "@eigenlayer/contracts/interfaces/IAllocationManager.sol";
// import {IAVSRegistrar} from "@eigenlayer/contracts/interfaces/IAVSRegistrar.sol";
import {IRewardsCoordinator} from "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";
import {ISlashingRegistryCoordinator} from
    "@eigenlayer-middleware/src/interfaces/ISlashingRegistryCoordinator.sol";

/**
 * @title Primary entrypoint for procuring services from IncredibleSquaring.
 * @author Layr Labs, Inc.
 */
contract RebalanceServiceManager is ServiceManagerBase {
    using BytesLib for bytes;

    IRebalanceTaskManager public immutable rebalanceTaskManager;

    /// @notice when applied to a function, ensures that the function is only callable by the `registryCoordinator`.
    modifier onlyRebalanceTaskManager() {
    require(
        msg.sender == address(rebalanceTaskManager),
        "onlyRebalanceTaskManager: not from rebalance task manager"
    );
    _;
}

    constructor(
        IAVSDirectory _avsDirectory,
        ISlashingRegistryCoordinator _registryCoordinator,
        IStakeRegistry _stakeRegistry,
        address rewards_coordinator,
        IAllocationManager allocationManager,
        IPermissionController _permissionController,
        IRebalanceTaskManager _rebalanceTaskManager
    )
        ServiceManagerBase(
            _avsDirectory,
            IRewardsCoordinator(rewards_coordinator),
            _registryCoordinator,
            _stakeRegistry,
            _permissionController,
            allocationManager
        )
    {
        rebalanceTaskManager = _rebalanceTaskManager;
    }

    function initialize(address initialOwner, address rewardsInitiator) external initializer {
        __ServiceManagerBase_init(initialOwner, rewardsInitiator);
    }
}

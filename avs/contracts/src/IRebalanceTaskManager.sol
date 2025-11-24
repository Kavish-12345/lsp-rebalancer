// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@eigenlayer-middleware/src/libraries/BN254.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";

interface IRebalanceTaskManager {
    // EVENTS
    event NewTaskCreated(uint32 indexed taskIndex, Task task);

    event TaskResponded(TaskResponse taskResponse, TaskResponseMetadata taskResponseMetadata);

    event TaskCompleted(uint32 indexed taskIndex);

    event TaskChallengedSuccessfully(uint32 indexed taskIndex, address indexed challenger);

    event TaskChallengedUnsuccessfully(uint32 indexed taskIndex, address indexed challenger);

    // STRUCTS
    struct Task {
        address [] lpaddresses;
        uint256 lstrate;
        uint32 taskCreatedBlock;
        bytes quorumNumbers; // this is a list of operator public keys that are expected to sign the task response
        uint32 quorumThresholdPercentage; // this is the percentage of operators that need to sign the
        // task response for the task to be considered completed. 
    }

    // Task response is hashed and signed by operators.
    // these signatures are aggregated and sent to the contract as response.
    struct TaskResponse {
        // Can be obtained by the operator from the event NewTaskCreated.
        uint32 referenceTaskIndex;
        bytes32 batchTxHash;
        uint256 totalGasUsed;
        uint8 successCount; // number of Lp'S Rebalanced successfully
        
    }

    // Extra information related to taskResponse, which is filled inside the contract.
    // It thus cannot be signed by operators, so we keep it in a separate struct than TaskResponse
    // This metadata is needed by the challenger, so we emit it in the TaskResponded event
    struct TaskResponseMetadata {
        uint32 taskRespondedBlock;
        bytes32 hashOfNonSigners;
    }

    // FUNCTIONS
    // NOTE: this function creates new task.
    function createNewTask(
        address [] calldata lpAddresses,
        uint256 lstRate,
        uint32 quorumThresholdPercentage,
        bytes calldata quorumNumbers
    ) external;

    /// @notice Returns the current 'taskNumber' for the middleware
    function taskNumber() external view returns (uint32);

    // // NOTE: this function raises challenge to existing tasks.
    function raiseAndResolveChallenge(
        Task calldata task,
        TaskResponse calldata taskResponse,
        TaskResponseMetadata calldata taskResponseMetadata,
        BN254.G1Point[] memory pubkeysOfNonSigningOperators
    ) external;

    /// @notice Returns the TASK_RESPONSE_WINDOW_BLOCK
    function getTaskResponseWindowBlock() external view returns (uint32);
}

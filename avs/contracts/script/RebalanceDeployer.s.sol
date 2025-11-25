// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {CoreDeploymentLib} from "./utils/CoreDeploymentLib.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@eigenlayer/contracts/permissions/PauserRegistry.sol";

import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IAVSDirectory} from "@eigenlayer/contracts/interfaces/IAVSDirectory.sol";
import {IStrategyManager, IStrategy} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {StrategyBaseTVLLimits} from "@eigenlayer/contracts/strategies/StrategyBaseTVLLimits.sol";
import "@eigenlayer/test/mocks/EmptyContract.sol";

import "@eigenlayer-middleware/src/RegistryCoordinator.sol";
import {RegistryCoordinator} from "@eigenlayer-middleware/src/RegistryCoordinator.sol";
import {IBLSApkRegistry} from "@eigenlayer-middleware/src/interfaces/IBLSApkRegistry.sol";
import {IIndexRegistry} from "@eigenlayer-middleware/src/interfaces/IIndexRegistry.sol";
import {IStakeRegistry} from "@eigenlayer-middleware/src/interfaces/IStakeRegistry.sol";
import {BLSApkRegistry} from "@eigenlayer-middleware/src/BLSApkRegistry.sol";
import {IndexRegistry} from "@eigenlayer-middleware/src/IndexRegistry.sol";
import {StakeRegistry} from "@eigenlayer-middleware/src/StakeRegistry.sol";
import "@eigenlayer-middleware/src/OperatorStateRetriever.sol";

import {
    RebalanceServiceManager,
    IServiceManager
} from "../src/RebalanceServiceManager.sol";
import {RebalanceTaskManager} from "../src/RebalanceTaskManager.sol";
import {IRebalanceTaskManager} from "../src/IRebalanceTaskManager.sol";
import "../src/MockERC20.sol";

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "forge-std/console.sol";
import {StrategyFactory} from "@eigenlayer/contracts/strategies/StrategyFactory.sol";

import {ContractsRegistry} from "../src/ContractsRegistry.sol";
import {RebalanceDeploymentLib} from "../script/utils/RebalanceDeploymentLib.sol";
import {UpgradeableProxyLib} from "./utils/UpgradeableProxyLib.sol";

import {FundOperator} from "./utils/FundOperator.sol";
// # To deploy and verify our contract
// forge script script/RebalanceDeployer.s.sol:RebalanceDeployer --rpc-url $RPC_URL  --private-key $PRIVATE_KEY --broadcast -vvvv

contract RebalanceDeployer is Script {
    // DEPLOYMENT CONSTANTS
    uint256 public constant QUORUM_THRESHOLD_PERCENTAGE = 100;
    uint32 public constant TASK_RESPONSE_WINDOW_BLOCK = 30;
    uint32 public constant TASK_DURATION_BLOCKS = 0;
    address public AGGREGATOR_ADDR;
    address public TASK_GENERATOR_ADDR;
    address public CONTRACTS_REGISTRY_ADDR;
    address public OPERATOR_ADDR;
    address public OPERATOR_2_ADDR;
    ContractsRegistry contractsRegistry;

    StrategyBaseTVLLimits public erc20MockStrategy;

    address public rewardscoordinator;

    ProxyAdmin public rebalanceProxyAdmin;
    PauserRegistry public rebalancePauserReg;
    //regcoord.RegistryCoordinator public registryCoordinator;
    //regcoord.IRegistryCoordinator public registryCoordinatorImplementation;

    IBLSApkRegistry public blsApkRegistry;
    IBLSApkRegistry public blsApkRegistryImplementation;

    IIndexRegistry public indexRegistry;
    IIndexRegistry public indexRegistryImplementation;

    IStakeRegistry public stakeRegistry;
    IStakeRegistry public stakeRegistryImplementation;

    OperatorStateRetriever public operatorStateRetriever;

    RebalanceServiceManager public rebalanceServiceManager;
    IServiceManager public rebalanceServiceManagerImplementation;
    RebalanceTaskManager public rebalanceTaskManager;
    IRebalanceTaskManager public rebalanceTaskManagerImplementation;
    CoreDeploymentLib.DeploymentData internal configData;
    IStrategy rebalanceStrategy;
    address private deployer;
    MockERC20 public erc20Mock;
    RebalanceDeploymentLib.DeploymentData rebalanceDeployment;

    using UpgradeableProxyLib for address;

    address proxyAdmin;

    function setUp() public virtual {
        deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        vm.label(deployer, "Deployer");
    }

    function run() external {
        // Eigenlayer contracts
        vm.startBroadcast(deployer);
        RebalanceDeploymentLib.RebalanceSetupConfig memory isConfig =
        RebalanceDeploymentLib.readRebalanceConfigJson(
            "rebalance_config"
        );
        configData = CoreDeploymentLib.readDeploymentJson("script/deployments/core/", block.chainid);

        erc20Mock = new MockERC20();
        console.log(address(erc20Mock));
        FundOperator.fund_operator(address(erc20Mock), isConfig.operator_addr, 15_000e18);
        FundOperator.fund_operator(address(erc20Mock), isConfig.operator_2_addr, 30_000e18);
        console.log(isConfig.operator_2_addr);
        (bool s,) = isConfig.operator_2_addr.call{value: 0.1 ether}("");
        require(s);
        rebalanceStrategy =
            IStrategy(StrategyFactory(configData.strategyFactory).deployNewStrategy(erc20Mock));
        rewardscoordinator = configData.rewardsCoordinator;

        proxyAdmin = UpgradeableProxyLib.deployProxyAdmin();
        require(address(rebalanceStrategy) != address(0));
        rebalanceDeployment = RebalanceDeploymentLib.deployContracts(
            proxyAdmin, configData, address(rebalanceStrategy), isConfig, msg.sender
        );
        console.log("instantSlasher", rebalanceDeployment.slasher);
        FundOperator.fund_operator(
            address(erc20Mock), rebalanceDeployment.rebalanceServiceManager, 1e18
        );
        rebalanceDeployment.token = address(erc20Mock);
        RebalanceDeploymentLib.writeDeploymentJson(rebalanceDeployment);

        vm.stopBroadcast();
    }
}

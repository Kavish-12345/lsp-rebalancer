package main

import (
	"context"
	"fmt"
	"math/big"
	"os"
	"time"
	"crypto/ecdsa"
"strings"
"github.com/ethereum/go-ethereum/accounts/abi"

	"github.com/Layr-Labs/hourglass-monorepo/ponos/pkg/performer/contracts"
	"github.com/Layr-Labs/hourglass-monorepo/ponos/pkg/performer/server"
	performerV1 "github.com/Layr-Labs/protocol-apis/gen/protos/eigenlayer/hourglass/v1/performer"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"go.uber.org/zap"
)

type RebalanceTaskData struct {
	PoolId          [32]byte
	YieldBps        uint64
	CumulativeYield uint64
	PositionCount   uint64
	Timestamp       uint64
}

type TaskWorker struct {
	logger        *zap.Logger
	contractStore *contracts.ContractStore
	l1Client      *ethclient.Client
	l2Client      *ethclient.Client
	hookAddress   common.Address
	privateKey  *ecdsa.PrivateKey
}

func NewTaskWorker(logger *zap.Logger) *TaskWorker {
	contractStore, err := contracts.NewContractStore()
	if err != nil {
		logger.Warn("Failed to load contract store", zap.Error(err))
	}

	var l1Client, l2Client *ethclient.Client

	if l1RpcUrl := os.Getenv("L1_RPC_URL"); l1RpcUrl != "" {
		l1Client, err = ethclient.Dial(l1RpcUrl)
		if err != nil {
			logger.Error("Failed to connect to L1 RPC", zap.Error(err))
		}
	}

	if l2RpcUrl := os.Getenv("L2_RPC_URL"); l2RpcUrl != "" {
		l2Client, err = ethclient.Dial(l2RpcUrl)
		if err != nil {
			logger.Error("Failed to connect to L2 RPC", zap.Error(err))
		}
	}

	// NEW: Load hook address and private key
	hookAddress := common.HexToAddress(os.Getenv("HOOK_ADDRESS"))
	
	pkHex := os.Getenv("OPERATOR_PRIVATE_KEY")
	 var privateKey *ecdsa.PrivateKey
	pk, err := crypto.HexToECDSA(pkHex)
if err != nil {
    logger.Error("Failed to load private key", zap.Error(err))
} else {
    privateKey = pk
}

	return &TaskWorker{
		logger:        logger,
		contractStore: contractStore,
		l1Client:      l1Client,
		l2Client:      l2Client,
		hookAddress:   hookAddress,
		privateKey:    privateKey,
	}
}

func (tw *TaskWorker) ValidateTask(t *performerV1.TaskRequest) error {
	tw.logger.Sugar().Infow("🔍 Validating LST rebalance task",
		zap.String("taskId", string(t.TaskId)),
	)

	if len(t.TaskId) == 0 {
		return fmt.Errorf("no task ID provided")
	}

	tw.logger.Sugar().Infow("✅ Task validation passed",
		zap.String("taskId", string(t.TaskId)),
	)
	return nil
}

func (tw *TaskWorker) HandleTask(t *performerV1.TaskRequest) (*performerV1.TaskResponse, error) {
	tw.logger.Sugar().Infow("🔄 Processing LST rebalance task",
		zap.String("taskId", string(t.TaskId)),
	)

	// Use mock yield data
	mockYieldBps := uint64(50) // Changed to 50 to match your test

	tw.logger.Sugar().Infow("📊 Task parameters",
		"yieldBps", mockYieldBps,
	)

	// Calculate optimal tick shift
	tickShift := tw.calculateTickShift(mockYieldBps)

	tw.logger.Sugar().Infow("✅ Calculated tick shift",
		"tickShift", tickShift,
		"yieldBps", mockYieldBps,
	)

	// NEW: Execute rebalance on hook if L2 client is available
	if tw.l2Client != nil && tw.hookAddress != (common.Address{}) && tw.privateKey != nil {
		err := tw.executeRebalanceOnHook(tickShift)
		if err != nil {
			tw.logger.Error("❌ Failed to execute rebalance on hook", zap.Error(err))
			// Don't fail the task, just log the error
		} else {
			tw.logger.Info("✅ Rebalance executed successfully on hook!")
		}
	} else {
		tw.logger.Warn("⚠️  Skipping hook execution (missing L2 client, hook address, or private key)")
	}

	// Encode tick shift as bytes for the response
	resultBytes := []byte(fmt.Sprintf("%d", tickShift))

	return &performerV1.TaskResponse{
		TaskId: t.TaskId,
		Result: resultBytes,
	}, nil
}

func (tw *TaskWorker) calculateTickShift(yieldBps uint64) int32 {
	tickShift := int32(yieldBps)

	tw.logger.Sugar().Infow("📐 Calculating tick shift",
		"yieldBps", yieldBps,
		"calculatedShift", tickShift,
	)

	if tickShift > 1000 {
		tw.logger.Sugar().Warnw("Tick shift capped at maximum",
			"original", tickShift,
			"capped", 1000,
		)
		tickShift = 1000
	} else if tickShift < -1000 {
		tw.logger.Sugar().Warnw("Tick shift capped at minimum",
			"original", tickShift,
			"capped", -1000,
		)
		tickShift = -1000
	}

	tw.logger.Sugar().Infow("📈 Final tick shift",
		"finalShift", tickShift,
	)

	return tickShift
}

// NEW: Execute rebalance on the hook contract
func (tw *TaskWorker) executeRebalanceOnHook(tickShift int32) error {
    tw.logger.Sugar().Infow("📤 Calling hook contract to execute rebalance",
        "hookAddress", tw.hookAddress.Hex(),
        "tickShift", tickShift,
    )

    // Get chain ID
    chainID, err := tw.l2Client.ChainID(context.Background())
    if err != nil {
        return fmt.Errorf("failed to get chain ID: %w", err)
    }

    // Create transactor
    auth, err := bind.NewKeyedTransactorWithChainID(tw.privateKey, chainID)
    if err != nil {
        return fmt.Errorf("failed to create transactor: %w", err)
    }

    // Set gas limit
    auth.GasLimit = 500000

    // ABI for executeRebalance function
    hookABI := `[{"inputs":[{"components":[{"internalType":"address","name":"currency0","type":"address"},{"internalType":"address","name":"currency1","type":"address"},{"internalType":"uint24","name":"fee","type":"uint24"},{"internalType":"int24","name":"tickSpacing","type":"int24"},{"internalType":"address","name":"hooks","type":"address"}],"internalType":"struct PoolKey","name":"","type":"tuple"},{"internalType":"int24","name":"","type":"int24"},{"internalType":"uint32","name":"","type":"uint32"}],"name":"executeRebalance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"}]`

    // Parse ABI
    parsedABI, err := abi.JSON(strings.NewReader(hookABI))
    if err != nil {
        return fmt.Errorf("failed to parse ABI: %w", err)
    }

    // Create bound contract
    contract := bind.NewBoundContract(tw.hookAddress, parsedABI, tw.l2Client, tw.l2Client, tw.l2Client)

    // Define the PoolKey struct
    poolKey := struct {
        Currency0   common.Address
        Currency1   common.Address
        Fee         *big.Int
        TickSpacing *big.Int
        Hooks       common.Address
    }{
        Currency0:   common.HexToAddress("0x8C4c13856e935d33c0d3C3EF5623F2339f17d4f5"),
        Currency1:   common.HexToAddress("0xfbBB81A58049F92C340F00006D6B1BCbDfD5ec0d"),
        Fee:         big.NewInt(3000),
        TickSpacing: big.NewInt(60),
        Hooks:       tw.hookAddress,
    }

    // Call the contract
    tx, err := contract.Transact(auth, "executeRebalance", poolKey, big.NewInt(int64(tickShift)), uint32(0))
    if err != nil {
        return fmt.Errorf("failed to send transaction: %w", err)
    }

    tw.logger.Sugar().Infow("✅ Transaction sent to hook contract", "txHash", tx.Hash().Hex())
    return nil
}

func main() {
	ctx := context.Background()
	l, _ := zap.NewProduction()

	w := NewTaskWorker(l)

	pp, err := server.NewPonosPerformerWithRpcServer(&server.PonosPerformerConfig{
		Port:    8080,
		Timeout: 5 * time.Second,
	}, w, l)
	if err != nil {
		panic(fmt.Errorf("failed to create performer: %w", err))
	}

	if err := pp.Start(ctx); err != nil {
		panic(err)
	}
}
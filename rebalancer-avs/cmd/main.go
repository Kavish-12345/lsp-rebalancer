package main

import (
	"context"
	"fmt"
	"os"
	"time"

	// Comment out unused imports
	// "github.com/Layr-Labs/hourglass-avs-template/contracts/bindings/l1/helloworldl1"
	// "github.com/Layr-Labs/hourglass-avs-template/contracts/bindings/l1/taskavsregistrar"
	"github.com/Layr-Labs/hourglass-monorepo/ponos/pkg/performer/contracts"
	"github.com/Layr-Labs/hourglass-monorepo/ponos/pkg/performer/server"
	performerV1 "github.com/Layr-Labs/protocol-apis/gen/protos/eigenlayer/hourglass/v1/performer"
	"github.com/ethereum/go-ethereum/ethclient"
	"go.uber.org/zap"
)

// This offchain binary is run by Operators running the Hourglass Executor. It contains
// the business logic of the AVS and performs worked based on the tasked sent to it.
// The Hourglass Aggregator ingests tasks from the TaskMailbox and distributes work
// to Executors configured to run the AVS Performer. Performers execute the work and
// return the result to the Executor where the result is signed and return to the
// Aggregator to place in the outbox once the signing threshold is met.

// LST Rebalance Task Data Structure
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
}

func NewTaskWorker(logger *zap.Logger) *TaskWorker {
	// Initialize contract store from environment variables
	contractStore, err := contracts.NewContractStore()
	if err != nil {
		logger.Warn("Failed to load contract store", zap.Error(err))
	}

	// Initialize Ethereum clients if RPC URLs are provided
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

	return &TaskWorker{
		logger:        logger,
		contractStore: contractStore,
		l1Client:      l1Client,
		l2Client:      l2Client,
	}
}

func (tw *TaskWorker) ValidateTask(t *performerV1.TaskRequest) error {
	tw.logger.Sugar().Infow("🔍 Validating LST rebalance task",
		zap.String("taskId", string(t.TaskId)),  // FIXED: Convert []byte to string
	)

	// Basic validation - check if task ID exists
	if len(t.TaskId) == 0 {  // FIXED: Check length instead of comparing to ""
		return fmt.Errorf("no task ID provided")
	}

	tw.logger.Sugar().Infow("✅ Task validation passed",
		zap.String("taskId", string(t.TaskId)),  // FIXED: Convert []byte to string
	)
	return nil
}

func (tw *TaskWorker) HandleTask(t *performerV1.TaskRequest) (*performerV1.TaskResponse, error) {
	tw.logger.Sugar().Infow("🔄 Processing LST rebalance task",
		zap.String("taskId", string(t.TaskId)),  // FIXED: Convert []byte to string
	)

	// TODO: In production, decode actual task data from the TaskMailbox
	// For MVP/Demo: Use mock yield data
	mockYieldBps := uint64(15) // 0.15% yield (15 basis points)

	tw.logger.Sugar().Infow("📊 Task parameters",
		"yieldBps", mockYieldBps,
	)

	// Calculate optimal tick shift using your algorithm
	tickShift := tw.calculateTickShift(mockYieldBps)

	tw.logger.Sugar().Infow("✅ Calculated tick shift",
		"tickShift", tickShift,
		"yieldBps", mockYieldBps,
	)

	// Encode tick shift as bytes for the response
	resultBytes := []byte(fmt.Sprintf("%d", tickShift))

	return &performerV1.TaskResponse{
		TaskId: t.TaskId,
		Result: resultBytes,
	}, nil
}

// calculateTickShift - Core algorithm to determine how many ticks to shift LP positions
func (tw *TaskWorker) calculateTickShift(yieldBps uint64) int32 {

	// STRATEGY: Simple 1:1 mapping (1 basis point = 1 tick)
	// This is close to mathematically correct for small yield values
	// and provides deterministic consensus across all operators
	tickShift := int32(yieldBps)

	tw.logger.Sugar().Infow("📐 Calculating tick shift",
		"yieldBps", yieldBps,
		"calculatedShift", tickShift,
	)

	// ALTERNATIVE STRATEGY (for production):
	// Price-based calculation using Uniswap v3 tick math
	// yieldMultiplier := 1.0 + (float64(yieldBps) / 10000.0)
	// priceShift := math.Log(yieldMultiplier) / math.Log(1.0001)
	// tickShift := int32(math.Round(priceShift))

	// Safety bounds: Prevent extreme shifts
	// Uniswap v3 max tick range is ±887,272
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
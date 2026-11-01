package main

import (
	"fmt"
	"sync"
	"sync/atomic"
	"time"
)

func runGoroutineBenchmark(nTasks int) {
	fmt.Println("\n=======================================================")
	fmt.Println("1. Go Goroutine 100,000 Microtasks Benchmark")
	fmt.Println("=======================================================")

	var wg sync.WaitGroup
	var completed int64

	t0 := time.Now()

	// Spawn Phase
	wg.Add(nTasks)
	tSpawnStart := time.Now()
	for i := 0; i < nTasks; i++ {
		go func() {
			atomic.AddInt64(&completed, 1)
			wg.Done()
		}()
	}
	tSpawnEnd := time.Now()

	// Wait for completion
	wg.Wait()
	tEnd := time.Now()

	spawnElapsedMs := tSpawnEnd.Sub(tSpawnStart).Milliseconds()
	execElapsedNs := tEnd.Sub(tSpawnStart).Nanoseconds()
	execElapsedMs := tEnd.Sub(tSpawnStart).Milliseconds()
	totalElapsedMs := tEnd.Sub(t0).Milliseconds()

	throughput := int64(0)
	if execElapsedNs > 0 {
		throughput = int64(nTasks) * 1000000000 / execElapsedNs
	}
	avgLatencyNs := execElapsedNs / int64(nTasks)

	fmt.Printf("  - Total Microtasks: %d tasks\n", completed)
	fmt.Printf("  - Spawn Time: %d ms\n", spawnElapsedMs)
	fmt.Printf("  - Execution Time: %d ms\n", execElapsedMs)
	fmt.Printf("  - Total Elapsed Time: %d ms\n", totalElapsedMs)
	fmt.Printf("  - Throughput: %d tasks/sec\n", throughput)
	fmt.Printf("  - Average Latency per Task: %d ns\n", avgLatencyNs)
	if completed == int64(nTasks) {
		fmt.Println("  [STATUS]: PASS (100% of goroutines completed)")
	}
}

func runChannelBenchmark(nRelays int) {
	fmt.Println("\n=======================================================")
	fmt.Println("2. Go Channel 50,000 Messaging Relay Benchmark")
	fmt.Println("=======================================================")

	ch := make(chan int, 1024)
	t0 := time.Now()

	for i := 0; i < nRelays; i++ {
		ch <- i
		val := <-ch
		if val != i {
			panic("message corrupted")
		}
	}

	elapsed := time.Since(t0)
	elapsedNs := elapsed.Nanoseconds()
	elapsedMs := elapsed.Milliseconds()

	throughput := int64(0)
	if elapsedNs > 0 {
		throughput = int64(nRelays) * 1000000000 / elapsedNs
	}
	latencyPerOp := elapsedNs / int64(nRelays)

	fmt.Printf("  - Channel Messages: %d msgs\n", nRelays)
	fmt.Printf("  - Elapsed Time: %d ms\n", elapsedMs)
	fmt.Printf("  - Messaging Throughput: %d msgs/sec\n", throughput)
	fmt.Printf("  - Latency per Send/Recv Pair: %d ns\n", latencyPerOp)
	fmt.Println("  [STATUS]: PASS (Zero Message Loss in Go Channel)")
}

func main() {
	fmt.Println("\n#######################################################")
	fmt.Println(" GO (1.22.2) CONCURRENCY BASELINE BENCHMARK")
	fmt.Println(" Hardware: Linux x86-64 | Runtime: Go Native M:N")
	fmt.Println("#######################################################")

	runGoroutineBenchmark(100000)
	runChannelBenchmark(50000)
}

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Instant;

#[tokio::main]
async fn main() {
    println!("\n#######################################################");
    println!(" RUST (1.75.0 / TOKIO) CONCURRENCY BASELINE BENCHMARK");
    println!(" Hardware: Linux x86-64 | Runtime: Tokio Work-Stealing M:N");
    println!("#######################################################");

    run_tokio_task_benchmark(100_000).await;
    run_tokio_channel_benchmark(50_000).await;
}

async fn run_tokio_task_benchmark(n_tasks: usize) {
    println!("\n=======================================================");
    println!("1. Rust Tokio 100,000 Microtasks Benchmark");
    println!("=======================================================");

    let counter = Arc::new(AtomicUsize::new(0));
    let t0 = Instant::now();

    let mut handles = Vec::with_capacity(n_tasks);
    let t_spawn_start = Instant::now();
    for _ in 0..n_tasks {
        let cnt = Arc::clone(&counter);
        handles.push(tokio::spawn(async move {
            cnt.fetch_add(1, Ordering::Relaxed);
        }));
    }
    let spawn_elapsed_ms = t_spawn_start.elapsed().as_millis();

    for h in handles {
        h.await.unwrap();
    }
    let total_elapsed = t0.elapsed();
    let exec_elapsed_ns = total_elapsed.as_nanos();
    let exec_elapsed_ms = total_elapsed.as_millis();

    let throughput = if exec_elapsed_ns > 0 {
        (n_tasks as u128 * 1_000_000_000) / exec_elapsed_ns
    } else {
        0
    };
    let avg_latency_ns = exec_elapsed_ns / (n_tasks as u128);
    let completed = counter.load(Ordering::Relaxed);

    println!("  - Total Microtasks: {} tasks", completed);
    println!("  - Spawn Time: {} ms", spawn_elapsed_ms);
    println!("  - Execution Time: {} ms", exec_elapsed_ms);
    println!("  - Total Elapsed Time: {} ms", exec_elapsed_ms);
    println!("  - Throughput: {} tasks/sec", throughput);
    println!("  - Average Latency per Task: {} ns", avg_latency_ns);
    if completed == n_tasks {
        println!("  [STATUS]: PASS (100% of Tokio tasks completed)");
    }
}

async fn run_tokio_channel_benchmark(n_relays: usize) {
    println!("\n=======================================================");
    println!("2. Rust Tokio 50,000 MPSC Messaging Relay Benchmark");
    println!("=======================================================");

    let (tx, mut rx) = tokio::sync::mpsc::channel::<usize>(1024);
    let t0 = Instant::now();

    for i in 0..n_relays {
        tx.send(i).await.unwrap();
        let val = rx.recv().await.unwrap();
        if val != i {
            panic!("message corrupted");
        }
    }

    let elapsed = t0.elapsed();
    let elapsed_ns = elapsed.as_nanos();
    let elapsed_ms = elapsed.as_millis();

    let throughput = if elapsed_ns > 0 {
        (n_relays as u128 * 1_000_000_000) / elapsed_ns
    } else {
        0
    };
    let latency_per_op = elapsed_ns / (n_relays as u128);

    println!("  - Channel Messages: {} msgs", n_relays);
    println!("  - Elapsed Time: {} ms", elapsed_ms);
    println!("  - Messaging Throughput: {} msgs/sec", throughput);
    println!("  - Latency per Send/Recv Pair: {} ns", latency_per_op);
    println!("  [STATUS]: PASS (Zero Message Loss in Tokio MPSC)");
}

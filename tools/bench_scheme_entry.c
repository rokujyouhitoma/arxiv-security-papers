#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <time.h>

extern uint64_t scheme_entry(void);

int main() {
    // Warmup
    uint64_t res = 0;
    for (int i = 0; i < 3; i++) {
        res = scheme_entry();
    }

    struct timespec ts0, ts1;
    clock_gettime(CLOCK_MONOTONIC, &ts0);
    for (int i = 0; i < 10; i++) {
        res = scheme_entry();
    }
    clock_gettime(CLOCK_MONOTONIC, &ts1);

    double total_ms = (ts1.tv_sec - ts0.tv_sec) * 1000.0 + (ts1.tv_nsec - ts0.tv_nsec) / 1000000.0;
    double avg_ms = total_ms / 10.0;
    printf("Result: %lu (unboxed: %ld)\n", res, (int64_t)res >> 2);
    printf("Pure CPU Loop Latency (1,000,000 iters): %.3f ms\n", avg_ms);
    return 0;
}

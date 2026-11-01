-module(bench_erlang).
-export([main/0]).

main() ->
    io:format("~n#######################################################~n"),
    io:format(" ERLANG/OTP 25 CONCURRENCY BASELINE BENCHMARK~n"),
    io:format(" Hardware: Linux x86-64 | Runtime: BEAM Actor VM~n"),
    io:format("#######################################################~n"),
    run_process_benchmark(100000),
    run_channel_benchmark(50000),
    halt(0).

run_process_benchmark(N) ->
    io:format("~n=======================================================~n"),
    io:format("1. Erlang 100,000 Actor Process Benchmark~n"),
    io:format("=======================================================~n"),
    Self = self(),
    T0 = erlang:monotonic_time(nanosecond),
    
    %% Spawn N processes
    lists:foreach(fun(I) ->
        spawn(fun() ->
            Self ! {done, I}
        end)
    end, lists:seq(1, N)),
    TSpawnEnd = erlang:monotonic_time(nanosecond),
    
    %% Collect N completions
    collect_completions(N),
    TEnd = erlang:monotonic_time(nanosecond),

    SpawnMs = (TSpawnEnd - T0) div 1000000,
    ExecNs = TEnd - T0,
    ExecMs = ExecNs div 1000000,
    Throughput = (N * 1000000000) div ExecNs,
    AvgLatencyNs = ExecNs div N,

    io:format("  - Total Microtasks: ~p tasks~n", [N]),
    io:format("  - Spawn Time: ~p ms~n", [SpawnMs]),
    io:format("  - Execution Time: ~p ms~n", [ExecMs]),
    io:format("  - Total Elapsed Time: ~p ms~n", [ExecMs]),
    io:format("  - Throughput: ~p tasks/sec~n", [Throughput]),
    io:format("  - Average Latency per Task: ~p ns~n", [AvgLatencyNs]),
    io:format("  [STATUS]: PASS (100% of Erlang processes completed)~n").

collect_completions(0) -> ok;
collect_completions(N) ->
    receive
        {done, _} -> collect_completions(N - 1)
    end.

run_channel_benchmark(N) ->
    io:format("~n=======================================================~n"),
    io:format("2. Erlang 50,000 Actor Message Relay Benchmark~n"),
    io:format("=======================================================~n"),
    Self = self(),
    Receiver = spawn(fun() -> receiver_loop(Self) end),
    T0 = erlang:monotonic_time(nanosecond),

    lists:foreach(fun(I) ->
        Receiver ! {msg, I},
        receive
            {ack, I} -> ok
        end
    end, lists:seq(1, N)),
    TEnd = erlang:monotonic_time(nanosecond),

    ElapsedNs = TEnd - T0,
    ElapsedMs = ElapsedNs div 1000000,
    Throughput = (N * 1000000000) div ElapsedNs,
    LatencyPerOp = ElapsedNs div N,

    io:format("  - Channel Messages: ~p msgs~n", [N]),
    io:format("  - Elapsed Time: ~p ms~n", [ElapsedMs]),
    io:format("  - Messaging Throughput: ~p msgs/sec~n", [Throughput]),
    io:format("  - Latency per Send/Recv Pair: ~p ns~n", [LatencyPerOp]),
    io:format("  [STATUS]: PASS (Zero Message Loss in Erlang Actor)~n").

receiver_loop(Sender) ->
    receive
        {msg, I} ->
            Sender ! {ack, I},
            receiver_loop(Sender);
        stop -> ok
    end.

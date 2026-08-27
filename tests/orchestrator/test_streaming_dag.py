"""Test suite for Streaming DAG & Reactive Backpressure Pipeline Engine."""

from typing import Iterator

from orchestrator.cli import main
from orchestrator.contracts import IntelligencePhase
from orchestrator.engine import UniversalIntelligenceOrchestrator
from orchestrator.workflow.streaming_dag import (
    BufferPolicy,
    StreamChunk,
    StreamingDAG,
    StreamingTaskNode,
)


def test_stream_chunk_properties() -> None:
    chunk = StreamChunk(
        chunk_id="chunk_1",
        sequence_no=1,
        items=[{"id": 1}, {"id": 2}, {"id": 3}],
        is_eos=False,
    )
    assert chunk.item_count == 3
    assert chunk.sequence_no == 1


def test_streaming_task_node_bounded_queue() -> None:
    node = StreamingTaskNode(
        node_id="node_1",
        transform_fn=lambda c: c,
        max_buffer_size=2,
        policy=BufferPolicy.BLOCK,
    )

    c1 = StreamChunk("c1", 1, [1])
    c2 = StreamChunk("c2", 2, [2])
    c3 = StreamChunk("c3", 3, [3])

    assert node.push(c1) is True
    assert node.push(c2) is True
    # Buffer full, BLOCK policy should reject
    assert node.push(c3) is False
    assert node.throttle_events == 1
    assert node.pressure == 1.0
    assert node.is_congested() is True

    popped = node.process_next()
    assert popped is not None
    assert popped.chunk_id == "c1"
    assert node.pressure == 0.5


def test_streaming_task_node_drop_oldest() -> None:
    node = StreamingTaskNode(
        node_id="node_drop",
        transform_fn=lambda c: c,
        max_buffer_size=2,
        policy=BufferPolicy.DROP_OLDEST,
    )

    c1 = StreamChunk("c1", 1, [1])
    c2 = StreamChunk("c2", 2, [2])
    c3 = StreamChunk("c3", 3, [3])

    node.push(c1)
    node.push(c2)
    # Pushing 3rd chunk should drop oldest (c1)
    assert node.push(c3) is True
    assert node.throttle_events == 1

    popped1 = node.process_next()
    assert popped1 is not None
    assert popped1.chunk_id == "c2"

    popped2 = node.process_next()
    assert popped2 is not None
    assert popped2.chunk_id == "c3"


def test_streaming_dag_multi_node_pipeline() -> None:
    dag = StreamingDAG(high_watermark=0.80, low_watermark=0.30)

    # 3-stage pipeline: Ingest -> Double -> AddTen
    node_in = StreamingTaskNode("stage_1", lambda c: c, max_buffer_size=5)
    node_dbl = StreamingTaskNode(
        "stage_2",
        lambda c: StreamChunk(
            f"dbl_{c.chunk_id}", c.sequence_no, [x * 2 for x in c.items]
        ),
        max_buffer_size=5,
    )
    node_add = StreamingTaskNode(
        "stage_3",
        lambda c: StreamChunk(
            f"add_{c.chunk_id}", c.sequence_no, [x + 10 for x in c.items]
        ),
        max_buffer_size=5,
    )

    dag.add_node(node_in)
    dag.add_node(node_dbl)
    dag.add_node(node_add)

    dag.connect("stage_1", "stage_2")
    dag.connect("stage_2", "stage_3")

    def input_gen() -> Iterator[StreamChunk[int]]:
        yield StreamChunk("c1", 1, [1, 2, 3])
        yield StreamChunk("c2", 2, [4, 5, 6])

    results = dag.run_stream("stage_1", input_gen())
    assert results["total_items"] == 6
    assert len(results["output_chunks"]) == 2

    # Verify transformations: (1*2+10=12, 2*2+10=14, 3*2+10=16, 4*2+10=18, 5*2+10=20, 6*2+10=22)
    first_chunk_items = results["output_chunks"][0].items
    assert first_chunk_items == [12, 14, 16]


def test_streaming_dag_backpressure_throttling() -> None:
    dag = StreamingDAG(high_watermark=0.50)

    # Downstream node that processes slowly (every 2 calls)
    call_counter = [0]

    def slow_transform(c: StreamChunk[int]) -> StreamChunk[int]:
        call_counter[0] += 1
        return c

    node_in = StreamingTaskNode("fast_in", lambda c: c, max_buffer_size=2)
    node_slow = StreamingTaskNode("slow_downstream", slow_transform, max_buffer_size=1)

    dag.add_node(node_in)
    dag.add_node(node_slow)
    dag.connect("fast_in", "slow_downstream")

    # Pre-fill slow node queue to trigger immediate congestion
    node_slow.push(StreamChunk("preload", 0, [999]))

    def input_gen() -> Iterator[StreamChunk[int]]:
        for i in range(5):
            yield StreamChunk(f"c_{i}", i + 1, [i])

    results = dag.run_stream("fast_in", input_gen())
    assert results["total_items"] == 6  # 5 from input + 1 preload
    assert results["throttled_steps"] > 0
    assert results["peak_pressure"] >= 0.50


def test_orchestrator_stream_cycle_integration(tmp_path) -> None:
    orchestrator = UniversalIntelligenceOrchestrator(workspace_dir=str(tmp_path))
    ctx = orchestrator.stream_cycle(cycle_id="test_stream_01", chunk_size=2)

    assert ctx.cycle_id == "test_stream_01"
    assert ctx.phase_statuses[IntelligencePhase.PROCESSING].value == "completed"
    assert ctx.phase_statuses[IntelligencePhase.ANALYSIS].value == "completed"
    assert "streaming_stats" in ctx.state
    assert ctx.state["streaming_stats"]["total_items"] == len(ctx.processed_records)


def test_cli_streaming_cycle_execution(tmp_path, capsys) -> None:
    code = main(
        [
            "--workdir",
            str(tmp_path),
            "cycle",
            "--cycles",
            "1",
            "--streaming",
            "--chunk-size",
            "5",
            "--quiet",
        ]
    )
    assert code == 0

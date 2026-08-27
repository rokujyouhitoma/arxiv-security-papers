"""Unit tests for Streaming DAG & Reactive Backpressure Engine."""

from workflow.streaming_dag import (
    BufferPolicy,
    StreamChunk,
    StreamingDAG,
    StreamingTaskNode,
)


def test_stream_chunk_creation() -> None:
    chunk = StreamChunk[int](chunk_id="chk_01", items=[1, 2, 3], sequence_num=0)
    assert chunk.chunk_id == "chk_01"
    assert len(chunk.items) == 3


def test_streaming_task_node_bounded_queue() -> None:
    node = StreamingTaskNode[int](
        node_id="n1",
        process_fn=lambda items: [x * 2 for x in items],
        max_queue_size=2,
        policy=BufferPolicy.BLOCK,
    )
    assert node.pressure == 0.0

    c1 = StreamChunk(chunk_id="c1", items=[1], sequence_num=1)
    c2 = StreamChunk(chunk_id="c2", items=[2], sequence_num=2)
    c3 = StreamChunk(chunk_id="c3", items=[3], sequence_num=3)

    assert node.enqueue(c1) is True
    assert node.enqueue(c2) is True
    assert node.pressure == 1.0
    assert node.enqueue(c3) is False  # Blocked due to capacity


def test_streaming_dag_pipeline() -> None:
    dag: StreamingDAG[int] = StreamingDAG()
    dag.add_node("step1", lambda items: [x + 10 for x in items], max_queue_size=5)
    dag.add_node("step2", lambda items: [x * 2 for x in items], max_queue_size=5)
    dag.add_edge("step1", "step2")

    chunks = [StreamChunk(chunk_id="c1", items=[1, 2], sequence_num=0)]
    output = dag.execute_pipeline(chunks)

    assert len(output) == 1
    assert output[0].items == [22, 24]  # (1+10)*2=22, (2+10)*2=24

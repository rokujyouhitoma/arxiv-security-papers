"""Streaming DAG & Reactive Backpressure Pipeline Engine.

Executes streaming intelligence workflows with bounded memory consumption,
adaptive throttling on downstream congestion, and per-chunk transformation.
"""

import time
from collections import defaultdict, deque
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Dict, Generic, Iterator, List, Optional, Set, TypeVar

T = TypeVar("T")
In = TypeVar("In")
Out = TypeVar("Out")


@dataclass
class StreamChunk(Generic[T]):
    """Atomic data payload unit transmitted across streaming nodes."""

    chunk_id: str
    sequence_no: int
    items: List[T]
    is_eos: bool = False  # End of Stream flag
    metadata: Dict[str, Any] = field(default_factory=dict)

    @property
    def item_count(self) -> int:
        return len(self.items)


class BufferPolicy(str, Enum):
    """Backpressure handling policy when a node buffer is congested."""

    BLOCK = "block"  # Throttles upstream producer until buffer drains below threshold
    DROP_OLDEST = "drop_oldest"  # Discards oldest chunk to favor freshest data
    DRAIN = "drain"  # Eagerly drains buffer before accepting new inputs


class StreamingTaskNode(Generic[In, Out]):
    """A single bounded-buffer processing node within the streaming DAG."""

    def __init__(
        self,
        node_id: str,
        transform_fn: Callable[[StreamChunk[In]], StreamChunk[Out]],
        max_buffer_size: int = 10,
        policy: BufferPolicy = BufferPolicy.BLOCK,
    ) -> None:
        self.node_id = node_id
        self.transform_fn = transform_fn
        self.max_buffer_size = max(1, max_buffer_size)
        self.policy = policy
        self.queue: deque[StreamChunk[In]] = deque()
        self.processed_chunks: int = 0
        self.total_items_processed: int = 0
        self.throttle_events: int = 0

    @property
    def buffer_occupancy(self) -> int:
        return len(self.queue)

    @property
    def pressure(self) -> float:
        """Returns buffer fill ratio in [0.0, 1.0]."""
        return min(1.0, len(self.queue) / float(self.max_buffer_size))

    def is_congested(self, threshold: float = 0.80) -> bool:
        return self.pressure >= threshold

    def push(self, chunk: StreamChunk[In]) -> bool:
        """Pushes a chunk into the bounded input queue respecting policy."""
        if len(self.queue) >= self.max_buffer_size:
            self.throttle_events += 1
            if self.policy == BufferPolicy.DROP_OLDEST:
                self.queue.popleft()
            elif self.policy == BufferPolicy.BLOCK:
                return False

        self.queue.append(chunk)
        return True

    def process_next(self) -> Optional[StreamChunk[Out]]:
        """Pops and transforms the next available chunk."""
        if not self.queue:
            return None

        chunk = self.queue.popleft()
        out_chunk = self.transform_fn(chunk)
        self.processed_chunks += 1
        self.total_items_processed += out_chunk.item_count
        return out_chunk


class StreamingDAG:
    """Manages streaming DAG task dependencies and reactive backpressure flow."""

    def __init__(
        self, high_watermark: float = 0.80, low_watermark: float = 0.30
    ) -> None:
        self.high_watermark = high_watermark
        self.low_watermark = low_watermark
        self.nodes: Dict[str, StreamingTaskNode[Any, Any]] = {}
        self.edges: Dict[str, Set[str]] = defaultdict(set)
        self.in_degree: Dict[str, int] = defaultdict(int)

    def add_node(self, node: StreamingTaskNode[Any, Any]) -> None:
        """Registers a streaming node."""
        self.nodes[node.node_id] = node
        if node.node_id not in self.in_degree:
            self.in_degree[node.node_id] = 0

    def connect(self, src_id: str, dst_id: str) -> None:
        """Connects source node output stream to destination node input queue."""
        if src_id not in self.nodes or dst_id not in self.nodes:
            raise KeyError(f"Invalid nodes: {src_id} -> {dst_id}")
        self.edges[src_id].add(dst_id)
        self.in_degree[dst_id] += 1

    def get_entry_nodes(self) -> List[str]:
        """Returns nodes with 0 in-degree (root data ingestion entry points)."""
        return [n for n in self.nodes if self.in_degree[n] == 0]

    def check_system_pressure(self) -> tuple[float, bool]:
        """Calculates peak pressure and whether backpressure is active."""
        if not self.nodes:
            return 0.0, False
        max_p = max(n.pressure for n in self.nodes.values())
        return max_p, max_p >= self.high_watermark

    def _step_ingest(
        self,
        entry_node: StreamingTaskNode[Any, Any],
        chunk_iterator: Iterator[StreamChunk[Any]],
    ) -> tuple[bool, bool]:
        """Attempts to pull and push the next chunk into entry node."""
        try:
            chunk = next(chunk_iterator)
            pushed = entry_node.push(chunk)
            return (not pushed), False
        except StopIteration:
            return False, True

    def _step_node(
        self,
        node_id: str,
        node: StreamingTaskNode[Any, Any],
        output_collector: List[StreamChunk[Any]],
    ) -> tuple[bool, int]:
        """Processes one node forward step."""
        dst_ids = self.edges.get(node_id, set())
        if any(self.nodes[did].is_congested() for did in dst_ids):
            return False, 1

        out = node.process_next()
        if not out:
            return False, 0

        throttles = 0
        if dst_ids:
            for dst_id in dst_ids:
                if not self.nodes[dst_id].push(out):
                    throttles += 1
        else:
            output_collector.append(out)
        return True, throttles

    def _step_all_nodes(
        self, output_collector: List[StreamChunk[Any]]
    ) -> tuple[bool, int]:
        """Steps all nodes with active queues forward."""
        active_work = False
        throttles = 0
        for nid, node in self.nodes.items():
            if node.queue:
                worked, th_cnt = self._step_node(nid, node, output_collector)
                active_work = active_work or worked
                throttles += th_cnt
        return active_work, throttles

    def _handle_ingestion_step(
        self,
        is_congested: bool,
        iterator_active: bool,
        entry_node: StreamingTaskNode[Any, Any],
        chunk_iterator: Iterator[StreamChunk[Any]],
    ) -> tuple[int, bool]:
        """Handles ingestion and backpressure throttling for a single step."""
        if is_congested:
            return 1, iterator_active
        if not iterator_active:
            return 0, False

        throttled, exhausted = self._step_ingest(entry_node, chunk_iterator)
        th_cnt = 1 if throttled else 0
        still_active = not exhausted
        return th_cnt, still_active

    def _is_stream_terminated(self, iterator_active: bool, active_work: bool) -> bool:
        """Checks if stream processing has completely drained."""
        if iterator_active or active_work:
            return False
        return all(len(n.queue) == 0 for n in self.nodes.values())

    def run_stream(
        self,
        entry_node_id: str,
        chunk_iterator: Iterator[StreamChunk[Any]],
        max_iterations: int = 10000,
    ) -> Dict[str, Any]:
        """Executes the streaming DAG until input iterator is exhausted and queues drain."""
        start_time = time.perf_counter()
        entry_node = self.nodes[entry_node_id]
        output_collector: List[StreamChunk[Any]] = []
        throttled_steps, peak_pressure = 0, 0.0
        iterator_active, step = True, 0

        while step < max_iterations:
            step += 1
            cur_p, is_congested = self.check_system_pressure()
            peak_pressure = max(peak_pressure, cur_p)

            th_ingest, iterator_active = self._handle_ingestion_step(
                is_congested, iterator_active, entry_node, chunk_iterator
            )
            throttled_steps += th_ingest

            active_work, th_cnt = self._step_all_nodes(output_collector)
            throttled_steps += th_cnt

            if self._is_stream_terminated(iterator_active, active_work):
                break

        duration_ms = (time.perf_counter() - start_time) * 1000.0
        total_items = sum(c.item_count for c in output_collector)

        return {
            "output_chunks": output_collector,
            "total_items": total_items,
            "total_steps": step,
            "throttled_steps": throttled_steps,
            "peak_pressure": round(peak_pressure, 3),
            "duration_ms": round(duration_ms, 2),
            "node_stats": {
                nid: {
                    "processed_chunks": n.processed_chunks,
                    "total_items": n.total_items_processed,
                    "throttle_events": n.throttle_events,
                }
                for nid, n in self.nodes.items()
            },
        }

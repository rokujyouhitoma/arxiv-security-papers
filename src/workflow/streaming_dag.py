"""Streaming DAG & Reactive Backpressure Pipeline Engine."""

import time
from collections import deque
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Dict, Generic, List, Optional, TypeVar

T = TypeVar("T")


class BufferPolicy(str, Enum):
    """Backpressure handling policy when intermediate buffers reach capacity."""

    BLOCK = "block"  # Throttles upstream producers until downstream drains
    DROP_OLDEST = "drop_oldest"  # Discards oldest chunk to make room for newest
    DRAIN = "drain"  # Immediately triggers downstream processing


@dataclass
class StreamChunk(Generic[T]):
    """Atomic batch item flowing through streaming task nodes."""

    chunk_id: str
    items: List[T]
    sequence_num: int
    is_final: bool = False
    created_at: float = field(default_factory=time.time)
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class StreamingTaskNode(Generic[T]):
    """A streaming task node equipped with a bounded input queue."""

    node_id: str
    process_fn: Callable[[List[T]], List[T]]
    max_queue_size: int = 10
    policy: BufferPolicy = BufferPolicy.BLOCK
    queue: deque[StreamChunk[T]] = field(default_factory=deque)
    processed_count: int = 0
    dropped_count: int = 0

    @property
    def pressure(self) -> float:
        """Calculates buffer occupancy ratio (0.0 to 1.0)."""
        if self.max_queue_size <= 0:
            return 0.0
        return len(self.queue) / float(self.max_queue_size)

    def enqueue(self, chunk: StreamChunk[T]) -> bool:
        """Pushes a chunk into the bounded queue according to BufferPolicy."""
        if len(self.queue) >= self.max_queue_size:
            if self.policy == BufferPolicy.DROP_OLDEST:
                self.queue.popleft()
                self.dropped_count += 1
                self.queue.append(chunk)
                return True
            elif self.policy == BufferPolicy.BLOCK:
                # Buffer full: indicates upstream backpressure
                return False
        self.queue.append(chunk)
        return True

    def process_next(self) -> Optional[StreamChunk[T]]:
        """Consumes the next chunk from the queue and transforms its payload."""
        if not self.queue:
            return None
        chunk = self.queue.popleft()
        transformed = self.process_fn(chunk.items)
        self.processed_count += len(chunk.items)
        return StreamChunk(
            chunk_id=chunk.chunk_id,
            items=transformed,
            sequence_num=chunk.sequence_num,
            is_final=chunk.is_final,
            metadata=chunk.metadata,
        )


class StreamingDAG(Generic[T]):
    """Executes a chain or graph of streaming nodes with reactive backpressure."""

    def __init__(self) -> None:
        self.nodes: Dict[str, StreamingTaskNode[T]] = {}
        self.edges: Dict[str, List[str]] = {}

    def add_node(
        self,
        node_id: str,
        process_fn: Callable[[List[T]], List[T]],
        max_queue_size: int = 10,
        policy: BufferPolicy = BufferPolicy.BLOCK,
    ) -> StreamingTaskNode[T]:
        """Registers a streaming node in the DAG."""
        node = StreamingTaskNode(
            node_id=node_id,
            process_fn=process_fn,
            max_queue_size=max_queue_size,
            policy=policy,
        )
        self.nodes[node_id] = node
        if node_id not in self.edges:
            self.edges[node_id] = []
        return node

    def add_edge(self, from_node: str, to_node: str) -> None:
        """Connects from_node output stream to to_node input queue."""
        if from_node not in self.nodes or to_node not in self.nodes:
            raise ValueError("Both nodes must be registered before adding an edge")
        self.edges[from_node].append(to_node)

    def _feed_initial_chunks(
        self, first_node: StreamingTaskNode[Any], chunks: List[StreamChunk[T]]
    ) -> None:
        for chunk in chunks:
            while not first_node.enqueue(chunk):
                first_node.process_next()

    def _drain_node_chunks(
        self,
        curr_node: StreamingTaskNode[Any],
        next_node: Optional[StreamingTaskNode[Any]],
    ) -> List[StreamChunk[T]]:
        next_chunks: List[StreamChunk[T]] = []
        while curr_node.queue:
            out_chunk = curr_node.process_next()
            if out_chunk:
                next_chunks.append(out_chunk)
                if next_node:
                    next_node.enqueue(out_chunk)
        return next_chunks

    def execute_pipeline(
        self, initial_chunks: List[StreamChunk[T]]
    ) -> List[StreamChunk[T]]:
        """Drives all chunks through the streaming DAG until completion."""
        if not self.nodes:
            return initial_chunks

        node_keys = list(self.nodes.keys())
        self._feed_initial_chunks(self.nodes[node_keys[0]], initial_chunks)

        current_chunks = initial_chunks
        for i, n_id in enumerate(node_keys):
            curr_node = self.nodes[n_id]
            nxt_node = self.nodes[node_keys[i + 1]] if i + 1 < len(node_keys) else None
            current_chunks = self._drain_node_chunks(curr_node, nxt_node)

        return current_chunks

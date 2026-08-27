"""Universal Workflow Execution Engine Package.

Provides domain-agnostic workflow infrastructure:
- Topological DAG Execution (`DAGWorkflowEngine`, `TaskNode`)
- Reactive Backpressure Streaming (`StreamingDAG`, `StreamChunk`, `BufferPolicy`)
- Distributed Saga Transactions (`SagaCoordinator`, `SagaStep`, `PhaseProtocol`)
- Event Sourcing Crash Recovery (`OrchestratorWAL`, `OrchestratorEvent`, `EventType`)
- Circuit Breaker State Machine (`CircuitBreaker`, `CircuitState`)
"""

from workflow.circuit import CircuitBreaker, CircuitState
from workflow.dag import DAGWorkflowEngine, TaskNode
from workflow.saga import PhaseProtocol, SagaCoordinator, SagaStep
from workflow.streaming_dag import (
    BufferPolicy,
    StreamChunk,
    StreamingDAG,
    StreamingTaskNode,
)
from workflow.wal import EventType, OrchestratorEvent, OrchestratorWAL

__all__ = [
    "DAGWorkflowEngine",
    "TaskNode",
    "StreamingDAG",
    "StreamingTaskNode",
    "StreamChunk",
    "BufferPolicy",
    "SagaCoordinator",
    "SagaStep",
    "PhaseProtocol",
    "OrchestratorWAL",
    "OrchestratorEvent",
    "EventType",
    "CircuitBreaker",
    "CircuitState",
]

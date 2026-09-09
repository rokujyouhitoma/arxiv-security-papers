#!/usr/bin/env python3
"""
WorkflowScheduler for orchestrating recurring and periodic workflow tasks.
Integrates SpiderTaskOperator for scheduled spider executions.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional

from spider.daemon.client import SpiderDaemonClient

from .operators.spider_operator import SpiderTaskOperator


def _now() -> float:
    return time.time()


@dataclass
class ScheduledTask:
    """Represents a periodic or cron-scheduled workflow task."""

    task_id: str
    interval_seconds: float
    handler: Callable[[Dict[str, Any]], Dict[str, Any]]
    last_run: float = 0.0
    enabled: bool = True
    metadata: Dict[str, Any] = field(default_factory=dict)

    def is_due(self, current_time: Optional[float] = None) -> bool:
        """Determines if the task is due for execution."""
        if not self.enabled:
            return False
        ref_time = current_time if current_time is not None else _now()
        return (ref_time - self.last_run) >= self.interval_seconds

    def to_dict(self) -> Dict[str, Any]:
        """Serializes task definition to primitive dictionary."""
        return {
            "task_id": self.task_id,
            "interval_seconds": self.interval_seconds,
            "last_run": self.last_run,
            "enabled": self.enabled,
            "metadata": dict(self.metadata),
        }


class WorkflowScheduler:
    """
    Scheduler coordinating periodic task execution and DAG triggers.
    Provides first-class registration for SpiderTaskOperator instances.
    """

    def __init__(self) -> None:
        self.tasks: Dict[str, ScheduledTask] = {}

    def register_task(
        self,
        task_id: str,
        interval_seconds: float,
        handler: Callable[[Dict[str, Any]], Dict[str, Any]],
        metadata: Optional[Dict[str, Any]] = None,
    ) -> ScheduledTask:
        """Registers a generic task with execution interval."""
        task = ScheduledTask(
            task_id=task_id,
            interval_seconds=max(0.1, interval_seconds),
            handler=handler,
            metadata=metadata or {},
        )
        self.tasks[task_id] = task
        return task

    def register_spider_task(
        self,
        spider_name: str,
        interval_seconds: float,
        client: Optional[SpiderDaemonClient] = None,
        params: Optional[Dict[str, Any]] = None,
        task_id: Optional[str] = None,
    ) -> ScheduledTask:
        """Registers a recurring spider crawl task using SpiderTaskOperator."""
        t_id = task_id or f"spider_{spider_name}_periodic"
        operator = SpiderTaskOperator(
            spider_name=spider_name,
            client=client,
            params=params,
        )
        return self.register_task(
            task_id=t_id,
            interval_seconds=interval_seconds,
            handler=operator,
            metadata={"spider_name": spider_name, "type": "spider_operator"},
        )

    def list_tasks(self) -> List[Dict[str, Any]]:
        """Returns summary of all registered tasks."""
        return [task.to_dict() for task in self.tasks.values()]

    def _execute_task(self, task: ScheduledTask, context: Dict[str, Any]) -> None:
        try:
            task.handler(context)
            task.last_run = _now()
        except Exception:
            task.last_run = _now()

    def run_due_tasks(self, context: Optional[Dict[str, Any]] = None) -> List[str]:
        """Evaluates and executes all due tasks."""
        ctx = dict(context or {})
        executed: List[str] = []
        now_t = _now()
        for task_id, task in self.tasks.items():
            if task.is_due(now_t):
                self._execute_task(task, ctx)
                executed.append(task_id)
        return executed

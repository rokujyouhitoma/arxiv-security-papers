"""Base Item Pipeline abstraction, built-in pipelines, and SPI PipelineRegistry."""

from __future__ import annotations

import json
import logging
import os
import re
from abc import ABC, abstractmethod
from dataclasses import asdict
from typing import Any, Callable, Dict, List, Optional, Type

from ..core.engine import ScrapedItem

logger = logging.getLogger(__name__)


class DropItem(Exception):
    """Exception raised by a pipeline stage to drop an item from downstream processing."""


class BaseItemPipeline(ABC):
    """Abstract base class for all item processing pipelines."""

    async def open_spider(self, spider: Any) -> None:
        """Called when the spider begins execution."""

    async def close_spider(self, spider: Any) -> None:
        """Called when the spider finishes execution."""

    @abstractmethod
    async def process_item(self, item: ScrapedItem, spider: Any) -> ScrapedItem:
        """Processes a single scraped item.

        Must return the ScrapedItem (modified or unmodified), or raise DropItem.
        """
        return item


def _sanitize_filename(name: str) -> str:
    """Sanitizes filename component to prevent Path Traversal (CWE-22)."""
    clean = re.sub(r"\.\.+", "", str(name or ""))
    clean = re.sub(r"[^a-zA-Z0-9_\-\.]", "_", clean)
    clean = re.sub(r"_+", "_", clean).strip("._-")
    return clean or "unnamed_spider"


class JsonLinesItemPipeline(BaseItemPipeline):
    """Generic item pipeline that appends ScrapedItems as JSON Lines (.jsonl)."""

    def __init__(
        self,
        output_dir: Optional[str] = None,
        output_file: Optional[str] = None,
        filename_pattern: str = "{spider_name}.jsonl",
    ) -> None:
        self.output_dir: str = output_dir or "outputs/scraped_data"
        self.output_file: Optional[str] = output_file
        self.filename_pattern: str = filename_pattern
        self._opened_files: Dict[str, Any] = {}

    def _resolve_target_path(self, spider: Any) -> str:
        if self.output_file:
            target = os.path.abspath(self.output_file)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            return target

        spider_name = getattr(spider, "name", "spider")
        safe_name = _sanitize_filename(spider_name)
        fname = self.filename_pattern.format(spider_name=safe_name)
        safe_fname = _sanitize_filename(fname)
        if not safe_fname.endswith(".jsonl"):
            safe_fname = f"{safe_fname}.jsonl"

        target_dir = os.path.abspath(self.output_dir)
        os.makedirs(target_dir, exist_ok=True)
        return os.path.join(target_dir, safe_fname)

    async def process_item(self, item: ScrapedItem, spider: Any) -> ScrapedItem:
        """Appends item as single JSON line to target file."""
        target_path = self._resolve_target_path(spider)
        data = asdict(item)
        line = json.dumps(data, ensure_ascii=False) + "\n"

        with open(target_path, "a", encoding="utf-8") as f:
            f.write(line)

        item.payload["jsonl_path"] = target_path
        return item


class ConsoleItemPipeline(BaseItemPipeline):
    """Generic pipeline that logs or prints items for debugging and observability."""

    def __init__(self, log_level: int = logging.INFO) -> None:
        self.log_level = log_level

    async def process_item(self, item: ScrapedItem, spider: Any) -> ScrapedItem:
        spider_name = getattr(spider, "name", "spider")
        msg = (
            f"[{spider_name}] ScrapedItem(id='{item.item_id}', "
            f"title='{item.title}', url='{item.source_url}', "
            f"keys={list(item.payload.keys())})"
        )
        logger.log(self.log_level, msg)
        return item


class PipelineRegistry:
    """SPI Registry for discovering and instantiating Item Pipelines."""

    def __init__(self) -> None:
        self._pipelines: Dict[str, Type[BaseItemPipeline]] = {}
        self._factories: Dict[str, Callable[..., BaseItemPipeline]] = {}
        # Register built-ins
        self.register("jsonl", JsonLinesItemPipeline)
        self.register("console", ConsoleItemPipeline)

    def register(
        self,
        name: str,
        pipeline_cls: Optional[Type[BaseItemPipeline]] = None,
        factory: Optional[Callable[..., BaseItemPipeline]] = None,
    ) -> None:
        """Registers a pipeline class or factory under a given name."""
        if pipeline_cls is not None:
            self._pipelines[name] = pipeline_cls
        if factory is not None:
            self._factories[name] = factory
        logger.debug("Registered pipeline: %s", name)

    def get(self, name: str) -> Optional[Type[BaseItemPipeline]]:
        """Retrieves a registered pipeline class by name."""
        return self._pipelines.get(name)

    def create(
        self, name: str, *args: Any, **kwargs: Any
    ) -> Optional[BaseItemPipeline]:
        """Instantiates a registered pipeline by name."""
        if name in self._factories:
            return self._factories[name](*args, **kwargs)
        pipeline_cls = self._pipelines.get(name)
        if pipeline_cls is not None:
            return pipeline_cls(*args, **kwargs)
        return None

    def list_pipelines(self) -> List[str]:
        """Lists all registered pipeline names."""
        names = set(self._pipelines.keys()) | set(self._factories.keys())
        return sorted(list(names))

    def unregister(self, name: str) -> None:
        """Removes a pipeline registration."""
        self._pipelines.pop(name, None)
        self._factories.pop(name, None)


_GLOBAL_PIPELINE_REGISTRY = PipelineRegistry()


def get_pipeline_registry() -> PipelineRegistry:
    """Returns the global PipelineRegistry singleton."""
    return _GLOBAL_PIPELINE_REGISTRY

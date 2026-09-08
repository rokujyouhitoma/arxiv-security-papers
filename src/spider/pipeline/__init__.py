"""Spider pipeline abstractions and implementations."""

from typing import Any

from .base import (
    BaseItemPipeline,
    ConsoleItemPipeline,
    DropItem,
    JsonLinesItemPipeline,
    PipelineRegistry,
    get_pipeline_registry,
)

__all__ = [
    "BaseItemPipeline",
    "JsonLinesItemPipeline",
    "ConsoleItemPipeline",
    "DropItem",
    "PipelineRegistry",
    "get_pipeline_registry",
]


def __getattr__(name: str) -> Any:
    if name in ("OkfItemPipeline", "SecurityOkfItemPipeline"):
        from domain.security.pipeline.okf_pipeline import SecurityOkfItemPipeline

        return SecurityOkfItemPipeline
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")

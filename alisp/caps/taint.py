"""ALisp Taint Tracking Subsystem.

Provides TaintedValue wrappers, automatic propagation, Sink checks,
and explicit untaint sanitization to prevent sensitive data leaks.
"""

from __future__ import annotations

from typing import Any, Optional, Set

from alisp.caps.base import AccessDeniedException, CapabilityError
from ilisp.evaluator import _apply_procedure
from ilisp.types import Procedure


class TaintLeakViolationException(CapabilityError):
    """Raised when tainted, unverified data is transmitted to an unauthorized sink."""

    def __init__(
        self,
        message: str = "Tainted data leak detected",
        source: str = "unknown",
        sink: str = "unknown",
    ) -> None:
        super().__init__(message)
        self.message = message
        self.source = source
        self.sink = sink

    def __str__(self) -> str:
        return self.message


class TaintedValue:
    """Wrapper holding sensitive or untrusted values with provenance tracking."""

    __slots__ = ("_value", "_source", "_tags")

    def __init__(
        self,
        value: Any,
        source: str = "external",
        tags: Optional[Set[str]] = None,
    ) -> None:
        # If value is already tainted, preserve original provenance or merge
        if isinstance(value, TaintedValue):
            self._value = value._value
            self._source = value._source
            merged_tags = set(value._tags)
            if tags:
                merged_tags.update(tags)
            self._tags = merged_tags
        else:
            self._value = value
            self._source = source
            self._tags = set(tags) if tags is not None else {"tainted"}

    @property
    def value(self) -> Any:
        return self._value

    @property
    def source(self) -> str:
        return self._source

    @property
    def tags(self) -> Set[str]:
        return self._tags

    def unwrap(self) -> Any:
        return self._value

    def __repr__(self) -> str:
        return f"#<tainted:{self._source} {self._value!r}>"

    def __str__(self) -> str:
        return str(self._value)

    def __eq__(self, other: Any) -> bool:
        if isinstance(other, TaintedValue):
            return bool(self._value == other._value)
        return bool(self._value == other)

    def __hash__(self) -> int:
        return hash(self._value)

    def __len__(self) -> int:
        return len(self._value)

    def __getitem__(self, item: Any) -> Any:
        res = self._value[item]
        # Propagate taint to sliced sub-elements if string/bytes
        if isinstance(res, (str, bytes)):
            return TaintedValue(res, source=self._source, tags=self._tags)
        return res

    def __add__(self, other: Any) -> TaintedValue:
        other_raw = other.unwrap() if isinstance(other, TaintedValue) else other
        res = self._value + other_raw
        tags = set(self._tags)
        if isinstance(other, TaintedValue):
            tags.update(other._tags)
        return TaintedValue(res, source=self._source, tags=tags)

    def __radd__(self, other: Any) -> TaintedValue:
        other_raw = other.unwrap() if isinstance(other, TaintedValue) else other
        res = other_raw + self._value
        tags = set(self._tags)
        if isinstance(other, TaintedValue):
            tags.update(other._tags)
        return TaintedValue(res, source=self._source, tags=tags)


def taint(
    value: Any,
    source: str = "external",
    tags: Optional[Set[str]] = None,
) -> TaintedValue:
    """Tag a value as tainted with the given source and tags."""
    return TaintedValue(value, source=source, tags=tags)


def is_tainted(obj: Any) -> bool:
    """Return True if obj is a TaintedValue or contains tainted data."""
    return isinstance(obj, TaintedValue)


def untaint(obj: Any, predicate: Any) -> Any:
    """Sanitize and unwrap tainted data if the predicate holds true.

    Raises AccessDeniedException or CapabilityError if predicate check fails.
    """
    if not isinstance(obj, TaintedValue):
        return obj

    raw_val = obj.unwrap()
    verified = False

    if isinstance(predicate, Procedure):
        res = _apply_procedure(predicate, [raw_val])
        # In Scheme, anything other than #f is truthy
        verified = res is not False
    elif callable(predicate):
        verified = bool(predicate(raw_val))
    else:
        raise TypeError(
            f"untaint predicate must be callable or Procedure, got {predicate!r}"
        )

    if not verified:
        raise AccessDeniedException(
            f"Untaint verification failed for tainted value from '{obj.source}': "
            f"predicate rejected value {raw_val!r}"
        )

    return raw_val


def check_sink(value: Any, sink_name: str) -> None:
    """Assert that value is not tainted before passing to an external sink."""
    if is_tainted(value):
        tv: TaintedValue = value
        raise TaintLeakViolationException(
            f"Tainted value from source '{tv.source}' leaked to unauthorized sink '{sink_name}'",
            source=tv.source,
            sink=sink_name,
        )

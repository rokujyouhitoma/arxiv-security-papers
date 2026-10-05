"""ALisp Capability Base Architecture.

Defines the abstract Capability base class and attenuation mechanics.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any


class CapabilityError(Exception):
    """Base exception for capability and sandbox violations in ALisp."""

    pass


class AccessDeniedException(CapabilityError, AttributeError):
    """Raised when an operation is performed without the required capability or authority."""

    pass


class Capability(ABC):
    """Abstract base class representing an unforgeable authority token."""

    name: str = "capability"

    @abstractmethod
    def attenuate(self, **kwargs: Any) -> Capability:
        """Derive a more restricted child capability from this capability."""
        raise NotImplementedError

    def __repr__(self) -> str:
        return f"#<{self.__class__.__name__} name={self.name}>"

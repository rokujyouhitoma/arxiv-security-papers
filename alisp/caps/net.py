"""ALisp Network Capability (net-cap).

Implements network communication authority, host/method whitelisting,
capability attenuation, and Taint Sink protection against data exfiltration.
"""

from __future__ import annotations

from typing import Any, Optional, Sequence, Set
from urllib.parse import urlparse

from alisp.caps.base import AccessDeniedException, Capability
from alisp.caps.taint import check_sink, is_tainted


class NetworkCapability(Capability):
    """Capability governing network request authority and egress data flow."""

    name = "net-cap"

    def __init__(
        self,
        allowed_hosts: Optional[Sequence[str]] = None,
        allowed_methods: Optional[Sequence[str]] = None,
        byte_budget: int = 1024 * 1024,
    ) -> None:
        self.allowed_hosts: Set[str] = {
            h.lower().strip() for h in (allowed_hosts or [])
        }
        self.allowed_methods: Set[str] = {
            m.upper().strip() for m in (allowed_methods or ["GET"])
        }
        self.byte_budget = byte_budget
        self.bytes_transferred = 0

    def is_host_allowed(self, host: str) -> bool:
        """Return True if host is in the allowed host whitelist."""
        clean_host = host.lower().strip()
        if ":" in clean_host:
            clean_host = clean_host.split(":")[0]

        if clean_host in self.allowed_hosts:
            return True

        # Check domain suffix matches (e.g. *.arxiv.org)
        for allowed in self.allowed_hosts:
            if allowed.startswith("*.") and clean_host.endswith(allowed[1:]):
                return True
        return False

    def is_method_allowed(self, method: str) -> bool:
        """Return True if HTTP method is in the allowed method set."""
        return method.upper().strip() in self.allowed_methods

    def check_request(
        self,
        url: str,
        method: str = "GET",
        data: Any = None,
    ) -> str:
        """Verify that network request to url with method is permitted under this capability."""
        parsed = urlparse(url)
        host = parsed.hostname or url
        method_upper = method.upper().strip()

        if not self.is_host_allowed(host):
            raise AccessDeniedException(
                f"Network egress denied to host '{host}' under net-cap "
                f"(allowed hosts: {sorted(self.allowed_hosts)})"
            )

        # Taint Sink Check: prevent exfiltrating tainted data immediately
        if data is not None and is_tainted(data):
            check_sink(data, f"network-egress:{host}")

        if not self.is_method_allowed(method_upper):
            raise AccessDeniedException(
                f"Network method '{method_upper}' not allowed under net-cap "
                f"(allowed methods: {sorted(self.allowed_methods)})"
            )

        return url

    def attenuate(
        self,
        allowed_hosts: Optional[Sequence[str]] = None,
        allowed_methods: Optional[Sequence[str]] = None,
        byte_budget: Optional[int] = None,
    ) -> NetworkCapability:
        """Derive an attenuated child NetworkCapability with narrower scope."""
        if allowed_hosts is not None:
            child_hosts = {h.lower().strip() for h in allowed_hosts}
            for h in child_hosts:
                if not self.is_host_allowed(h):
                    raise AccessDeniedException(
                        f"Cannot attenuate net-cap: host '{h}' is not permitted by parent"
                    )
            new_hosts = child_hosts
        else:
            new_hosts = set(self.allowed_hosts)

        if allowed_methods is not None:
            child_methods = {m.upper().strip() for m in allowed_methods}
            for m in child_methods:
                if not self.is_method_allowed(m):
                    raise AccessDeniedException(
                        f"Cannot attenuate net-cap: method '{m}' is not permitted by parent"
                    )
            new_methods = child_methods
        else:
            new_methods = set(self.allowed_methods)

        new_budget = (
            min(self.byte_budget, byte_budget)
            if byte_budget is not None
            else self.byte_budget
        )

        return NetworkCapability(
            allowed_hosts=sorted(new_hosts),
            allowed_methods=sorted(new_methods),
            byte_budget=new_budget,
        )

    def __repr__(self) -> str:
        return (
            f"#<net-cap hosts={len(self.allowed_hosts)} "
            f"methods={sorted(self.allowed_methods)}>"
        )

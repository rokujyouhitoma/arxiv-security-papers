#!/usr/bin/env python3
"""
Unit tests for SSRF Protection & Network Isolation Validation.
"""

import socket
from unittest.mock import MagicMock, patch

import pytest

from src.security.validation.network import (
    DEFAULT_ALLOWED_SCHEMES,
    METADATA_IPS,
    SSRFSecurityError,
    create_safe_socket,
    is_safe_remote_url,
    resolve_and_validate_ip,
    safe_http_fetch,
)


def test_network_constants() -> None:
    """Verifies default schemes and metadata IP definitions."""
    assert "http" in DEFAULT_ALLOWED_SCHEMES
    assert "https" in DEFAULT_ALLOWED_SCHEMES
    assert "169.254.169.254" in METADATA_IPS


def test_resolve_and_validate_ip_prohibited_ranges() -> None:
    """Tests that loopback, RFC 1918, link-local, multicast, and metadata are rejected."""
    prohibited_cases = [
        "127.0.0.1",
        "127.0.0.254",
        "::1",
        "10.0.0.1",
        "10.254.254.254",
        "172.16.0.1",
        "172.31.255.255",
        "192.168.1.1",
        "169.254.169.254",
        "169.254.1.1",
        "fe80::1",
        "224.0.0.1",
        "ff02::1",
        "0.0.0.0",
        "::",
        "::ffff:127.0.0.1",
        "::ffff:169.254.169.254",
        "::ffff:10.0.0.1",
    ]
    for ip in prohibited_cases:
        is_safe, _, reason = resolve_and_validate_ip(ip)
        assert (
            not is_safe
        ), f"Expected {ip} to be rejected, but passed. Reason: {reason}"
        assert reason is not None


def test_resolve_and_validate_ip_public_address() -> None:
    """Tests that public, non-private IPs are approved."""
    safe_cases = [
        "8.8.8.8",
        "1.1.1.1",
        "93.184.216.34",  # example.com
        "2606:4700:4700::1111",
    ]
    for ip in safe_cases:
        is_safe, resolved_ip, reason = resolve_and_validate_ip(ip)
        assert is_safe, f"Expected {ip} to be safe, but failed: {reason}"
        assert resolved_ip == ip
        assert reason is None


def test_resolve_and_validate_ip_invalid_and_empty() -> None:
    """Tests empty hostnames, null bytes, and non-resolvable domains."""
    assert not resolve_and_validate_ip("")[0]
    assert not resolve_and_validate_ip("host\x00name")[0]
    with patch(
        "socket.getaddrinfo",
        side_effect=socket.gaierror(-2, "Name or service not known"),
    ):
        is_safe, _, reason = resolve_and_validate_ip("nonexistent-domain-xyz-12345.org")
        assert not is_safe
        assert reason is not None and "DNS resolution failed" in reason


def test_is_safe_remote_url_schemes() -> None:
    """Tests URL scheme filtering."""
    assert not is_safe_remote_url("file:///etc/passwd")
    assert not is_safe_remote_url("ftp://ftp.example.com/file.txt")
    assert not is_safe_remote_url("gopher://evil.com/")
    assert not is_safe_remote_url("dict://evil.com/")
    assert not is_safe_remote_url("javascript:alert(1)")
    assert not is_safe_remote_url("")
    assert not is_safe_remote_url(None)  # type: ignore[arg-type]
    assert not is_safe_remote_url("https://example.com\x00")


def test_is_safe_remote_url_credentials() -> None:
    """Tests URL userinfo / credentials blocking."""
    assert not is_safe_remote_url("https://user:password@example.com")
    assert not is_safe_remote_url("http://admin@example.com")
    # Allowed when explicitly permitted
    with patch(
        "src.security.validation.network.resolve_and_validate_ip",
        return_value=(True, "93.184.216.34", None),
    ):
        assert is_safe_remote_url(
            "https://user:password@example.com", allow_user_info=True
        )


def test_is_safe_remote_url_internal_targets() -> None:
    """Tests URL pointing to internal / loopback / metadata targets."""
    assert not is_safe_remote_url("http://127.0.0.1:8080/status")
    assert not is_safe_remote_url("http://169.254.169.254/latest/meta-data/")
    assert not is_safe_remote_url("http://10.0.1.2/internal-api")
    assert not is_safe_remote_url("http://192.168.0.1/admin")


def test_is_safe_remote_url_public_domain() -> None:
    """Tests valid remote URL with mock DNS resolution."""
    with patch(
        "src.security.validation.network.resolve_and_validate_ip",
        return_value=(True, "93.184.216.34", None),
    ):
        assert is_safe_remote_url("https://arxiv.org/abs/2301.00001")
        assert is_safe_remote_url("http://example.com/test?query=1")


def test_create_safe_socket_rejection() -> None:
    """Tests that create_safe_socket raises SSRFSecurityError for unsafe hosts."""
    with pytest.raises(SSRFSecurityError, match="rejected by SSRF guard"):
        create_safe_socket("127.0.0.1", 80)

    with pytest.raises(SSRFSecurityError, match="rejected by SSRF guard"):
        create_safe_socket("169.254.169.254", 80)


def test_create_safe_socket_pinned_connection() -> None:
    """Tests socket creation connects directly to the safe IP."""
    mock_sock = MagicMock(spec=socket.socket)
    with patch(
        "src.security.validation.network.resolve_and_validate_ip",
        return_value=(True, "93.184.216.34", None),
    ), patch("socket.socket", return_value=mock_sock):
        sock = create_safe_socket("example.com", 80, timeout=5.0)
        assert sock == mock_sock
        mock_sock.settimeout.assert_called_once_with(5.0)
        mock_sock.connect.assert_called_once_with(("93.184.216.34", 80))


def test_safe_http_fetch_blocks_unsafe_start_url() -> None:
    """Tests safe_http_fetch rejects unsafe entry URL."""
    with pytest.raises(SSRFSecurityError):
        safe_http_fetch("http://127.0.0.1:8080/secret")


def test_safe_http_fetch_blocks_redirect_to_internal_ip() -> None:
    """Tests that redirecting to private / metadata IP is intercepted and blocked."""
    mock_sock = MagicMock(spec=socket.socket)
    # Simulate first response: 302 redirect to http://169.254.169.254/latest
    redirect_resp = (
        b"HTTP/1.1 302 Found\r\n"
        b"Location: http://169.254.169.254/latest\r\n"
        b"Content-Length: 0\r\n\r\n"
    )
    mock_sock.recv.side_effect = [redirect_resp, b""]

    with patch(
        "src.security.validation.network.is_safe_remote_url", side_effect=[True, False]
    ), patch(
        "src.security.validation.network.create_safe_socket", return_value=mock_sock
    ):
        with pytest.raises(SSRFSecurityError, match="rejected by SSRF guard"):
            safe_http_fetch("https://external.example.com/redirect")


def test_safe_http_fetch_success() -> None:
    """Tests successful safe HTTP fetch."""
    mock_sock = MagicMock(spec=socket.socket)
    http_resp = (
        b"HTTP/1.1 200 OK\r\n"
        b"Content-Type: text/plain\r\n"
        b"Content-Length: 12\r\n\r\n"
        b"Hello World!"
    )
    mock_sock.recv.side_effect = [http_resp, b""]

    with patch(
        "src.security.validation.network.is_safe_remote_url", return_value=True
    ), patch(
        "src.security.validation.network.create_safe_socket", return_value=mock_sock
    ):
        status, headers, body = safe_http_fetch("https://arxiv.org/robots.txt")
        assert status == 200
        assert headers.get("content-type") == "text/plain"
        assert body == b"Hello World!"

#!/usr/bin/env python3
"""
SSRF Protection & Network Isolation Validation Module.
Provides URL validation, IP address resolution safety checks, and pinned-socket creation
to defend against Server-Side Request Forgery (SSRF) and DNS-rebinding attacks.
Zero external runtime dependencies (Python standard library only).
"""

import ipaddress
import socket
import ssl
import urllib.parse
from typing import Dict, List, Optional, Set, Tuple, Union


class SSRFSecurityError(ValueError):
    """Raised when a remote network request violates SSRF or network isolation rules."""

    pass


# Default allowed URL schemes
DEFAULT_ALLOWED_SCHEMES: Set[str] = {"http", "https"}

# Well-known cloud metadata endpoints and prohibited addresses
METADATA_IPS: Set[str] = {
    "169.254.169.254",  # AWS EC2 / Azure / GCP metadata
    "169.254.170.2",  # AWS ECS task metadata
    "fd00:ec2::254",  # AWS IPv6 metadata
}


def _check_url_scheme(
    parsed: urllib.parse.ParseResult, allowed_schemes: Set[str]
) -> bool:
    """Verifies that the URL scheme is within the allowed set."""
    if not parsed.scheme:
        return False
    return parsed.scheme.lower() in allowed_schemes


def _check_url_credentials(
    parsed: urllib.parse.ParseResult, allow_user_info: bool
) -> bool:
    """Checks whether URL contains user credentials (e.g., user:pass@host)."""
    if allow_user_info:
        return True
    return parsed.username is None and parsed.password is None


def _check_ip_mapped_v4(
    ip: Union[ipaddress.IPv4Address, ipaddress.IPv6Address],
) -> Tuple[bool, Optional[str]]:
    """Validates IPv4-mapped IPv6 address (e.g. ::ffff:127.0.0.1)."""
    if isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped is not None:
        return _is_prohibited_ip_obj(ip.ipv4_mapped)
    return False, None


def _is_cloud_or_loopback_ip(
    ip: Union[ipaddress.IPv4Address, ipaddress.IPv6Address],
) -> Tuple[bool, Optional[str]]:
    """Checks for cloud metadata endpoints or loopback addresses."""
    ip_str = str(ip)
    if ip_str in METADATA_IPS:
        return True, f"cloud metadata IP: {ip_str}"
    if ip.is_loopback:
        return True, f"loopback address: {ip_str}"
    return False, None


def _is_private_or_link_local_ip(
    ip: Union[ipaddress.IPv4Address, ipaddress.IPv6Address],
) -> Tuple[bool, Optional[str]]:
    """Checks for RFC 1918 private or link-local addresses."""
    ip_str = str(ip)
    if ip.is_private:
        return True, f"private network address: {ip_str}"
    if ip.is_link_local:
        return True, f"link-local address: {ip_str}"
    return False, None


def _is_special_range_ip(
    ip: Union[ipaddress.IPv4Address, ipaddress.IPv6Address],
) -> Tuple[bool, Optional[str]]:
    """Checks for multicast, reserved, or unspecified addresses."""
    ip_str = str(ip)
    if ip.is_multicast:
        return True, f"multicast address: {ip_str}"
    if ip.is_reserved or ip.is_unspecified:
        return True, f"reserved/unspecified address: {ip_str}"
    return False, None


def _is_prohibited_ip_obj(
    ip: Union[ipaddress.IPv4Address, ipaddress.IPv6Address],
) -> Tuple[bool, Optional[str]]:
    """Evaluates whether an IP address belongs to any prohibited network range."""
    checkers = (
        _is_cloud_or_loopback_ip,
        _is_private_or_link_local_ip,
        _is_special_range_ip,
    )
    for checker in checkers:
        prohibited, reason = checker(ip)
        if prohibited:
            return True, reason

    is_mapped_prohibited, reason = _check_ip_mapped_v4(ip)
    if is_mapped_prohibited:
        return True, f"IPv4-mapped {reason}"

    return False, None


def _resolve_ips_for_host(hostname: str) -> List[Tuple[int, str]]:
    """Resolves all IP addresses for a given hostname using socket.getaddrinfo."""
    clean_host = hostname.strip("[]")
    results = socket.getaddrinfo(clean_host, None, socket.AF_UNSPEC, socket.SOCK_STREAM)
    extracted: List[Tuple[int, str]] = []
    for entry in results:
        family, _, _, _, sockaddr = entry
        item = (int(family), str(sockaddr[0]))
        if item not in extracted:
            extracted.append(item)
    return extracted


def _validate_single_ip_str(ip_str: str) -> Tuple[bool, Optional[str]]:
    """Parses and checks an individual IP string against prohibited ranges."""
    try:
        ip_obj = ipaddress.ip_address(ip_str)
        return _is_prohibited_ip_obj(ip_obj)
    except ValueError as e:
        return True, f"invalid IP address: {e}"


def _check_ip_candidates(
    ip_candidates: List[Tuple[int, str]],
) -> Tuple[bool, Optional[str], Optional[str]]:
    """Iterates through candidate IPs to ensure all are safe."""
    safe_ip: Optional[str] = None
    for _, ip_str in ip_candidates:
        prohibited, reason = _validate_single_ip_str(ip_str)
        if prohibited:
            return False, ip_str, reason
        if safe_ip is None:
            safe_ip = ip_str
    return True, safe_ip, None


def resolve_and_validate_ip(hostname: str) -> Tuple[bool, Optional[str], Optional[str]]:
    """
    Resolves a hostname to IP addresses and checks every IP against SSRF rules.
    Returns:
        (is_safe, first_safe_ip, error_reason)
    """
    if not hostname or "\x00" in hostname:
        return False, None, "empty or invalid hostname"

    try:
        ip_candidates = _resolve_ips_for_host(hostname)
        if not ip_candidates:
            return False, None, f"unable to resolve hostname: {hostname}"
        return _check_ip_candidates(ip_candidates)
    except socket.gaierror as e:
        return False, None, f"DNS resolution failed: {e}"


def _validate_url_syntax(url: Optional[str]) -> Optional[urllib.parse.ParseResult]:
    """Validates URL string basic integrity and parses."""
    if not url or not isinstance(url, str) or "\x00" in url:
        return None
    try:
        return urllib.parse.urlparse(url)
    except Exception:
        return None


def _validate_url_components(
    parsed: urllib.parse.ParseResult,
    allowed_schemes: Optional[Set[str]],
    allow_user_info: bool,
) -> bool:
    """Verifies parsed URL scheme, credentials, and hostname presence."""
    schemes = (
        allowed_schemes if allowed_schemes is not None else DEFAULT_ALLOWED_SCHEMES
    )
    if not _check_url_scheme(parsed, schemes):
        return False
    if not _check_url_credentials(parsed, allow_user_info):
        return False
    return bool(parsed.hostname)


def is_safe_remote_url(
    url: str,
    allowed_schemes: Optional[Set[str]] = None,
    allow_user_info: bool = False,
    validate_dns: bool = True,
) -> bool:
    """
    Validates that a URL is safe to fetch from a remote source.
    Rejects invalid schemes, embedded user credentials, and private/metadata destinations.
    """
    parsed = _validate_url_syntax(url)
    if parsed is None or not _validate_url_components(
        parsed, allowed_schemes, allow_user_info
    ):
        return False

    if validate_dns:
        hostname = str(parsed.hostname)
        is_safe, _, _ = resolve_and_validate_ip(hostname)
        return is_safe
    return True


def _connect_and_bind_socket(
    target_ip: str, port: int, timeout: float
) -> socket.socket:
    """Creates a raw socket, connects directly to target IP, and configures timeout."""
    ip_obj = ipaddress.ip_address(target_ip)
    family = socket.AF_INET6 if ip_obj.version == 6 else socket.AF_INET
    sock = socket.socket(family, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        sock.connect((target_ip, port))
        return sock
    except Exception:
        sock.close()
        raise


def create_safe_socket(
    hostname: str,
    port: int,
    timeout: float = 10.0,
    ssl_context: Optional[ssl.SSLContext] = None,
) -> socket.socket:
    """
    Creates a network socket connected to a verified non-private IP.
    Pins connection directly to resolved IP to prevent DNS-rebinding attacks.
    If ssl_context is provided, completes TLS handshake with SNI server_hostname.
    """
    is_safe, safe_ip, reason = resolve_and_validate_ip(hostname)
    if not is_safe or safe_ip is None:
        raise SSRFSecurityError(f"Host '{hostname}' rejected by SSRF guard: {reason}")

    sock = _connect_and_bind_socket(safe_ip, port, timeout)

    if ssl_context is not None:
        try:
            return ssl_context.wrap_socket(sock, server_hostname=hostname)
        except Exception:
            sock.close()
            raise

    return sock


def _read_all_response(sock: socket.socket, buffer_size: int = 65536) -> bytes:
    """Reads all incoming bytes from a socket until EOF."""
    chunks: List[bytes] = []
    while True:
        data = sock.recv(buffer_size)
        if not data:
            break
        chunks.append(data)
    return b"".join(chunks)


def _build_http_request_payload(
    parsed: urllib.parse.ParseResult,
    method: str,
    headers: Optional[Dict[str, str]],
) -> bytes:
    """Builds standard HTTP 1.1 request wire bytes."""
    path = parsed.path if parsed.path else "/"
    if parsed.query:
        path = f"{path}?{parsed.query}"

    req_headers: Dict[str, str] = {
        "Host": parsed.netloc,
        "User-Agent": "arxiv-security-papers-safe-fetcher/1.0",
        "Connection": "close",
        "Accept": "*/*",
    }
    if headers:
        req_headers.update(headers)

    header_lines = [f"{k}: {v}" for k, v in req_headers.items()]
    req_str = f"{method} {path} HTTP/1.1\r\n" + "\r\n".join(header_lines) + "\r\n\r\n"
    return req_str.encode("latin-1")


def _extract_status_code(first_line: str) -> int:
    """Extracts integer HTTP status code from the initial response line."""
    parts = first_line.split()
    if len(parts) >= 2 and parts[1].isdigit():
        return int(parts[1])
    return 500


def _parse_headers_map(lines: List[str]) -> Dict[str, str]:
    """Parses raw HTTP response header lines into a normalized lowercase dict."""
    headers: Dict[str, str] = {}
    for line in lines:
        if ":" in line:
            k, v = line.split(":", 1)
            headers[k.strip().lower()] = v.strip()
    return headers


def _parse_http_status_and_body(raw_data: bytes) -> Tuple[int, Dict[str, str], bytes]:
    """Parses raw HTTP wire response into status code, headers dict, and body."""
    header_end = raw_data.find(b"\r\n\r\n")
    if header_end == -1:
        return 500, {}, raw_data

    header_text = raw_data[:header_end].decode("latin-1", errors="replace")
    lines = header_text.split("\r\n")
    status_code = _extract_status_code(lines[0]) if lines else 500
    headers = _parse_headers_map(lines[1:])
    body_bytes = raw_data[header_end + 4 :]
    return status_code, headers, body_bytes


def _get_target_port(parsed: urllib.parse.ParseResult) -> int:
    """Determines port from URL netloc or defaults to 80 / 443."""
    if parsed.port is not None:
        return parsed.port
    return 443 if parsed.scheme == "https" else 80


def _execute_single_http_attempt(
    current_url: str,
    method: str,
    timeout: float,
    headers: Optional[Dict[str, str]],
) -> Tuple[int, Dict[str, str], bytes]:
    """Connects to host, sends HTTP request, and reads back raw response."""
    parsed = urllib.parse.urlparse(current_url)
    hostname = parsed.hostname
    if not hostname:
        raise SSRFSecurityError(f"URL '{current_url}' missing valid hostname")

    port = _get_target_port(parsed)
    ssl_ctx = ssl.create_default_context() if parsed.scheme == "https" else None
    sock = create_safe_socket(hostname, port, timeout=timeout, ssl_context=ssl_ctx)
    try:
        sock.sendall(_build_http_request_payload(parsed, method, headers))
        raw_resp = _read_all_response(sock)
    finally:
        sock.close()

    return _parse_http_status_and_body(raw_resp)


def _is_redirect_status(status: int, headers: Dict[str, str]) -> bool:
    """Checks if response is a redirection status code containing a Location header."""
    return status in (301, 302, 303, 307, 308) and "location" in headers


def safe_http_fetch(
    url: str,
    method: str = "GET",
    timeout: float = 10.0,
    max_redirects: int = 5,
    headers: Optional[Dict[str, str]] = None,
) -> Tuple[int, Dict[str, str], bytes]:
    """
    Executes a secure HTTP request with full SSRF and DNS-rebinding protection.
    Follows redirects securely, enforcing SSRF validation on every target location.
    """
    current_url = url
    for _ in range(max_redirects + 1):
        if not is_safe_remote_url(current_url):
            raise SSRFSecurityError(f"URL '{current_url}' rejected by SSRF guard")

        status, resp_headers, body = _execute_single_http_attempt(
            current_url, method, timeout, headers
        )
        if _is_redirect_status(status, resp_headers):
            current_url = urllib.parse.urljoin(current_url, resp_headers["location"])
            continue

        return status, resp_headers, body

    raise SSRFSecurityError(f"Exceeded maximum redirects ({max_redirects})")

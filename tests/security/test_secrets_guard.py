#!/usr/bin/env python3
"""
Unit tests for Secrets & Token Management Guard.
"""

import pytest

from src.security.secrets.crypto_util import (
    constant_time_compare,
    generate_csrf_token,
    generate_secure_token,
    verify_csrf_token,
)
from src.security.secrets.manager import (
    EphemeralSecretStore,
    SecretFinding,
    detect_exposed_secrets,
    mask_secret,
)


def test_ephemeral_secret_store_lifecycle() -> None:
    """Tests setting, retrieving, overwriting, and secure zeroization."""
    store = EphemeralSecretStore()
    store.set_secret("arxiv_api_key", "secret_value_12345")
    store.set_secret("raw_bytes_key", b"\x01\x02\x03\x04")

    assert len(store) == 2
    assert store.get_secret("arxiv_api_key") == "secret_value_12345"
    assert store.get_secret_bytes("raw_bytes_key") == b"\x01\x02\x03\x04"

    # Grab reference to internal buffer to verify zeroization on delete
    buf_ref = store._store["arxiv_api_key"]
    assert any(b != 0 for b in buf_ref)

    deleted = store.delete_secret("arxiv_api_key")
    assert deleted
    assert all(b == 0 for b in buf_ref)
    assert store.get_secret("arxiv_api_key") is None
    assert len(store) == 1

    # Zeroize entire store
    remaining_buf = store._store["raw_bytes_key"]
    store.zeroize()
    assert len(store) == 0
    assert all(b == 0 for b in remaining_buf)


def test_ephemeral_secret_store_empty_key() -> None:
    """Tests rejection of empty key."""
    store = EphemeralSecretStore()
    with pytest.raises(ValueError, match="cannot be empty"):
        store.set_secret("", "val")


def test_mask_secret() -> None:
    """Tests masking utility across standard and edge cases."""
    assert mask_secret("sk-1234567890abcdef", reveal_len=4) == "***************cdef"
    assert mask_secret("1234", reveal_len=4) == "****"
    assert mask_secret("12", reveal_len=4) == "**"
    assert mask_secret("", reveal_len=4) == ""
    assert (
        mask_secret("my_token_value", reveal_len=3, mask_char="#") == "###########lue"
    )


def test_detect_exposed_secrets_known_patterns() -> None:
    """Tests regex detection of AWS, GitHub, OpenAI keys, and private keys."""
    sample_text = (
        "Logs: Connecting with AWS AKIAIOSFODNN7EXAMPLE and "
        "GitHub token ghp_1234567890abcdefghijklmnopqrstuvwxyz. "
        "Also OpenAI sk-abcdefghijklmnopqrstuvwxyz123456. "
        "-----BEGIN RSA PRIVATE KEY-----\nMIIEogIBAAKCAQEA..."
    )
    findings = detect_exposed_secrets(sample_text, check_entropy=False)
    pattern_names = [f.pattern_name for f in findings]

    assert "AWS_ACCESS_KEY" in pattern_names
    assert "GITHUB_TOKEN" in pattern_names
    assert "OPENAI_API_KEY" in pattern_names
    assert "PRIVATE_KEY_BLOCK" in pattern_names

    # Check previews are masked and typed as SecretFinding
    for f in findings:
        assert isinstance(f, SecretFinding)
        assert "*" in f.preview


def test_detect_exposed_secrets_entropy() -> None:
    """Tests Shannon entropy detection of random cryptographic tokens."""
    random_token = "K9zXw7bM2vP4qL1tR8yU5oI3sA6dF0hJ"
    text = f"API query parameter token={random_token} in request"
    findings = detect_exposed_secrets(text, check_entropy=True, min_entropy=4.0)

    assert any(f.pattern_name == "HIGH_ENTROPY_SECRET" for f in findings)


def test_detect_exposed_secrets_clean_text() -> None:
    """Tests that ordinary prose contains no exposed secret false positives."""
    clean_text = (
        "This paper investigates network intrusion detection using deep learning."
    )
    findings = detect_exposed_secrets(clean_text)
    assert len(findings) == 0


def test_constant_time_compare() -> None:
    """Tests timing-attack-resistant comparison."""
    assert constant_time_compare("correct_token_12345", "correct_token_12345")
    assert constant_time_compare(b"binary_key", b"binary_key")
    assert not constant_time_compare("correct_token", "wrong_token")
    assert not constant_time_compare(b"bin1", b"bin2")


def test_csrf_token_lifecycle() -> None:
    """Tests CSRF token generation and constant-time validation."""
    token = generate_csrf_token()
    assert isinstance(token, str)
    assert len(token) >= 32

    assert verify_csrf_token(token, token)
    assert not verify_csrf_token(token, "tampered_token")
    assert not verify_csrf_token("", token)
    assert not verify_csrf_token(token, "")


def test_generate_secure_token_options() -> None:
    """Tests token generation formats and error handling."""
    url_token = generate_secure_token(16, url_safe=True)
    hex_token = generate_secure_token(16, url_safe=False)

    assert len(url_token) > 0
    assert len(hex_token) == 32  # 16 bytes hex is 32 chars

    with pytest.raises(ValueError, match="must be positive"):
        generate_secure_token(-5)

"""Tests for ALisp Phase 2: Object-Capability, ManagedPort, and Transaction Rollback.

Verifies:
- Capability base class and Principle of Attenuation.
- FileSystemCapability (fs-cap) with strict path prefix whitelisting and loopback isolation.
- NetworkCapability (net-cap) with host/method restrictions and taint sink protection.
- ManagedPort with Byte Budget quota enforcement (PortQuotaExceededException).
- 100% blocking of destructive file I/O (open-output-file, etc.) when fs-cap is missing.
- Safe in-memory loopback redirection for unauthorized write paths leaving physical disk untouched.
- with-fuel automatic snapshot and atomic transaction rollback of state mutations (set!) on fuel exhaustion.
- TaintedValue lifecycle, propagation, untaint primitive, and exfiltration prevention.
- with-caps macro and scoped authority delegation.
"""

import os
import shutil
import tempfile

import pytest

from alisp import (
    AccessDeniedException,
    ALispEngine,
    FileSystemCapability,
    FuelExhaustedException,
    ManagedTextualOutputPort,
    NetworkCapability,
    PortQuotaExceededException,
    TaintLeakViolationException,
    is_tainted,
    make_loopback_binary_port,
    make_loopback_textual_port,
    taint,
)
from ilisp.types import Bytevector


@pytest.fixture
def sandbox_dirs():
    """Create isolated temporary directories for test files."""
    base_dir = tempfile.mkdtemp(prefix="alisp_test_")
    allowed_dir = os.path.join(base_dir, "allowed")
    forbidden_dir = os.path.join(base_dir, "forbidden")
    os.makedirs(allowed_dir, exist_ok=True)
    os.makedirs(forbidden_dir, exist_ok=True)
    try:
        yield allowed_dir, forbidden_dir
    finally:
        shutil.rmtree(base_dir, ignore_errors=True)


class TestCapabilityAttenuation:
    """Test the Principle of Attenuation: authority can only decay, never escalate."""

    def test_fs_cap_attenuation_narrower_paths_allowed(self, sandbox_dirs):
        allowed_dir, forbidden_dir = sandbox_dirs
        sub_dir = os.path.join(allowed_dir, "sub")
        os.makedirs(sub_dir, exist_ok=True)

        parent_cap = FileSystemCapability(
            allowed_read_paths=[allowed_dir],
            allowed_write_paths=[allowed_dir],
            byte_budget=1024 * 1024,
        )

        # Attenuating to a sub-directory is valid
        child_cap = parent_cap.attenuate(
            allowed_read_paths=[sub_dir],
            allowed_write_paths=[sub_dir],
            byte_budget=512,
        )
        assert child_cap.is_read_allowed(sub_dir)
        assert child_cap.is_write_allowed(sub_dir)
        assert child_cap.byte_budget == 512

    def test_fs_cap_attenuation_escalation_rejected(self, sandbox_dirs):
        allowed_dir, forbidden_dir = sandbox_dirs

        parent_cap = FileSystemCapability(
            allowed_read_paths=[allowed_dir],
            allowed_write_paths=[allowed_dir],
        )

        # Attempting to escalate to forbidden_dir must raise AccessDeniedException
        with pytest.raises(AccessDeniedException) as exc_info:
            parent_cap.attenuate(allowed_read_paths=[forbidden_dir])
        assert "not permitted by parent" in str(exc_info.value)

        with pytest.raises(AccessDeniedException):
            parent_cap.attenuate(allowed_write_paths=[forbidden_dir])

    def test_net_cap_attenuation(self):
        parent_cap = NetworkCapability(
            allowed_hosts=["arxiv.org", "api.semanticscholar.org"],
            allowed_methods=["GET", "HEAD"],
            byte_budget=2048,
        )

        child_cap = parent_cap.attenuate(
            allowed_hosts=["arxiv.org"],
            allowed_methods=["GET"],
            byte_budget=1024,
        )
        assert child_cap.is_host_allowed("arxiv.org")
        assert not child_cap.is_host_allowed("api.semanticscholar.org")
        assert child_cap.is_method_allowed("GET")
        assert not child_cap.is_method_allowed("HEAD")
        assert child_cap.byte_budget == 1024

        # Escalating host is rejected
        with pytest.raises(AccessDeniedException):
            parent_cap.attenuate(allowed_hosts=["evil.com"])

        # Escalating method is rejected
        with pytest.raises(AccessDeniedException):
            parent_cap.attenuate(allowed_methods=["POST"])


class TestManagedPortAndByteBudget:
    """Test Byte Budget quotas and in-memory loopback ports."""

    def test_textual_port_budget_quota_enforcement(self):
        port = make_loopback_textual_port(byte_budget=10)
        port.write_string("12345")
        assert port.bytes_transferred == 5

        # Writing within remaining budget
        port.write_string("67890")
        assert port.bytes_transferred == 10

        # Exceeding budget triggers PortQuotaExceededException
        with pytest.raises(PortQuotaExceededException) as exc_info:
            port.write_char("!")
        assert exc_info.value.budget == 10
        assert exc_info.value.transferred == 11

    def test_binary_port_budget_quota_enforcement(self):
        port = make_loopback_binary_port(byte_budget=4)
        bv = Bytevector([1, 2, 3])
        port.write_bytevector(bv)
        assert port.bytes_transferred == 3

        # Next write exceeds quota
        with pytest.raises(PortQuotaExceededException):
            port.write_bytevector(Bytevector([4, 5]))

    def test_loopback_textual_port_content_isolation(self):
        port = make_loopback_textual_port(virtual_path="/virtual/test.txt")
        assert port.is_loopback is True
        port.write_string("hello alisp loopback\n")
        assert port.get_content() == "hello alisp loopback\n"


class TestSandboxDestructiveIOBlocked:
    """DoD: fs-cap を持たないコードから open-output-file の呼び出しが 100% 遮断されること。"""

    def test_open_output_file_blocked_without_capability(self, sandbox_dirs):
        allowed_dir, _ = sandbox_dirs
        test_file = os.path.join(allowed_dir, "unauthorized.txt")

        engine = ALispEngine(sandbox=True)
        code = f'(open-output-file "{test_file}")'

        with pytest.raises(AccessDeniedException) as exc_info:
            engine.eval(code)
        assert "FileSystemCapability (fs-cap) required" in str(exc_info.value)
        assert not os.path.exists(test_file)

    def test_open_input_file_blocked_without_capability(self, sandbox_dirs):
        allowed_dir, _ = sandbox_dirs
        test_file = os.path.join(allowed_dir, "test.txt")
        with open(test_file, "w") as f:
            f.write("content")

        engine = ALispEngine(sandbox=True)
        code = f'(open-input-file "{test_file}")'

        with pytest.raises(AccessDeniedException) as exc_info:
            engine.eval(code)
        assert "FileSystemCapability (fs-cap) required" in str(exc_info.value)

    def test_delete_file_blocked_without_capability(self, sandbox_dirs):
        allowed_dir, _ = sandbox_dirs
        test_file = os.path.join(allowed_dir, "delete_me.txt")
        with open(test_file, "w") as f:
            f.write("data")

        engine = ALispEngine(sandbox=True)
        code = f'(delete-file "{test_file}")'

        with pytest.raises(AccessDeniedException):
            engine.eval(code)
        assert os.path.exists(test_file)


class TestUnauthorizedWriteLoopbackIsolation:
    """DoD: 認可パス外へのファイル書き込みがメモリ内バッファへ隔離され、実ファイルシステムが一切変更されないこと。"""

    def test_unauthorized_write_redirected_to_in_memory_loopback(self, sandbox_dirs):
        allowed_dir, forbidden_dir = sandbox_dirs
        target_forbidden_file = os.path.join(forbidden_dir, "secret_compromised.txt")

        # fs-cap only grants write authority to allowed_dir, with loopback enabled
        fs_cap = FileSystemCapability(
            allowed_read_paths=[allowed_dir],
            allowed_write_paths=[allowed_dir],
            loopback_unauthorized_writes=True,
            byte_budget=1024 * 1024,
        )

        engine = ALispEngine(sandbox=True, initial_caps=[fs_cap])

        code = f"""
        (let ((p (open-output-file "{target_forbidden_file}")))
          (write-string "ATTACKER_DATA_HERE" p)
          (close-output-port p))
        """
        engine.eval(code)

        # CRITICAL DOD CHECK: Physical disk must NOT have been touched!
        assert not os.path.exists(target_forbidden_file)

        # Check that the port created was a loopback port and contained the written data
        assert len(fs_cap.created_ports) == 1
        created_port = fs_cap.created_ports[0]
        assert isinstance(created_port, ManagedTextualOutputPort)
        assert created_port.is_loopback is True
        assert created_port.get_content() == "ATTACKER_DATA_HERE"

    def test_authorized_write_modifies_disk(self, sandbox_dirs):
        allowed_dir, _ = sandbox_dirs
        target_allowed_file = os.path.join(allowed_dir, "valid_output.txt")

        fs_cap = FileSystemCapability(
            allowed_read_paths=[allowed_dir],
            allowed_write_paths=[allowed_dir],
            loopback_unauthorized_writes=True,
        )
        engine = ALispEngine(sandbox=True, initial_caps=[fs_cap])

        code = f"""
        (let ((p (open-output-file "{target_allowed_file}")))
          (write-string "LEGITIMATE_DATA" p)
          (close-output-port p))
        """
        engine.eval(code)

        # Authorized write must physically exist on disk
        assert os.path.exists(target_allowed_file)
        with open(target_allowed_file, "r") as f:
            assert f.read() == "LEGITIMATE_DATA"


class TestWithCapsMacro:
    """Test (with-caps (<bindings>...) <body>) macro syntax and dynamic scoping."""

    def test_with_caps_variable_binding(self, sandbox_dirs):
        allowed_dir, _ = sandbox_dirs
        target_file = os.path.join(allowed_dir, "caps_macro_test.txt")

        engine = ALispEngine(sandbox=True)
        code = f"""
        (with-caps ((fs (make-fs-cap "{allowed_dir}" "{allowed_dir}")))
          (let ((p (open-output-file "{target_file}")))
            (write-string "scoped capability write" p)
            (close-output-port p)))
        """
        engine.eval(code)

        assert os.path.exists(target_file)
        with open(target_file, "r") as f:
            assert f.read() == "scoped capability write"

        # After exiting with-caps, access is blocked again
        with pytest.raises(AccessDeniedException):
            engine.eval(f'(open-output-file "{target_file}")')


class TestTransactionRollback:
    """DoD: with-fuel 内で状態変更（set!）を行った後に意図的に Fuel 枯渇を起こした場合、

    すべての変数が実行前状態へ巻き戻ること。
    """

    def test_fuel_exhaustion_rolls_back_mutations(self):
        engine = ALispEngine()

        # Initialize variable x = 42, y = 100
        engine.eval("(define x 42)")
        engine.eval("(define y 100)")
        assert engine.eval("x") == 42
        assert engine.eval("y") == 100

        # In with-fuel, mutate x and y then enter infinite recursion to exhaust fuel
        code = """
        (with-fuel 80
          (set! x 9999)
          (set! y 8888)
          (letrec ((loop (lambda () (loop))))
            (loop)))
        """
        with pytest.raises(FuelExhaustedException):
            engine.eval(code)

        # CRITICAL DOD CHECK: x and y must be completely restored to 42 and 100!
        assert engine.eval("x") == 42
        assert engine.eval("y") == 100

    def test_normal_completion_preserves_mutations(self):
        engine = ALispEngine()
        engine.eval("(define counter 0)")

        code = """
        (with-fuel 1000
          (set! counter (+ counter 10))
          counter)
        """
        res = engine.eval(code)
        assert res == 10
        assert engine.eval("counter") == 10

    def test_multiple_mutations_rollback_to_original_state(self):
        engine = ALispEngine()
        engine.eval("(define state 5)")

        code = """
        (with-fuel 50
          (set! state 10)
          (set! state 20)
          (set! state 30)
          (letrec ((loop (lambda (n) (loop (+ n 1)))))
            (loop 0)))
        """
        with pytest.raises(FuelExhaustedException):
            engine.eval(code)

        # state must roll back to 5, not 10 or 20
        assert engine.eval("state") == 5


class TestTaintTracking:
    """Test TaintedValue creation, propagation, untaint sanitization, and sink leak prevention."""

    def test_taint_and_is_tainted(self):
        t = taint("user_input_from_web", source="web")
        assert is_tainted(t)
        assert t.source == "web"
        assert str(t) == "user_input_from_web"
        assert not is_tainted("plain_string")

    def test_taint_propagation_string_operations(self):
        t1 = taint("SELECT * FROM users WHERE ", source="external")
        t2 = t1 + "id = 1"
        assert is_tainted(t2)
        assert t2.source == "external"
        assert str(t2) == "SELECT * FROM users WHERE id = 1"

    def test_untaint_success(self):
        engine = ALispEngine()
        engine.eval('(define is-safe? (lambda (s) (equal? s "valid_data")))')
        engine.eval('(define secret (taint "valid_data" "user"))')

        res = engine.eval("(untaint secret is-safe?)")
        assert res == "valid_data"
        assert not is_tainted(res)

    def test_untaint_failure_raises_exception(self):
        engine = ALispEngine()
        engine.eval("(define is-number-string? (lambda (s) #f))")
        engine.eval('(define dirty (taint "DROP TABLE users;" "prompt_injection"))')

        with pytest.raises(AccessDeniedException) as exc_info:
            engine.eval("(untaint dirty is-number-string?)")
        assert "Untaint verification failed" in str(exc_info.value)

    def test_network_sink_blocks_tainted_data_exfiltration(self):
        net_cap = NetworkCapability(
            allowed_hosts=["arxiv.org"],
            allowed_methods=["GET", "POST"],
        )
        tainted_token = taint("SUPER_SECRET_TOKEN_ABC123", source="api_keys")

        with pytest.raises(TaintLeakViolationException) as exc_info:
            net_cap.check_request(
                url="https://arxiv.org/api",
                method="POST",
                data=tainted_token,
            )
        assert "Tainted value from source 'api_keys' leaked" in str(exc_info.value)

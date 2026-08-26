"""Unit tests for SupervisorConfig validation and serialization."""

import pytest

from supervisor.config import SupervisorConfig


def test_supervisor_config_defaults() -> None:
    cfg = SupervisorConfig()
    assert cfg.bind_host == "0.0.0.0"
    assert cfg.bind_port == 8000
    assert cfg.workers == 2
    assert cfg.worker_class == "sync"
    assert cfg.timeout == 30.0
    assert len(cfg.pools) == 1
    assert cfg.pools[0].name == "default"


def test_supervisor_config_custom_valid() -> None:
    cfg = SupervisorConfig(
        bind_host="127.0.0.1",
        bind_port=9000,
        workers=4,
        worker_class="gthread",
        threads=8,
        timeout=15.0,
    )
    assert cfg.bind_host == "127.0.0.1"
    assert cfg.bind_port == 9000
    assert cfg.workers == 4
    assert cfg.worker_class == "gthread"
    assert cfg.threads == 8


def test_supervisor_config_validation_errors() -> None:
    with pytest.raises(ValueError, match="Invalid bind_port"):
        SupervisorConfig(bind_port=70000)

    with pytest.raises(ValueError, match="worker count must be >= 1"):
        SupervisorConfig(workers=0)

    with pytest.raises(ValueError, match="Invalid worker_class"):
        SupervisorConfig(worker_class="invalid_worker")

    with pytest.raises(ValueError, match="Thread count must be at least 1"):
        SupervisorConfig(threads=0)

    with pytest.raises(ValueError, match="Timeout must be positive"):
        SupervisorConfig(timeout=-5.0)

    with pytest.raises(ValueError, match="Graceful timeout must be positive"):
        SupervisorConfig(graceful_timeout=0.0)


def test_supervisor_config_dict_roundtrip() -> None:
    data = {
        "bind_host": "0.0.0.0",
        "bind_port": 8080,
        "workers": 3,
        "worker_class": "async",
        "timeout": 20.0,
    }
    cfg = SupervisorConfig.from_dict(data)
    assert cfg.bind_port == 8080
    assert cfg.worker_class == "async"
    d = cfg.to_dict()
    assert d["bind_port"] == 8080
    assert d["worker_class"] == "async"


def test_supervisor_config_bind_alias() -> None:
    data = {"bind": "127.0.0.1:9090", "workers": 2}
    cfg = SupervisorConfig.from_dict(data)
    assert cfg.bind_host == "127.0.0.1"
    assert cfg.bind_port == 9090

    data2 = {"bind": 9091}
    cfg2 = SupervisorConfig.from_dict(data2)
    assert cfg2.bind_port == 9091


def test_supervisor_config_from_file_json(tmp_path) -> None:
    json_file = tmp_path / "supervisor.json"
    json_file.write_text(
        '{"bind_host": "127.0.0.1", "bind_port": 8888, "workers": 4, "worker_class": "gthread", "threads": 2}',
        encoding="utf-8",
    )

    cfg = SupervisorConfig.from_file(str(json_file))
    assert cfg.bind_host == "127.0.0.1"
    assert cfg.bind_port == 8888
    assert cfg.workers == 4
    assert cfg.worker_class == "gthread"
    assert cfg.threads == 2


def test_supervisor_config_from_file_toml(tmp_path) -> None:
    toml_file = tmp_path / "supervisor.toml"
    toml_file.write_text(
        'bind_host = "0.0.0.0"\nbind_port = 8889\nworkers = 3\nworker_class = "async"\n',
        encoding="utf-8",
    )

    cfg = SupervisorConfig.from_file(str(toml_file))
    assert cfg.bind_port == 8889
    assert cfg.workers == 3
    assert cfg.worker_class == "async"


def test_supervisor_config_from_file_python(tmp_path) -> None:
    py_file = tmp_path / "supervisor_conf.py"
    py_file.write_text(
        'bind = "127.0.0.1:9999"\nworkers = 5\nworker_class = "gthread"\nthreads = 4\n',
        encoding="utf-8",
    )

    cfg = SupervisorConfig.from_file(str(py_file))
    assert cfg.bind_host == "127.0.0.1"
    assert cfg.bind_port == 9999
    assert cfg.workers == 5
    assert cfg.worker_class == "gthread"
    assert cfg.threads == 4


def test_supervisor_config_from_file_not_found() -> None:
    with pytest.raises(FileNotFoundError):
        SupervisorConfig.from_file("/non/existent/path/supervisor.json")


def test_supervisor_config_auto_discover(tmp_path) -> None:
    # No config present
    assert SupervisorConfig.auto_discover(str(tmp_path)) is None

    # Write supervisor.conf.py
    py_conf = tmp_path / "supervisor.conf.py"
    py_conf.write_text('bind = "0.0.0.0:7777"\nworkers = 6\n', encoding="utf-8")

    cfg = SupervisorConfig.auto_discover(str(tmp_path))
    assert cfg is not None
    assert cfg.bind_port == 7777
    assert cfg.workers == 6


def test_supervisor_config_daemon_defaults() -> None:
    cfg = SupervisorConfig(daemon=True)
    assert cfg.daemon is True
    assert cfg.log_file is not None
    assert cfg.log_file.endswith("supervisor.log")
    assert cfg.pid_file is not None
    assert cfg.pid_file.endswith("arbiter.pid")


def test_supervisor_config_daemon_custom_paths() -> None:
    cfg = SupervisorConfig(
        daemon=True,
        log_file="/tmp/custom_supervisor.log",
        pid_file="/tmp/custom_supervisor.pid",
    )
    assert cfg.daemon is True
    assert cfg.log_file == "/tmp/custom_supervisor.log"
    assert cfg.pid_file == "/tmp/custom_supervisor.pid"

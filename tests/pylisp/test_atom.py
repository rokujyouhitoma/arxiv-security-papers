"""tests.pylisp.test_atom: pylisp.atom の包括的テストスイート (DSN-29)."""

import concurrent.futures
import threading
import time

import pytest

from pylisp.atom import Atom


def test_atom_initialization_and_repr() -> None:
    """Atomの初期化、derefプロパティ、および文字列表現を検証."""
    atom: Atom[int] = Atom(42)
    assert atom.deref == 42
    assert repr(atom) == "<Atom: 42>"


def test_atom_reset() -> None:
    """Atomのresetによる値の不可分上書きを検証."""
    atom: Atom[str] = Atom("initial")
    old_or_new = atom.reset("updated")
    assert old_or_new == "updated"
    assert atom.deref == "updated"
    assert repr(atom) == "<Atom: updated>"


def test_atom_swap_basic() -> None:
    """Atomのswapによる純粋関数適用の状態遷移を検証."""
    atom: Atom[int] = Atom(10)
    res = atom.swap(lambda x: x * 2)
    assert res == 20
    assert atom.deref == 20


def test_atom_swap_args_kwargs() -> None:
    """Atomのswapにおいて位置引数およびキーワード引数が正しく適用されることを検証."""
    atom: Atom[str] = Atom("hello")

    def append_text(current: str, suffix: str, prefix: str = "") -> str:
        return f"{prefix}{current}{suffix}"

    res = atom.swap(append_text, " world", prefix="[")
    assert res == "[hello world"
    assert atom.deref == "[hello world"


def test_atom_swap_exception_rollback() -> None:
    """swap関数内で例外が発生した場合、状態が破損せず元の値を維持することを検証."""
    atom: Atom[dict[str, int]] = Atom({"a": 1, "b": 2})

    def faulty_mutator(state: dict[str, int]) -> dict[str, int]:
        # 途中まで計算した後に意図的に例外を送出
        raise RuntimeError("computation failed")

    with pytest.raises(RuntimeError, match="computation failed"):
        atom.swap(faulty_mutator)

    assert atom.deref == {"a": 1, "b": 2}


def test_atom_concurrent_swap_no_lost_updates() -> None:
    """マルチスレッド高競合下での並行swapにおいて、更新喪失 (Lost Update) が生じないことを検証."""
    num_threads = 50
    increments_per_thread = 1_000
    expected_total = num_threads * increments_per_thread

    counter: Atom[int] = Atom(0)

    def worker() -> None:
        for _ in range(increments_per_thread):
            counter.swap(lambda n: n + 1)

    with concurrent.futures.ThreadPoolExecutor(max_workers=num_threads) as executor:
        futures = [executor.submit(worker) for _ in range(num_threads)]
        for f in concurrent.futures.as_completed(futures):
            f.result()

    assert counter.deref == expected_total


def test_atom_concurrent_deref_and_swap_consistency() -> None:
    """並行してderefとswapを実行した際、読み取り値が単調増加し破綻しないことを検証."""
    counter: Atom[int] = Atom(0)
    stop_event = threading.Event()
    read_values: list[int] = []

    def writer() -> None:
        while not stop_event.is_set():
            counter.swap(lambda n: n + 1)
            time.sleep(0.0001)

    def reader() -> None:
        last = -1
        while not stop_event.is_set():
            val = counter.deref
            assert val >= last, "Torn read or out-of-order state observation detected!"
            last = val
            read_values.append(val)
            time.sleep(0.0001)

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        writer_futures = [executor.submit(writer) for _ in range(2)]
        reader_futures = [executor.submit(reader) for _ in range(2)]

        time.sleep(0.1)  # 100ms 実行
        stop_event.set()

        for f in writer_futures + reader_futures:
            f.result()

    assert len(read_values) > 0
    assert counter.deref > 0

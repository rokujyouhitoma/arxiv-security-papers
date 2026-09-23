"""tests.pylisp.test_dynvar: pylisp.dynvar の包括的テストスイート (DSN-29)."""

import asyncio
from typing import AsyncGenerator, Generator

import pytest

from pylisp.dynvar import DynamicVar, dynamic_bind


def test_dynamic_var_default_and_repr() -> None:
    """DynamicVarのデフォルト値およびrepr文字列表現を検証."""
    var: DynamicVar[int] = DynamicVar("counter", 0)
    assert var.name == "counter"
    assert var.value == 0
    assert repr(var) == "*dyn_counter*=0"


def test_dynamic_bind_basic_scoping() -> None:
    """dynamic_bindによるスコープ限定束縛と自動巻き戻しを検証."""
    var: DynamicVar[str] = DynamicVar("env", "production")
    assert var.value == "production"

    with dynamic_bind({var: "staging"}):
        assert var.value == "staging"
        assert repr(var) == "*dyn_env*=staging"

    assert var.value == "production"


def test_dynamic_bind_multiple_variables() -> None:
    """複数変数を同時に束縛・復元できることを検証."""
    var_a: DynamicVar[int] = DynamicVar("a", 1)
    var_b: DynamicVar[str] = DynamicVar("b", "init")

    with dynamic_bind({var_a: 100, var_b: "updated"}):
        assert var_a.value == 100
        assert var_b.value == "updated"

    assert var_a.value == 1
    assert var_b.value == "init"


def test_dynamic_bind_nested_scoping() -> None:
    """ネストした動的束縛の多段スコープ解決と段階的復元を検証."""
    var: DynamicVar[int] = DynamicVar("depth", 0)

    with dynamic_bind({var: 1}):
        assert var.value == 1
        with dynamic_bind({var: 2}):
            assert var.value == 2
            with dynamic_bind({var: 3}):
                assert var.value == 3
            assert var.value == 2
        assert var.value == 1

    assert var.value == 0


def test_dynamic_bind_exception_rollback() -> None:
    """コンテキスト内で例外が発生した場合でも元の値へ確実に復元されることを検証."""
    var: DynamicVar[str] = DynamicVar("status", "safe")

    with pytest.raises(ValueError, match="intended failure"):
        with dynamic_bind({var: "tainted"}):
            assert var.value == "tainted"
            raise ValueError("intended failure")

    assert var.value == "safe"


def test_dynamic_bind_asyncio_isolation() -> None:
    """asyncioの並行タスク間で動的変数が相互汚染せず分離されていることを検証."""
    request_id: DynamicVar[str] = DynamicVar("request_id", "default_req")

    async def task_worker(task_id: str, delay: float) -> str:
        with dynamic_bind({request_id: task_id}):
            await asyncio.sleep(delay)
            res = request_id.value
        return res

    async def main() -> tuple[str, str]:
        return await asyncio.gather(
            task_worker("REQ-A", 0.02),
            task_worker("REQ-B", 0.01),
        )

    res_a, res_b = asyncio.run(main())
    assert res_a == "REQ-A"
    assert res_b == "REQ-B"
    assert request_id.value == "default_req"


def test_generator_leakage_guard_sync() -> None:
    """同期ジェネレータ内部での dynamic_bind 使用が RuntimeError で遮断されることを検証."""
    var: DynamicVar[int] = DynamicVar("gen_val", 0)

    def invalid_generator() -> Generator[int, None, None]:
        with dynamic_bind({var: 42}):
            yield 1

    gen = invalid_generator()
    with pytest.raises(
        RuntimeError,
        match="dynamic_bind cannot be safely used directly inside a generator",
    ):
        next(gen)

    # ガードにより値が汚染されていないこと
    assert var.value == 0


def test_generator_leakage_guard_async() -> None:
    """非同期ジェネレータ内部での dynamic_bind 使用が RuntimeError で遮断されることを検証."""
    var: DynamicVar[str] = DynamicVar("async_gen_val", "clean")

    async def invalid_async_generator() -> AsyncGenerator[str, None]:
        with dynamic_bind({var: "dirty"}):
            yield "value"

    async def run_async_test() -> None:
        agen = invalid_async_generator()
        with pytest.raises(
            RuntimeError,
            match="dynamic_bind cannot be safely used directly inside a generator",
        ):
            await anext(agen)

    asyncio.run(run_async_test())
    assert var.value == "clean"


def test_generator_safe_external_usage() -> None:
    """ジェネレータ呼び出しの外側で dynamic_bind を使う場合は正常に値が伝播することを検証."""
    var: DynamicVar[str] = DynamicVar("caller_context", "root")

    def producer() -> Generator[str, None, None]:
        # ジェネレータ関数内部では dynamic_bind を呼ばず、外部の動的変数を参照
        yield f"item_with_{var.value}"

    with dynamic_bind({var: "scoped"}):
        items = list(producer())
        assert items == ["item_with_scoped"]

    assert var.value == "root"

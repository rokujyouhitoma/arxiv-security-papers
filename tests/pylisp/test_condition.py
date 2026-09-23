"""tests.pylisp.test_condition: pylisp.condition の包括的テストスイート (DSN-29)."""

import asyncio

import pytest

from pylisp.condition import (
    Condition,
    ConditionController,
    Restart,
    handler_bind,
    safe_create_task,
    signal,
)


class InvalidFieldCondition(Condition):
    """テスト用: 不正なフィールド値を表すコンディション."""

    def __init__(self, raw_val: str) -> None:
        super().__init__(f"Invalid field value: {raw_val}")
        self.raw_val: str = raw_val


class NetworkTimeoutCondition(Condition):
    """テスト用: ネットワークタイムアウトを表すコンディション."""

    pass


def parse_field(raw_val: str) -> str:
    """現場復帰プロトコル（非巻き戻し）を用いたパーサー."""
    if not raw_val.isalnum():
        raw_val = signal(
            InvalidFieldCondition(raw_val),
            restarts=[
                Restart("use_default", lambda: "DEFAULT", "デフォルト値を採用"),
                Restart(
                    "correct_value", lambda v: v, "指定された値で補正", takes_arg=True
                ),
            ],
        )

    # 現場フレームを保持したまま後続の変換処理を最後まで完遂
    return raw_val.strip().lower()


def test_condition_basic_signaling_and_return() -> None:
    """現場復帰プロトコルにより、スタックを解体せず後続処理が完遂することを検証."""
    with handler_bind(
        {InvalidFieldCondition: lambda ctrl: ctrl.invoke_restart("use_default")}
    ):
        result = parse_field("###CORRUPTED###")

    assert result == "default"


def test_condition_compute_restarts_inspection() -> None:
    """上位ハンドラが compute_restarts() で現場のリスタートを内省・選択できることを検証."""
    inspected_names: list[str] = []

    def introspecting_handler(ctrl: ConditionController) -> None:
        restarts = ctrl.compute_restarts()
        for r in restarts:
            inspected_names.append(r.name)
        ctrl.invoke_restart("use_default")

    with handler_bind({InvalidFieldCondition: introspecting_handler}):
        result = parse_field("$$$BAD$$$")

    assert result == "default"
    assert "use_default" in inspected_names
    assert "correct_value" in inspected_names


def test_condition_restart_with_args() -> None:
    """リスタート呼び出し時に引数を安全に渡して現場を補正できることを検証."""
    with handler_bind(
        {
            InvalidFieldCondition: lambda ctrl: ctrl.invoke_restart(
                "correct_value", "REPAIRED"
            )
        }
    ):
        result = parse_field("@@@INVALID@@@")

    assert result == "repaired"


def test_condition_unhandled_raises_exception() -> None:
    """ハンドラ未登録時に通常の例外としてスタック解体へフォールバックすることを検証."""
    with pytest.raises(InvalidFieldCondition) as exc_info:
        parse_field("!!!FAIL!!!")

    assert exc_info.value.raw_val == "!!!FAIL!!!"


def test_condition_uninvoked_restart_raises_exception() -> None:
    """ハンドラが実行されても invoke_restart が呼ばれなかった場合は通常例外送出となることを検証."""

    def passive_handler(ctrl: ConditionController) -> None:
        # 何も修復戦略を選択しない
        pass

    with pytest.raises(InvalidFieldCondition):
        with handler_bind({InvalidFieldCondition: passive_handler}):
            parse_field("???UNKNOWN???")


def test_condition_invalid_restart_name_raises_keyerror() -> None:
    """存在しないリスタート名を指定した際に KeyError が送出されることを検証."""
    with pytest.raises(KeyError, match="Restart 'non_existent' is not registered"):
        with handler_bind(
            {InvalidFieldCondition: lambda ctrl: ctrl.invoke_restart("non_existent")}
        ):
            parse_field("###CORRUPTED###")


def test_condition_nested_handler_inheritance() -> None:
    """ネストした handler_bind において親のハンドラが維持・上書きされることを検証."""

    def outer_network_handler(ctrl: ConditionController) -> None:
        ctrl.invoke_restart("fallback_net")

    def inner_field_handler(ctrl: ConditionController) -> None:
        ctrl.invoke_restart("use_default")

    def run_nested() -> tuple[str, str]:
        with handler_bind({NetworkTimeoutCondition: outer_network_handler}):
            with handler_bind({InvalidFieldCondition: inner_field_handler}):
                # 1. 内部で登録されたハンドラが動く
                res_field = parse_field("###CORRUPTED###")
                # 2. 親で登録されたハンドラも維持されている
                res_net = signal(
                    NetworkTimeoutCondition("timeout"),
                    restarts=[Restart("fallback_net", lambda: "OFFLINE_CACHE")],
                )
                return res_field, res_net

    f_res, n_res = run_nested()
    assert f_res == "default"
    assert n_res == "OFFLINE_CACHE"


def test_condition_safe_create_task_asyncio() -> None:
    """safe_create_task により非同期タスク境界を越えてコンディションハンドラが伝播することを検証."""

    async def async_worker() -> str:
        # 別タスクとして非同期実行される現場
        return parse_field("###CORRUPTED_ASYNC###")

    async def main() -> str:
        with handler_bind(
            {InvalidFieldCondition: lambda ctrl: ctrl.invoke_restart("use_default")}
        ):
            task = safe_create_task(async_worker())
            return await task

    result = asyncio.run(main())
    assert result == "default"

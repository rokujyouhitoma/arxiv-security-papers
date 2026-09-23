"""pylisp.condition: 現場復帰・非巻き戻し型コンディション機構 (DSN-29 Phase 1).

Common Lispのコンディションシステムに倣い、スタックフレームを破棄せず現場の中間状態を
維持したまま上位ハンドラに修復戦略（Restart）を問い合わせ、現場へ復帰して計算を継続する。
"""

from __future__ import annotations

import asyncio
import contextvars
import sys
from typing import Any, Callable, Coroutine, Literal, Optional, TypeVar

T = TypeVar("T")


class Restart:
    """シグナル現場で提供される修復戦略."""

    __slots__ = ("name", "callback", "description", "takes_arg")

    def __init__(
        self,
        name: str,
        callback: Callable[..., Any],
        description: str = "",
        takes_arg: bool = False,
    ) -> None:
        """修復戦略を初期化する.

        Args:
            name: リスタート名
            callback: 適用時に実行される復帰用コールバック関数
            description: 修復戦略の説明文
            takes_arg: コールバックが引数を要求するかどうかのフラグ
        """
        self.name: str = name
        self.callback: Callable[..., Any] = callback
        self.description: str = description
        self.takes_arg: bool = takes_arg

    def __repr__(self) -> str:
        """リスタートの文字列表現を返却する."""
        return f"<Restart '{self.name}': {self.description}>"


class Condition(Exception):
    """すべてのシグナル可能なコンディションの基底クラス."""

    pass


class ConditionController:
    """上位ハンドラが現場のリスタートを内省・選択するためのコントローラ."""

    __slots__ = (
        "condition",
        "restarts",
        "invoked_restart",
        "restart_args",
        "restart_kwargs",
    )

    def __init__(self, condition: Condition, restarts: list[Restart]) -> None:
        """コントローラを初期化する.

        Args:
            condition: 発生したコンディション
            restarts: 現場で利用可能なリスタート一覧
        """
        self.condition: Condition = condition
        self.restarts: dict[str, Restart] = {r.name: r for r in restarts}
        self.invoked_restart: Optional[Restart] = None
        self.restart_args: tuple[Any, ...] = ()
        self.restart_kwargs: dict[str, Any] = {}

    def compute_restarts(self) -> list[Restart]:
        """現在利用可能なリスタートの一覧を返却する（Common Lispの compute-restarts 相当）."""
        return list(self.restarts.values())

    def invoke_restart(self, name: str, *args: Any, **kwargs: Any) -> None:
        """指定された名前のリスタートを選択・呼び出すよう登録する.

        Args:
            name: 選択するリスタート名
            *args: リスタートコールバックに渡す位置引数
            **kwargs: リスタートコールバックに渡すキーワード引数

        Raises:
            KeyError: 現場で登録されていないリスタート名を指定した場合
        """
        if name not in self.restarts:
            raise KeyError(f"Restart '{name}' is not registered at signaling site.")
        self.invoked_restart = self.restarts[name]
        self.restart_args = args
        self.restart_kwargs = kwargs


class ConditionContext:
    """現在の階層におけるコンディションハンドラを管理するコンテキスト."""

    __slots__ = ("handlers",)

    def __init__(self) -> None:
        """ハンドラマップを初期化する."""
        self.handlers: dict[type[Condition], Callable[[ConditionController], None]] = {}


_current_context: contextvars.ContextVar[Optional[ConditionContext]] = (
    contextvars.ContextVar("pylisp_condition_ctx", default=None)
)


class handler_bind:
    """上位でコンディションに対する修復ポリシーを登録するコンテキストマネージャ."""

    __slots__ = ("mapping", "token")

    def __init__(
        self, mapping: dict[type[Condition], Callable[[ConditionController], None]]
    ) -> None:
        """ハンドラバインディングを初期化する.

        Args:
            mapping: コンディション型とハンドラ関数のマッピング
        """
        self.mapping: dict[type[Condition], Callable[[ConditionController], None]] = (
            mapping
        )
        self.token: Optional[contextvars.Token[Optional[ConditionContext]]] = None

    def __enter__(self) -> handler_bind:
        """コンテキストに入り、親のハンドラを継承しつつ新しいハンドラを追加する."""
        ctx = ConditionContext()
        parent = _current_context.get()
        if parent is not None:
            ctx.handlers.update(parent.handlers)
        ctx.handlers.update(self.mapping)
        self.token = _current_context.set(ctx)
        return self

    def __exit__(
        self,
        exc_type: Optional[type[BaseException]],
        exc_val: Optional[BaseException],
        exc_tb: Optional[Any],
    ) -> Literal[False]:
        """コンテキストを脱出し、トークンを確実に復元する."""
        if self.token is not None:
            _current_context.reset(self.token)
        return False


def signal(condition: Condition, restarts: list[Restart]) -> Any:
    """シグナル地点から直接ハンドラを逆探索する.

    スタックを巻き戻さず、ハンドラが選択したリスタートの実行結果を現場へ「値」として返却する。
    現場コードはこの戻り値を受け取り、以降の処理を継続する。
    ハンドラ不在時、またはリスタート未選択時は通常の例外として送出（スタック解体フォールバック）する。

    Args:
        condition: 送出するコンディション
        restarts: 現場で提供可能な修復戦略一覧

    Returns:
        選択されたリスタートの実行結果

    Raises:
        Condition: ハンドラ不在時、またはハンドラ内でリスタートが選択されなかった場合
    """
    ctx = _current_context.get()
    if ctx is None:
        raise condition

    ctrl = ConditionController(condition, restarts)

    for cond_type, handler in ctx.handlers.items():
        if isinstance(condition, cond_type):
            handler(ctrl)
            if ctrl.invoked_restart is not None:
                return ctrl.invoked_restart.callback(
                    *ctrl.restart_args, **ctrl.restart_kwargs
                )

    raise condition


def safe_create_task(coro: Coroutine[Any, Any, T]) -> asyncio.Task[T]:
    """現在のコンテキストを確実に引き継いで非同期タスクを生成する.

    Python 3.11以降では context= 引数を使用し、3.10以前では ctx.run でラップする。

    Args:
        coro: 実行するコルーチン

    Returns:
        生成された asyncio.Task
    """
    ctx = contextvars.copy_context()
    if sys.version_info >= (3, 11):
        return asyncio.create_task(coro, context=ctx)

    async def _runner() -> T:
        return await coro

    return asyncio.create_task(ctx.run(_runner))

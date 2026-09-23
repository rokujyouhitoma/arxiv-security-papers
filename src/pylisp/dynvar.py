"""pylisp.dynvar: 非同期セーフ動的スコープ基盤 (DSN-29 Phase 0).

Common Lispの *special-variables* および Clojureの binding に倣い、
呼び出し階層深さ方向へのみ影響する非同期セーフな動的束縛を提供する。
ジェネレータ内でのイテレーション途中破棄に伴うコンテキスト値の永続漏洩を防ぐため、
呼び出し元スタックフレームの CO_GENERATOR / CO_ASYNC_GENERATOR フラグを検査・遮断する。
"""

from __future__ import annotations

import inspect
from contextvars import ContextVar, Token
from typing import Any, Generic, Literal, Optional, TypeVar

T = TypeVar("T")

# Pythonバイトコードのコードオブジェクトフラグ定数
CO_GENERATOR: int = 0x20
CO_ASYNC_GENERATOR: int = 0x200


class DynamicVar(Generic[T]):
    """動的変数の定義（Common Lispの *special-variable* に相当）.

    各スレッド・各非同期タスクローカルなコンテキスト（ContextVar）として管理される。
    """

    __slots__ = ("name", "_cv")

    def __init__(self, name: str, default: T) -> None:
        """動的変数を初期化する.

        Args:
            name: 変数識別名
            default: スコープ外でのデフォルト値
        """
        self.name: str = name
        self._cv: ContextVar[T] = ContextVar(f"*dyn_{name}*", default=default)

    @property
    def value(self) -> T:
        """現在のコンテキストにおける束縛値を取得する."""
        return self._cv.get()

    def __repr__(self) -> str:
        """変数の文字列表現を返却する."""
        return f"*dyn_{self.name}*={self.value}"


class dynamic_bind:
    """複数の動的変数をスコープ限定で一括束縛するコンテキストマネージャ.

    ジェネレータ・非同期ジェネレータ内での使用を検知した場合は RuntimeError を送出し、
    イテレータの途中放棄によるコンテキスト汚染を未然に防止する。
    """

    __slots__ = ("bindings", "tokens", "_active")

    def __init__(self, bindings: dict[DynamicVar[Any], Any]) -> None:
        """動的束縛コンテキストを初期化する.

        Args:
            bindings: 動的変数と設定値の辞書
        """
        self.bindings: dict[DynamicVar[Any], Any] = bindings
        self.tokens: list[tuple[DynamicVar[Any], Token[Any]]] = []
        self._active: bool = False

    def __enter__(self) -> dynamic_bind:
        """コンテキストに入り、動的変数を新しい値で束縛する.

        Raises:
            RuntimeError: ジェネレータまたは非同期ジェネレータ内部で呼び出された場合
        """
        caller_frame = inspect.currentframe()
        if caller_frame is not None and caller_frame.f_back is not None:
            flags = caller_frame.f_back.f_code.co_flags
            if flags & (CO_GENERATOR | CO_ASYNC_GENERATOR):
                raise RuntimeError(
                    "dynamic_bind cannot be safely used directly inside a generator / async generator. "
                    "Context cleanup is not guaranteed if iteration is abandoned."
                )

        for var, val in self.bindings.items():
            token = var._cv.set(val)
            self.tokens.append((var, token))
        self._active = True
        return self

    def __exit__(
        self,
        exc_type: Optional[type[BaseException]],
        exc_val: Optional[BaseException],
        exc_tb: Optional[Any],
    ) -> Literal[False]:
        """コンテキストを脱出し、束縛を元の値へ確実に巻き戻す."""
        if self._active:
            for var, token in reversed(self.tokens):
                var._cv.reset(token)
            self._active = False
        return False

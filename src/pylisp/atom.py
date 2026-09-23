"""pylisp.atom: Free-threaded対応アトミック状態同期コンテナ (DSN-29 Phase 0).

Clojureの atom 設計に倣い、不変データ構造と純粋関数を組み合わせて
不可分な状態遷移（Compare-And-Swap / Lock Synchronized Transition）を提供する。
CPython 3.13+/3.14+ (Free-threaded / No-GIL) 環境下でのキャッシュ不整合や Torn Read を防ぐため、
状態更新時のみならず参照時 (deref) を含む全アクセス経路でミューテックスロックを取得する。
"""

from __future__ import annotations

import threading
from typing import Any, Callable, Generic, TypeVar

T = TypeVar("T")


class Atom(Generic[T]):
    """不変データ構造を安全に管理するためのアトミック参照コンテナ.

    Free-threaded Python (No-GIL) 環境下でもメモリ可視性と整合性を保証する。
    """

    __slots__ = ("_state", "_lock")

    def __init__(self, initial_state: T) -> None:
        """アトミックコンテナを初期化する.

        Args:
            initial_state: 初期の不変状態
        """
        self._state: T = initial_state
        self._lock: threading.Lock = threading.Lock()

    @property
    def deref(self) -> T:
        """現在の不変状態を安全に読み取る（Free-threaded対応: ロック必須）."""
        with self._lock:
            return self._state

    def reset(self, new_val: T) -> T:
        """状態をアトミックに新しい値で上書きする.

        Args:
            new_val: 上書きする新しい値

        Returns:
            上書き後の新しい状態
        """
        with self._lock:
            self._state = new_val
            return self._state

    def swap(self, fn: Callable[..., T], *args: Any, **kwargs: Any) -> T:
        """純粋関数 fn を適用して不可分に状態を更新する.

        関数の評価成功後にのみ状態を更新するため、関数内部で例外が発生した場合は
        元の状態が完全に保護・維持される。

        Args:
            fn: 現在の状態を受け取り新しい状態を返す純粋関数
                fn(current_state, *args, **kwargs) -> new_state
            *args: fn に渡す位置引数
            **kwargs: fn に渡すキーワード引数

        Returns:
            更新後の新しい状態
        """
        with self._lock:
            new_state = fn(self._state, *args, **kwargs)
            self._state = new_state
            return self._state

    def __repr__(self) -> str:
        """アトミックコンテナの文字列表現をスレッドセーフに返却する."""
        with self._lock:
            return f"<Atom: {self._state}>"

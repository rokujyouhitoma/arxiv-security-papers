---
ID: 391
種別: Feature
優先度: Medium
ステータス: Closed
完了日: 2026-09-24
---

# [FEAT/ENH] pylisp.condition 現場復帰・非巻き戻し型コンディション機構の実装 (ID: 391)

## 1. 概要 / Summary
Common Lispのコンディションシステム（Condition System）に倣い、スタックフレームを即座に破棄（スタックアンワインド）せずに例外発生現場の中間計算状態やローカル変数を保持したまま、上位ハンドラに修復戦略（Restart）を問い合わせ、現場へ復帰して計算を継続する非巻き戻し型エラー処理基盤を実装する。

従来のPython例外機構（`try-except` / `raise`）は、例外発生時にスタックフレームを不可逆的に破棄してしまうため、現場に保持されていたローカル変数、中間計算結果、開いていたネットワーク接続コンテキストなどが失われる。

本モジュールでは、現場コードが `val = signal(condition, restarts)` で修復値を受け取り、スタックを破棄せず後続の処理ステップを完遂する呼び出し規約を義務付ける。さらに、上位ハンドラが現場で提供された修復戦略を動的に内省・選択できる `compute_restarts()` API、および `asyncio` タスク越境時にコンテキストが暗黙的に分断されるのを防ぐ安全な非同期タスク生成ラッパー `safe_create_task` を提供する。

---

## 2. トレーサビリティ / Traceability
- **設計書**: [DSN-29 Python-LISP 統合アーキテクチャ設計仕様書 第4章・第8.3節・第9章](../designs/DSN-29-python_lisp_integrated_architecture_specification.md#4-pylispcondition-現場復帰非巻き戻し型コンディション機構-条件付き自作採用)
- **関連標準**: Common Lisp Condition System (ANSI Common Lisp / Kent Pitman), PEP 567 (Context Variables)
- **関連エージェント**: Systems Architect (SA), Software Development (SWD), Information Security Specialist (SEC), Software Quality Assurance (QA)

---

## 3. セキュリティ脅威分析とガード設計 / Threat Analysis & Security Mitigations
### 3.1 脅威シナリオ
1. **未処理エラーの暗黙的握りつぶし (Silent Error Swallowing / CWE-390)**:
   - ハンドラがリスタートを選択しなかった場合や、ハンドラが設定されていない場合に `signal` が `None` 等を返却してしまうと、エラーが握りつぶされ後続処理が不正な状態で暴走する。
2. **非同期タスク越境における修復コンテキストの暗黙的消失 (Context Partitioning / CWE-662)**:
   - `asyncio.create_task` や `to_thread` で別タスク・別スレッドに処理をオフロードした際、上位でバインドした `handler_bind` のコンテキストが伝播せず、現場でハンドラ不在例外となる。
3. **コンテキスト汚染とスコープ漏洩 (Context Leakage / CWE-404)**:
   - `handler_bind` 脱出時にコンテキストトークンが確実にリセットされない場合、上位リクエストの修復ハンドラが後続の無関係なタスクに残留・誤適用される。

### 3.2 緩和策と技術ガード
- **厳格なフォールバック機構**: ハンドラが存在しない、またはハンドラがどの `invoke_restart` も呼び出さなかった場合は、必ず標準の例外送出（`raise condition`）を行い、通常のスタック解体へ安全にフォールバックする。
- **安全な非同期タスク生成ラッパー**: `safe_create_task` を標準提供し、`contextvars.copy_context()` を引き継いでタスク境界越えのコンテキスト保護を保証。
- **`Token` による完全復元**: `handler_bind.__exit__` において、`_current_context.reset(token)` を確実に実行。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [docs/issues/391-implement-pylisp-condition-restarts-mechanism.md](391-implement-pylisp-condition-restarts-mechanism.md) (本Issue仕様書)
- [x] [src/pylisp/__init__.py](../../src/pylisp/__init__.py) (`Condition`, `Restart`, `ConditionController`, `handler_bind`, `signal`, `safe_create_task` のパブリックエクスポート追加)
- [x] [src/pylisp/condition.py](../../src/pylisp/condition.py) (コンディション・リスタート基盤の実装)
- [x] [tests/pylisp/test_condition.py](../../tests/pylisp/test_condition.py) (単体・現場復帰・非同期伝播テスト)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/391-implement-pylisp-condition-restarts-mechanism`

### 5.1 モジュール設計 (`src/pylisp/condition.py`)
```python
from __future__ import annotations

import asyncio
import contextvars
import sys
from typing import Any, Callable, Coroutine, Literal, Optional

class Restart:
    """シグナル現場で提供される修復戦略."""
    __slots__ = ("name", "callback", "description", "takes_arg")

    def __init__(self, name: str, callback: Callable[..., Any], description: str = "", takes_arg: bool = False) -> None:
        self.name: str = name
        self.callback: Callable[..., Any] = callback
        self.description: str = description
        self.takes_arg: bool = takes_arg

    def __repr__(self) -> str:
        return f"<Restart '{self.name}': {self.description}>"

class Condition(Exception):
    """すべてのシグナル可能なコンディションの基底クラス."""
    pass

class ConditionController:
    """上位ハンドラが現場のリスタートを内省・選択するためのコントローラ."""
    def __init__(self, condition: Condition, restarts: list[Restart]) -> None:
        self.condition: Condition = condition
        self.restarts: dict[str, Restart] = {r.name: r for r in restarts}
        self.invoked_restart: Optional[Restart] = None
        self.restart_args: tuple[Any, ...] = ()
        self.restart_kwargs: dict[str, Any] = {}

    def compute_restarts(self) -> list[Restart]:
        """現在利用可能なリスタートの一覧を返却（Common Lispの compute-restarts 相当）."""
        return list(self.restarts.values())

    def invoke_restart(self, name: str, *args: Any, **kwargs: Any) -> None:
        if name not in self.restarts:
            raise KeyError(f"Restart '{name}' is not registered at signaling site.")
        self.invoked_restart = self.restarts[name]
        self.restart_args = args
        self.restart_kwargs = kwargs

class ConditionContext:
    def __init__(self) -> None:
        self.handlers: dict[type[Condition], Callable[[ConditionController], None]] = {}

_current_context: contextvars.ContextVar[Optional[ConditionContext]] = \
    contextvars.ContextVar("pylisp_condition_ctx", default=None)

class handler_bind:
    """上位でコンディションに対する修復ポリシーを登録するコンテキストマネージャ."""
    def __init__(self, mapping: dict[type[Condition], Callable[[ConditionController], None]]) -> None:
        self.mapping = mapping
        self.token: Optional[contextvars.Token[Optional[ConditionContext]]] = None

    def __enter__(self) -> handler_bind:
        ctx = ConditionContext()
        parent = _current_context.get()
        if parent:
            ctx.handlers.update(parent.handlers)
        ctx.handlers.update(self.mapping)
        self.token = _current_context.set(ctx)
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> Literal[False]:
        if self.token:
            _current_context.reset(self.token)
        return False

def signal(condition: Condition, restarts: list[Restart]) -> Any:
    """シグナル地点から直接ハンドラを逆探索する.
    
    スタックを巻き戻さず、ハンドラが選択したリスタートの実行結果を現場へ値として返却する。
    現場コードはこの戻り値を受け取り、以降の処理を継続する。
    ハンドラ不在時またはリスタート未選択時は通常の例外として送出する。
    """
    ctx = _current_context.get()
    if not ctx:
        raise condition

    ctrl = ConditionController(condition, restarts)

    for cond_type, handler in ctx.handlers.items():
        if isinstance(condition, cond_type):
            handler(ctrl)
            if ctrl.invoked_restart:
                return ctrl.invoked_restart.callback(*ctrl.restart_args, **ctrl.restart_kwargs)

    raise condition

def safe_create_task(coro: Coroutine[Any, Any, Any]) -> asyncio.Task[Any]:
    """現在のコンテキストを確実に引き継いで非同期タスクを生成するヘルパー."""
    ctx = contextvars.copy_context()
    if sys.version_info >= (3, 11):
        return asyncio.create_task(coro, context=ctx)
    async def _runner() -> Any:
        return await coro
    return asyncio.create_task(ctx.run(_runner))
```

### 5.2 パッケージ公開インターフェース (`src/pylisp/__init__.py`)
- `from pylisp.condition import Condition, ConditionController, Restart, handler_bind, safe_create_task, signal`
- `__all__ = ["DynamicVar", "dynamic_bind", "Atom", "Condition", "Restart", "ConditionController", "handler_bind", "signal", "safe_create_task"]`

### 5.3 テストスイート設計 (`tests/pylisp/test_condition.py`)
1. **現場復帰テスト**:
   - シグナル地点以降のローカルコードが正常に完遂し、ハンドラで選択したリスタートの戻り値で計算が継続されること。
2. **多重リスタート内省テスト (`compute_restarts`)**:
   - 複数のリスタートが登録された現場で、ハンドラが `compute_restarts()` を走査して動的に選択できること。
3. **引数付きリスタートテスト**:
   - `ctrl.invoke_restart("correct_value", "FIXED")` で引数がリスタートコールバックに渡ること。
4. **未処理フォールバックテスト**:
   - ハンドラ不在時、またはハンドラ内でリスタートが選択されなかった場合に、通常の例外として `raise condition` されスタックが解体されること。
5. **階層的ハンドラ継承テスト**:
   - ネストした `handler_bind` で上位のハンドラが維持・上書きされること。
6. **非同期境界越えテスト (`safe_create_task`)**:
   - `safe_create_task` で起動した別コルーチン内部の `signal` が親コンテキストの `handler_bind` に正しくトラップされること。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `src/pylisp/condition.py` に `Condition`, `Restart`, `ConditionController`, `handler_bind`, `signal`, `safe_create_task` が実装され、`mypy --strict` に完全合格すること。
- [x] スタックアンワインドを行わず、現場で `val = signal(...)` の戻り値を受け取って後続処理を継続できること。
- [x] 上位ハンドラから `compute_restarts()` により利用可能なリスタートを内省・選択できること。
- [x] ハンドラ未設定時またはリスタート未選択時は通常の例外としてスタック解体されること。
- [x] `safe_create_task` により非同期タスク境界を越えてコンディションハンドラが正しく伝播すること。
- [x] `tests/pylisp/test_condition.py` の全テストが 100% 合格すること。
- [x] `make check_format` および `make static_analysis` がエラー0件で完全合格すること。

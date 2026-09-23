---
ID: 389
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-09-24
---

# [FEAT/ENH] pylisp.dynvar 非同期セーフ動的スコープ基盤の実装 (ID: 389)

## 1. 概要 / Summary
Common Lispの `*special-variables*`（スペシャル変数）および Clojureの `binding`（動的束縛）モデルを、CPython 3.10+ / 3.14+ の低レイヤ並行プリミティブである `contextvars` をコアエンジンとして再構築し、呼び出し階層（Call Stack）の深さ方向へのみ影響する非同期セーフな動的束縛基盤（`DynamicVar`, `dynamic_bind`）を実装する。

関数の引数バケツリレー（Props drilling）やスレッドローカルの汚染を完全に排除し、FastAPI等のリクエストコンテキスト、非同期分散トレーシング（TraceContext）、データベーストランザクションスコープの透過的伝播を実現する。

さらに、ジェネレータ関数（同期 `yield` / 非同期 `async yield`）内部でコンテキストマネージャを利用した際、消費側が途中でイテレーションを放棄・中断した場合に `__exit__` が実行されず、以降のタスク全体に変数値が永続漏洩・汚染（Context Pollution）する重大なリスクを防止するため、呼び出し元スタックフレームのコードオブジェクトフラグ（`CO_GENERATOR`, `CO_ASYNC_GENERATOR`）を実行時に検査・遮断する厳格なガード機構を標準装備する。

---

## 2. トレーサビリティ / Traceability
- **設計書**: [DSN-29 Python-LISP 統合アーキテクチャ設計仕様書 第2章・第8.1節・第9章](../designs/DSN-29-python_lisp_integrated_architecture_specification.md#2-pylispdynvar-非同期セーフ動的スコープ-条件付き自作採用)
- **関連標準**: PEP 567 (Context Variables), CPython Bytecode Specification (Code Object Flags)
- **関連エージェント**: Systems Architect (SA), Software Development (SWD), Information Security Specialist (SEC), Software Quality Assurance (QA)

---

## 3. セキュリティ脅威分析とガード設計 / Threat Analysis & Security Mitigations
### 3.1 脅威シナリオ
1. **ジェネレータ早期中断によるスコープ漏洩（Context Leakage / Pollution）**:
   - `dynamic_bind` 内で `yield` を行い、呼び出し元が `break` や例外送出で途中でイテレーションを破棄した場合、ジェネレータのスタックフレームが即時GCされず、`__exit__` が発火しない。
   - その結果、後続の別リクエストやタスクに機密トークンや権限コンテキストが残留・漏洩する（CWE-404 / CWE-200）。
2. **非同期コルーチン間の不用意な交差（Corrupted Shared State）**:
   - スレッドローカル（`threading.local`）を用いた動的スコープは、`asyncio` の協調型マルチタスクでタスクが同一スレッド上で切り替わった際にコンテキストが交差混同する。

### 3.2 緩和策と技術ガード
- `inspect.currentframe().f_back` から呼び出し元フレームの `f_code.co_flags` を取得。
- `flags & (CO_GENERATOR | CO_ASYNC_GENERATOR)` が真であれば、束縛の適用を拒否し即座に `RuntimeError` を送出。
- コアストレージに `threading.local` ではなく CPython ネイティブの `contextvars.ContextVar` を採用し、非同期タスクごとの完全なコピーオンライト（CoW）分離を保証。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [docs/issues/389-implement-pylisp-dynvar-dynamic-scope.md](389-implement-pylisp-dynvar-dynamic-scope.md) (本Issue仕様書)
- [ ] [src/pylisp/__init__.py](../../src/pylisp/__init__.py) (新規パッケージ初期化およびパブリックエクスポート)
- [ ] [src/pylisp/dynvar.py](../../src/pylisp/dynvar.py) (`DynamicVar`, `dynamic_bind`, `CO_GENERATOR` ガード実装)
- [ ] [tests/pylisp/__init__.py](../../tests/pylisp/__init__.py) (テストパッケージ初期化)
- [ ] [tests/pylisp/test_dynvar.py](../../tests/pylisp/test_dynvar.py) (単体・並行・ガードテスト)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/389-implement-pylisp-dynvar-dynamic-scope`

### 5.1 モジュール設計 (`src/pylisp/dynvar.py`)
```python
import inspect
from contextvars import ContextVar, Token
from typing import TypeVar, Generic, Any, Optional

T = TypeVar("T")

CO_GENERATOR = 0x20
CO_ASYNC_GENERATOR = 0x200

class DynamicVar(Generic[T]):
    __slots__ = ("name", "_cv")

    def __init__(self, name: str, default: T):
        self.name = name
        self._cv: ContextVar[T] = ContextVar(f"*dyn_{name}*", default=default)

    @property
    def value(self) -> T:
        return self._cv.get()

    def __repr__(self) -> str:
        return f"*dyn_{self.name}*={self.value}"

class dynamic_bind:
    __slots__ = ("bindings", "tokens", "_active")

    def __init__(self, bindings: dict[DynamicVar[Any], Any]):
        self.bindings = bindings
        self.tokens: list[tuple[DynamicVar[Any], Token[Any]]] = []
        self._active = False

    def __enter__(self) -> "dynamic_bind":
        caller_frame = inspect.currentframe().f_back
        if caller_frame:
            flags = caller_frame.f_code.co_flags
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

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> bool:
        if self._active:
            for var, token in reversed(self.tokens):
                var._cv.reset(token)
            self._active = False
        return False
```

### 5.2 パッケージ公開インターフェース (`src/pylisp/__init__.py`)
- `from pylisp.dynvar import DynamicVar, dynamic_bind`
- `__all__ = ["DynamicVar", "dynamic_bind"]`

### 5.3 テストスイート設計 (`tests/pylisp/test_dynvar.py`)
1. **基本束縛とスコープ復元テスト**:
   - `DynamicVar` の初期値（デフォルト値）が正しく返るか。
   - `with dynamic_bind({x: 10}):` 内で `x.value == 10` となり、ブロック脱出後に元の値に復元されるか。
   - 複数変数の同時束縛が正しく機能するか。
2. **ネスト束縛テスト**:
   - 多段ネストした `dynamic_bind` において、スコープごとに値が上書き・復元されるか。
3. **例外発生時の安全性テスト**:
   - `dynamic_bind` ブロック内で例外が送出された場合でも、`__exit__` でトークンが確実に巻き戻され、元の値が復元されるか。
4. **非同期タスク分離テスト**:
   - `asyncio.create_task` で分岐したタスク間で、動的束縛が独立して維持され、相互に干渉（汚染）しないことの検証。
5. **ジェネレータ漏洩防止ガードテスト**:
   - 同期ジェネレータ（`def gen(): with dynamic_bind(...): yield 1`）内で `dynamic_bind` を実行した際、即座に `RuntimeError` が送出されること。
   - 非同期ジェネレータ（`async def async_gen(): with dynamic_bind(...): yield 1`）内で `dynamic_bind` を実行した際、即座に `RuntimeError` が送出されること。
   - 通常の関数呼び出しからジェネレータを駆動する外側で `dynamic_bind` を使う場合は正常に機能すること。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `src/pylisp/__init__.py` および `src/pylisp/dynvar.py` が新規作成され、`DynamicVar`, `dynamic_bind` が提供されていること。
- [x] `CO_GENERATOR` / `CO_ASYNC_GENERATOR` のフレームフラグ判定により、ジェネレータ内呼び出しが確実に検知され `RuntimeError` を送出すること。
- [x] 例外脱出時を含むすべてのケースで、`Token` によるコンテキスト値の復元が 100% 確実に実行されること。
- [x] `tests/pylisp/test_dynvar.py` の全テストが 100% 合格すること。
- [x] `make check_format` および `make static_analysis` (`mypy --strict src tests`, `xenon`, `radon`) がエラー0件で完全合格すること。


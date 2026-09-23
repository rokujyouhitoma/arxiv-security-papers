---
ID: 390
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-09-24
---

# [FEAT/ENH] pylisp.atom Free-threaded対応アトミック状態同期コンテナの実装 (ID: 390)

## 1. 概要 / Summary
Clojureの `atom` 設計に倣い、不変データ構造（Immutable Data Structures）と純粋関数を組み合わせて不可分な状態遷移を提供する同期コンテナ `Atom[T]` を実装する。

重厚なSTM（ソフトウェアトランザクショナルメモリ）や投機的CASリトライループによる過剰なCPU消費・Livelockを排し、ミューテックス同期による決定論的かつ不可分な状態更新（`swap`）およびアトミック上書き（`reset`）を提供する。

特に、CPython 3.13+/3.14+ で導入された Free-threaded Python (No-GIL) 環境下では、グローバルインタプリタロックの保護が存在しないため、状態の参照（`deref`）をロックなしで実行すると別スレッドの更新途中ポインタの不整合読み出し（**Torn Read**）や CPU キャッシュの不整合が生じる重大な並行性リスクがある。このため、更新操作だけでなく参照操作（`deref`）を含む全アクセス経路でミューテックスロックの取得を必須とする厳格ガードを実装する。

---

## 2. トレーサビリティ / Traceability
- **設計書**: [DSN-29 Python-LISP 統合アーキテクチャ設計仕様書 第3章・第8.2節・第9章](../designs/DSN-29-python_lisp_integrated_architecture_specification.md#3-pylispatom-free-threaded対応-アトミック状態同期-条件付き自作採用)
- **関連標準**: PEP 703 (Making the Global Interpreter Lock Optional in CPython), Clojure Reference Types (Atom)
- **関連エージェント**: Systems Architect (SA), Software Development (SWD), Information Security Specialist (SEC), Software Quality Assurance (QA)

---

## 3. 並行性・セキュリティ脅威分析とガード設計 / Concurrency & Security Mitigations
### 3.1 脅威シナリオ
1. **Free-threaded (No-GIL) 環境下での Torn Read / メモリ可視性喪失 (CWE-362 / CWE-662)**:
   - GILが存在しない環境では、ポインタの書き換えと参照がアトミックに行われない場合、CPU命令レベルで不完全なオブジェクト参照（破綻ポインタ・古いキャッシュ値）を読み取る Torn Read が発生する。
2. **並行更新における更新喪失 (Lost Update)**:
   - 複数スレッドが同時に状態を更新する際、読み取りと更新の間にレースコンディションが発生すると、先行スレッドの更新結果が後続スレッドによって上書き喪失する。
3. **遷移関数 (Transition Function) 失敗時の状態破損 (State Inconsistency)**:
   - `swap(fn)` に渡された純粋関数 `fn` の実行中に例外（`ZeroDivisionError` や `ValueError` 等）が送出された場合、状態が中途半端に更新・破損する。

### 3.2 緩和策と技術ガード
- `Atom` クラスに `threading.Lock()` を保持し、`__slots__ = ("_state", "_lock")` で属性改ざんを防止。
- `deref` プロパティの内部で必ず `with self._lock:` を経由させ、Free-threaded環境におけるキャッシュコヒーレンシとアトミックなメモリアクセスを保証。
- `swap` メソッドにおいて、`new_state = fn(self._state, *args, **kwargs)` の算出が成功した後にのみ `self._state = new_state` の代入を行うことで、例外発生時のロールバック（元の状態の完全保持）を保証。
- 文字列表現 `__repr__` においても `with self._lock:` で排他取得し、フォーマット中の並行書き換えによる例外や表示不整合を防止。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [docs/issues/390-implement-pylisp-atom-free-threaded-atomic-container.md](390-implement-pylisp-atom-free-threaded-atomic-container.md) (本Issue仕様書)
- [ ] [src/pylisp/__init__.py](../../src/pylisp/__init__.py) (`Atom` のパブリックエクスポート追加)
- [ ] [src/pylisp/atom.py](../../src/pylisp/atom.py) (`Atom[T]` クラスの実装)
- [ ] [tests/pylisp/test_atom.py](../../tests/pylisp/test_atom.py) (単体・マルチスレッド並行性・例外テスト)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/390-implement-pylisp-atom-free-threaded-atomic-container`

### 5.1 モジュール設計 (`src/pylisp/atom.py`)
```python
import threading
from typing import TypeVar, Generic, Callable, Any

T = TypeVar("T")

class Atom(Generic[T]):
    """不変データ構造を安全に管理するためのアトミック参照コンテナ.

    Free-threaded Python (No-GIL) 環境下でもメモリ可視性と整合性を保証する。
    """
    __slots__ = ("_state", "_lock")

    def __init__(self, initial_state: T) -> None:
        self._state: T = initial_state
        self._lock: threading.Lock = threading.Lock()

    @property
    def deref(self) -> T:
        """現在の不変状態を安全に読み取る（Free-threaded対応: ロック必須）."""
        with self._lock:
            return self._state

    def reset(self, new_val: T) -> T:
        """状態をアトミックに新しい値で上書き."""
        with self._lock:
            self._state = new_val
            return self._state

    def swap(self, fn: Callable[..., T], *args: Any, **kwargs: Any) -> T:
        """純粋関数 fn を適用して不可分に状態を更新する.

        fn(current_state, *args, **kwargs) -> new_state
        """
        with self._lock:
            new_state = fn(self._state, *args, **kwargs)
            self._state = new_state
            return self._state

    def __repr__(self) -> str:
        with self._lock:
            return f"<Atom: {self._state}>"
```

### 5.2 パッケージ公開インターフェース (`src/pylisp/__init__.py`)
- `from pylisp.atom import Atom`
- `__all__ = ["DynamicVar", "dynamic_bind", "Atom"]`

### 5.3 テストスイート設計 (`tests/pylisp/test_atom.py`)
1. **基本操作テスト**:
   - 初期化、`deref`、`reset`、文字列表現 `repr` の検証。
2. **不可分更新 (`swap`) テスト**:
   - 引数なし関数、位置引数付き関数、キーワード引数付き関数による更新。
3. **マルチスレッド高並行性テスト (Lost Update 防御検証)**:
   - 20〜50個のスレッドからそれぞれ1,000回並行 `swap`（インクリメント）を実行し、最終値が厳密にスレッド数 × 1,000 に一致することを検証。
4. **並行 `deref` と `swap` の整合性テスト**:
   - バックグラウンドで高速更新が走る中で、参照側が常に有効な中間状態（壊れたオブジェクトやTorn Readなし）を取得できることの検証。
5. **例外発生時のアトミック性（ロールバック）テスト**:
   - `swap(fn)` の実行中に例外が送出された場合、`Atom` の内部状態が更新されず従前の状態を維持していることの検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `src/pylisp/atom.py` に `Atom` が実装され、`mypy --strict` に完全合格すること。
- [x] `deref`, `reset`, `swap`, `__repr__` の全アクセス経路で確実に `self._lock` が取得されていること。
- [x] マルチスレッド高競合下での並行 `swap` テストにおいて、Lost Update が 0 件であり計算結果が 100% 正確であること。
- [x] `swap` 関数内で例外発生時に内部状態が保護・維持されること。
- [x] `tests/pylisp/test_atom.py` の全テストが 100% 合格すること。
- [x] `make check_format` および `make static_analysis` がエラー0件で完全合格すること。

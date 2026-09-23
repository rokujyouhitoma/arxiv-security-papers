---
ID: 390
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] pylisp.atom Free-threaded対応アトミック状態同期コンテナの実装 (ID: 390)

## 1. 概要 / Summary
Clojureの `atom` 設計に倣い、不変データ構造と組み合わせて不可分な状態遷移を提供する同期コンテナ `Atom[T]` を実装する。

投機的リトライ（CASループ）によるCPU浪費やLivelockを排し、純粋関数適用による不可分更新（`swap`）およびアトミック上書き（`reset`）を提供する。特に Free-threaded Python (No-GIL, 3.13+/3.14+) 環境下における CPU キャッシュ不整合や Torn Read を完全に防止するため、更新時だけでなく参照操作（`deref`）を含む全アクセス経路でミューテックスロックの取得を必須とする厳格ガードを実装する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-29 Python-LISP 統合アーキテクチャ設計仕様書 第3章・第8.2節・第9章](../designs/DSN-29-python_lisp_integrated_architecture_specification.md#3-pylispatom-free-threaded対応-アトミック状態同期-条件付き自作採用)
- 関連仕様: Free-threaded CPython (PEP 703), Clojure Reference Types (Atom)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/pylisp/__init__.py](../../src/pylisp/__init__.py)
- [ ] [src/pylisp/atom.py](../../src/pylisp/atom.py)
- [ ] [tests/pylisp/test_atom.py](../../tests/pylisp/test_atom.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/390-implement-pylisp-atom-free-threaded-atomic-container`

1. **`Atom[T]` クラスの実装**:
   - `__slots__ = ("_state", "_lock")` を定義。
   - `threading.Lock()` を内部ミューテックスとして保持。
   - `deref`: プロパティ。`with self._lock:` ブロック内で現在の参照値を取得して返却（Free-threaded 環境での Torn Read 防止）。
   - `reset(new_val: T) -> T`: `with self._lock:` で排他ロックを取得し、状態を上書きして返却。
   - `swap(fn: Callable[..., T], *args: Any, **kwargs: Any) -> T`: `with self._lock:` で排他ロックを取得し、純粋関数 `fn` を適用して不可分に状態を更新。
   - `__repr__`: スレッドセーフに文字列表現を生成。
2. **並行性・整合性テストスイートの整備**:
   - マルチスレッド（`concurrent.futures.ThreadPoolExecutor`）による超高頻度並行 `swap` での更新喪失（Lost Update）ゼロ検証。
   - 並行 `deref` と並行 `swap` が衝突した際のメモリ可視性・不整合不在テスト。
   - 更新関数 `fn` 内で例外が発生した場合のロールバック・状態保持検証。
   - `mypy --strict` 型適合性検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `src/pylisp/atom.py` に `Atom` が実装され、`mypy --strict` に完全合格すること。
- [ ] `deref`, `reset`, `swap`, `__repr__` の全アクセス経路で確実に `self._lock` が取得されていること。
- [ ] 多数のスレッドによる並行 `swap` 実行において、レースコンディションによる計算不整合が一切生じないこと。
- [ ] `tests/pylisp/test_atom.py` の全テストが通過すること。

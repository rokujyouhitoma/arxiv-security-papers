---
ID: 389
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] pylisp.dynvar 非同期セーフ動的スコープ基盤の実装 (ID: 389)

## 1. 概要 / Summary
Common Lispの `*special-variables*` および Clojureの `binding` を CPython 3.10+ の `contextvars` をコアに再現し、呼び出し階層の深さ方向へのみ影響する非同期セーフな動的束縛基盤（`DynamicVar`, `dynamic_bind`）を実装する。

関数の引数バケツリレー（Props drilling）を排除しつつ、ジェネレータ関数（`yield` / `async yield`）内部でのイテレーション途中破棄に伴うコンテキスト値の永続漏洩（Context Pollution）を防止するため、呼び出し元スタックフレームのコードオブジェクトフラグ（`CO_GENERATOR`, `CO_ASYNC_GENERATOR`）を実行時検査・遮断する厳格なガード機構を標準装備する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-29 Python-LISP 統合アーキテクチャ設計仕様書 第2章・第8.1節・第9章](../designs/DSN-29-python_lisp_integrated_architecture_specification.md#2-pylispdynvar-非同期セーフ動的スコープ-条件付き自作採用)
- 関連仕様: CPython `contextvars`, PEP 567, Common Lisp Special Variables

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/pylisp/__init__.py](../../src/pylisp/__init__.py)
- [ ] [src/pylisp/dynvar.py](../../src/pylisp/dynvar.py)
- [ ] [tests/pylisp/test_dynvar.py](../../tests/pylisp/test_dynvar.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/389-implement-pylisp-dynvar-dynamic-scope`

1. **`DynamicVar[T]` クラスの実装**:
   - `__slots__ = ("name", "_cv")` を定義し、メモリオーバーヘッドを極小化。
   - `ContextVar` をカプセル化し、スレッドセーフ・タスクローカルな値取得プロパティ `value` を提供。
2. **`dynamic_bind` コンテキストマネージャの実装**:
   - `__enter__`: `inspect.currentframe().f_back` から `co_flags` を取得。
   - `co_flags & (CO_GENERATOR | CO_ASYNC_GENERATOR)` 判定を行い、ジェネレータ内での利用検知時に `RuntimeError` を送出してスコープ漏洩を未然遮断。
   - 複数の `DynamicVar` を一括 `set()` し、トークンスタックを保持。
   - `__exit__`: 逆順で `reset()` を呼び出し、例外発生時にも元のコンテキストへ完全復元。
3. **包括的テストスイートの整備**:
   - 同期関数・非同期コルーチンでのスコープ分離テスト。
   - ネストした `dynamic_bind` の復元テスト。
   - 同期ジェネレータ・非同期ジェネレータ内呼び出しにおける `RuntimeError` 送出ガードテスト。
   - `mypy --strict` 型適合性検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `src/pylisp/dynvar.py` に `DynamicVar`, `dynamic_bind` が実装され、`mypy --strict` に完全合格すること。
- [ ] 同期・非同期関数の階層深さ方向へ値が正しく伝播し、ブロック脱出時に元の値へ確実に巻き戻ること。
- [ ] ジェネレータ関数および非同期ジェネレータ関数の内部で `dynamic_bind` を実行した際、即座に `RuntimeError` が送出されること。
- [ ] `tests/pylisp/test_dynvar.py` の全テストが通過すること。

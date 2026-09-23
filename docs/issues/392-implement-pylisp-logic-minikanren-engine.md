---
ID: 392
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] pylisp.logic HAMT構造共有＆Occurs Check付きminiKanren推論エンジンの実装 (ID: 392)

## 1. 概要 / Summary
Clojureの `core.logic` および Schemeの `miniKanren` を基盤とする関係プログラミング（Relational Programming）推論エンジンを実装する。認可ルール解決（RBAC/ABAC）やセキュリティ制約充足の宣言的解決を担う。

単一化アルゴリズムにおいて循環参照項（自己言及構造）の評価に伴う CPython の `RecursionError` クラッシュを完全に防止するため、Occurs Check を標準かつ無効化不能な構造として組み込む。さらに、バックトラック探索ノードでの辞書コピー（`{**s}`）を全廃し、C拡張である `immutables.Map`（HAMT）を置換マップ（`Subst`）に直結することで、探索ノード分岐時のアロケーション爆発およびGC負荷を極小化する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-29 Python-LISP 統合アーキテクチャ設計仕様書 第5章・第9章](../designs/DSN-29-python_lisp_integrated_architecture_specification.md#5-pylisplogic-hamt置換--occurs-check付き-minikanren-条件付き自作採用)
- 関連仕様: miniKanren (William Byrd, Dan Friedman), Clojure core.logic, C拡張 `immutables.Map` (HAMT)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/pylisp/__init__.py](../../src/pylisp/__init__.py)
- [ ] [src/pylisp/logic.py](../../src/pylisp/logic.py)
- [ ] [tests/pylisp/test_logic.py](../../tests/pylisp/test_logic.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/392-implement-pylisp-logic-minikanren-engine`

1. **論理変数および置換マップ構造の実装**:
   - `Var`: `__slots__ = ("name",)` を持つ論理変数シンボル。
   - `Subst = immutables.Map`: 構造共有（HAMT）に基づく不変置換マップ。
2. **単一化・探索コアエンジンの実装**:
   - `walk(u: Any, s: Subst) -> Any`: 置換マップ内を再帰走査して束縛解決。
   - `occurs_check(v: Var, term: Any, s: Subst) -> bool`: 項の中に変数 `v` が循環して含まれていないかを検証し、自己言及ループを検知。
   - `unify(u: Any, v: Any, s: Subst) -> Optional[Subst]`:
     - 変数束縛時に `occurs_check` を実施。循環参照検出時は探索失敗（`None`）を即座に返し、クラッシュを防止。
     - 辞書コピーを行わず、`s.set(var, val)` による HAMT 構造共有更新を実施。
     - タプル・構造体の一致判定を再帰実行。
   - `eq(u: Any, v: Any)`: 等値ゴール生成器（ジェネレータ関数）。
   - `run(q: Var, *goals) -> list[Any]`: クエリ変数に対する解の探索実行エントリポイント。
3. **テストスイートの整備**:
   - 基本的な単一化（変数束縛、定数照合、複合タプル照合）テスト。
   - `unify(x, (x, 1))` 等の循環参照に対して `RecursionError` が発生せず `None` を返却する Occurs Check 検証。
   - 複数解・バックトラック探索の網羅テスト。
   - `immutables.Map` 構造共有によるアロケーション健全性テスト。
   - `mypy --strict` 型適合性検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `src/pylisp/logic.py` に `Var`, `walk`, `occurs_check`, `unify`, `eq`, `run` が実装され、`mypy --strict` に完全合格すること。
- [ ] 自己言及構造の単一化時に `RecursionError` が送出されず、安全に探索失敗（`None`）として処理されること。
- [ ] 置換マップの分岐更新において標準辞書コピーではなく `immutables.Map` の構造共有が使用されていること。
- [ ] `tests/pylisp/test_logic.py` の全テストが通過すること。

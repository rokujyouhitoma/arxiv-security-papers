---
ID: 392
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] pylisp.logic 構造共有＆Occurs Check付きminiKanren推論エンジンの実装 (ID: 392)

## 1. 概要 / Summary
Clojureの `core.logic` および Schemeの `miniKanren` を基盤とする関係プログラミング（Relational Programming）推論エンジンを実装する。認可ルール解決（RBAC/ABAC）やセキュリティ制約充足の宣言的解決を担う。

単一化アルゴリズムにおいて循環参照項（自己言及構造）の評価に伴う CPython の `RecursionError` クラッシュを完全に防止するため、Occurs Check を標準かつ無効化不能な構造として組み込む。さらに、バックトラック探索ノードでの辞書コピー（`{**s}`）を全廃し、外部パッケージゼロ依存の Pure Python 構造共有置換マップ（`PersistentMap`）を置換マップ（`Subst`）に直結することで、探索ノード分岐時のアロケーション爆発およびGC負荷を極小化する。

---

## 2. トレーサビリティ / Traceability
- **設計書**: [DSN-29 Python-LISP 統合アーキテクチャ設計仕様書 第5章・第9章](../designs/DSN-29-python_lisp_integrated_architecture_specification.md#5-pylisplogic-hamt置換--occurs-check付き-minikanren-条件付き自作採用)
- **関連仕様**: miniKanren (William Byrd, Dan Friedman), Clojure core.logic
- **関連エージェント**: Systems Architect (SA), Software Development (SWD), Information Security Specialist (SEC), Software Quality Assurance (QA)

---

## 3. セキュリティ脅威分析とガード設計 / Threat Analysis & Security Mitigations
### 3.1 脅威シナリオ
1. **制御不能な再帰・スタックオーバーフロー (Uncontrolled Recursion / CWE-674)**:
   - `unify(x, (x, 1))` のような自己言及構造を単一化しようとした際、走査が無限ループに陥り CPython が `RecursionError` でクラッシュする。
2. **探索分岐時のメモリ爆発・リソース枯渇 (Uncontrolled Resource Consumption / CWE-400)**:
   - バックトラック探索時の置換マップ（`Subst`）に標準辞書コピー `{**s}` を使用すると、探索深度や分岐数の二乗オーダーでアロケーションが発生しGCが逼迫・サービス不能（DoS）に陥る。
3. **推論探索の無限展開・ハング (Algorithmic Complexity / CWE-407)**:
   - 深いゴール木評価での探索パスの非効率な複製による計算量爆発。

### 3.2 緩和策と技術ガード
- **無効化不能な Occurs Check**:
  - `unify` の変数束縛時に必ず `occurs_check` を実施。循環参照を検知した場合は例外を投げず即座に単一化失敗（`None`）を返却し、安全に探索を枝刈りする。
- **構造共有不変置換マップ (`PersistentMap`)**:
  - 辞書全体のコピー（`{**s}` や `dict.copy()`）を完全排除。親ノードへの参照リンクを保持する構造共有イミュータブルマップを採用し、分岐生成コストを $O(1)$ に抑制。
- **ゼロ外部依存 (Zero External Dependencies)**:
  - 外部パッケージの追加インストールを行わず、Python 3.14 標準機能のみで安全かつ高パフォーマンスに完結。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [docs/issues/392-implement-pylisp-logic-minikanren-engine.md](392-implement-pylisp-logic-minikanren-engine.md) (本Issue仕様書)
- [x] [src/pylisp/__init__.py](../../src/pylisp/__init__.py) (`Var`, `PersistentMap`, `walk`, `occurs_check`, `unify`, `eq`, `run` のエクスポート追加)
- [x] [src/pylisp/logic.py](../../src/pylisp/logic.py) (miniKanrenコアおよび構造共有置換マップの実装)
- [x] [tests/pylisp/test_logic.py](../../tests/pylisp/test_logic.py) (単一化、Occurs Check、バックトラック、構造共有テスト)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/392-implement-pylisp-logic-minikanren-engine`

### 5.1 モジュール設計 (`src/pylisp/logic.py`)
1. **`Var` クラス**:
   - `__slots__ = ("name",)`
   - `__repr__ -> f"?{self.name}"`
   - `__eq__` / `__hash__`: 同一オブジェクトまたは名前の一致に基づく判定。
2. **`PersistentMap` クラス**:
   - 構造共有連想構造（Persistent Node Linked Map）。
   - 各ノードは `(key, value, parent)` を持ち、`set(key, value)` は親を参照する新ノードを生成（$O(1)$）。
   - `__contains__`, `__getitem__`, `get(key, default)` による探索。
   - 反復走査（`__iter__`, `items()`, `keys()`）のサポート。
3. **`walk(u: Any, s: PersistentMap) -> Any`**:
   - 置換マップを辿り、最終的に束縛されている具象値または未束縛変数を返却。
4. **`occurs_check(v: Var, term: Any, s: PersistentMap) -> bool`**:
   - `term` を `walk` し、`term == v` なら `True`。
   - `term` が `tuple` または `list` ならば再帰的に要素を走査。
5. **`unify(u: Any, v: Any, s: PersistentMap) -> Optional[PersistentMap]`**:
   - `u` と `v` を `walk`。
   - `u == v` ならそのまま `s` を返却。
   - `u` が `Var` の場合: `occurs_check(u, v, s)` が `True` なら `None`（失敗）、そうでなければ `s.set(u, v)`。
   - `v` が `Var` の場合: `occurs_check(v, u, s)` が `True` なら `None`、そうでなければ `s.set(v, u)`。
   - `u` と `v` が共に `tuple`（または共に `list`）で長さが等しい場合: 各要素ペアを再帰的に単一化。
   - それ以外は `None`。
6. **`eq(u: Any, v: Any)`**:
   - ゴール関数 `Callable[[PersistentMap], Generator[PersistentMap, None, None]]` を返却。
   - `unify(u, v, s)` が成功すれば新置換を `yield`。
7. **`run(q: Var, *goals: Callable[[PersistentMap], Generator[PersistentMap, None, None]]) -> list[Any]`**:
   - 空の `PersistentMap()` から開始し、ゴール群をバックトラック探索。
   - 各成功置換における `walk(q, s)` の結果をリストとして集約・返却。

### 5.2 パッケージ公開インターフェース (`src/pylisp/__init__.py`)
- `from pylisp.logic import PersistentMap, Var, eq, occurs_check, run, unify, walk`
- `__all__` に上記を追加。

### 5.3 テストスイート設計 (`tests/pylisp/test_logic.py`)
1. **基本単一化テスト**:
   - 定数同士の一致・不一致
   - 変数と定数の単一化
   - 変数同士の連鎖単一化 (`unify(x, y)` & `unify(y, 42)`)
2. **Occurs Check テスト**:
   - `unify(x, (x, 1))` が `RecursionError` を起こさず `None` を返却すること。
   - 深い複合構造内の循環参照検知。
3. **複合データ構造の単一化**:
   - ネストしたタプル・リストのパターンマッチング。
4. **関係探索・バックトラックテスト (`run`, `eq`)**:
   - 単一ゴールの解探索。
   - 複数ゴールの連立解決（交差制約）。
5. **PersistentMap 構造共有・イミュータビリティテスト**:
   - 元のマップが変更されないこと（副作用なし）。
   - 分岐ノードが親を共有していること。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `src/pylisp/logic.py` に `Var`, `PersistentMap`, `walk`, `occurs_check`, `unify`, `eq`, `run` が実装され、`mypy --strict` に完全合格すること。
- [x] 外部パッケージを一切インストールせず、Pure Python / 標準機能のみでゼロ依存動作すること。
- [x] 自己言及構造（`unify(x, (x, 1))` 等）の単一化時に `RecursionError` が送出されず、安全に探索失敗（`None`）として処理されること。
- [x] 置換マップの分岐更新において標準辞書コピー（`{**s}`）を行わず、構造共有イミュータブルマップが使用されていること。
- [x] `tests/pylisp/test_logic.py` の全テストが 100% 合格すること。
- [x] `make check_format` および `make static_analysis` がエラー0件で完全合格すること。


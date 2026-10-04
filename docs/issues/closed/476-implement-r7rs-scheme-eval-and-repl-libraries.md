---
ID: 476
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS (scheme eval) および (scheme repl) 動的環境評価・対話セッションライブラリの実装と完全準拠 (ID: 476)

## 1. 概要 / Summary
R7RS-small (Revised^7 Report on the Algorithmic Language Scheme) 6.12 および 7.1.1 で規定される `(scheme eval)` および `(scheme repl)` 標準ライブラリを完全実装・サポートする。
これらは Scheme における動的コード評価および対話環境の標準インターフェースを定義する中核ライブラリである。
- `(eval expr env-spec)`: `expr` を指定された環境 `env-spec` で動的評価
- `(environment import-spec ...)`: 指定した import-spec 群から新たな評価環境オブジェクトを構築
- `(interaction-environment)`: 対話型セッション・トップレベル環境オブジェクトを返却
本 Issue では、プリミティブの実装、マクロ衛生性（`core_forms` 登録）、`ilisp/module.py` への `(scheme eval)` と `(scheme repl)` の登録、包括的テストスイートの作成、および `ilisp/docs/SPEC_R7RS.md` の準拠マトリクス更新を実施する。

---

## 2. トレーサビリティ / Traceability
- R7RS-small Section 6.12 (Environments and evaluation): `environment`, `eval`
- R7RS-small Section 6.12 (Interaction environment): `interaction-environment`
- R7RS-small Section 7.1.1 (Standard Libraries): `(scheme eval)`, `(scheme repl)`
- [SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md): 動的評価および標準ライブラリ仕様マトリクス

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ilisp/env.py](../../ilisp/env.py): `eval`, `environment`, `interaction-environment` プリミティブの実装
- [x] [ilisp/syntax.py](../../ilisp/syntax.py): `core_forms` への動的評価識別子の登録
- [x] [ilisp/module.py](../../ilisp/module.py): `(scheme eval)` および `(scheme repl)` の登録とエクスポート
- [x] [tests/ilisp/test_scheme_eval_repl.py](../../tests/ilisp/test_scheme_eval_repl.py): 新規テストスイート
- [x] [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md): 準拠状況の更新 (全203機能 100% 達成)
- [x] [docs/issues/README.md](README.md): Issue 台帳の更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/476-implement-scheme-eval-and-repl`

1. **プリミティブ実装**:
   - `ilisp/env.py` 内に以下を実装:
     - `prim_eval(expr: Any, env_obj: Any) -> Any`: `env_obj` が `Environment` であることを検証し、`eval_expr(expr, env_obj)` を実行。
     - `prim_environment(*specs: Any) -> Environment`: 新規 `Environment` を生成し、各 `spec`（S式 Datum またはペア）から `resolve_import_set` を経由して束縛を注入。
     - `prim_interaction_environment() -> Environment`: 現在のベース環境（`env`）を返却。
2. **マクロ衛生性と識別子保護**:
   - `ilisp/syntax.py` の `core_forms` に `eval`, `environment`, `interaction-environment` を追加。
3. **ライブラリ登録**:
   - `ilisp/module.py` に:
     - `(scheme eval)`: `eval`, `environment` をエクスポート
     - `(scheme repl)`: `interaction-environment` をエクスポート
4. **テストスイート実装**:
   - `tests/ilisp/test_scheme_eval_repl.py` を作成し、以下を検証:
     - `(import (scheme eval) (scheme repl))` の正常性
     - `(eval '(* 3 4) (environment '(scheme base)))` によるクリーン環境での評価
     - `environment` で構築された分離環境への変数の定義と `eval` での参照
     - `(interaction-environment)` による現在環境での変数の読み書き
     - 不正な環境オブジェクトを渡した場合の型エラーハンドリング
5. **仕様マトリクス更新**:
   - `ilisp/docs/SPEC_R7RS.md` の `(scheme eval)` および `(scheme repl)` を Fully Supported (🟢 100%) に更新し、R7RS-small 言語機能全203機能の完全準拠 (100%) を達成。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ilisp/env.py` に `eval`, `environment`, `interaction-environment` が実装されていること
- [x] `(scheme eval)` および `(scheme repl)` がインポート可能であること
- [x] `tests/ilisp/test_scheme_eval_repl.py` のテストがすべて PASS すること
- [x] 全テスト（360件以上）が PASS し、`flake8`、`mypy --strict ilisp` が 0 エラーであること
- [x] `ilisp/docs/SPEC_R7RS.md` の準拠ステータスが更新され、全203機能が 100% Fully Supported となっていること


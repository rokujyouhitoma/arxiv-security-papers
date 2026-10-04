---
ID: 479
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] (ilisp python) ライブラリの独立分離と import-python マクロの実装 (ID: 479)

## 1. 概要 / Summary
R7RS-small 公式規格の `(scheme base)` ライブラリ（`ilisp/stdlib/base.ilisp`）の純粋性を保護し、非標準な Python 固有機能の混入を防ぐため、Python ゼロコピー相互運用機能を **`(ilisp python)`**（`ilisp/stdlib/python.ilisp`）として独立ライブラリに分離する。
また、ユーザーが直面した `Unbound variable: 'import-python'` エラーを解消し、`import-python` をコア評価器の特殊形式ではなく **純粋な Scheme マクロ（`py-import`, `py-get`, `define` への脱糖）** として実装・提供する。

---

## 2. トレーサビリティ / Traceability
- [DSN-31 (ILISP R7RS コアアーキテクチャ包括設計仕様書)](../../designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md)
- [PYTHON_INTEROP.md](../../../ilisp/docs/PYTHON_INTEROP.md): Python 双方向ゼロコピー相互運用仕様書
- [SPEC_R7RS.md](../../../ilisp/docs/SPEC_R7RS.md): R7RS 仕様準拠マトリクス
- Issue #478: chibi-scheme 公式 R7RS 適合性テストスイートの 100% 完全合格化

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ilisp/stdlib/python.ilisp](../../../ilisp/stdlib/python.ilisp): `(ilisp python)` 拡張ライブラリ新設 (`import-python`, `->>`, `|\|>>|` マクロ)
- [x] [ilisp/module.py](../../../ilisp/module.py): `(ilisp python)` ライブラリへのエクスポートシンボル登録
- [x] [ilisp/env.py](../../../ilisp/env.py): `make_initial_env` での `python.ilisp` プリロード & `prim_py_call`/`prim_py_import`/`prim_py_get` の高信頼化
- [x] [tests/ilisp/test_modules.py](../../../tests/ilisp/test_modules.py): `TestImportPythonInterop` テストクラスの追加
- [x] [docs/issues/README.md](../README.md): Issue 台帳の更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/479-implement-import-python-macro-library`

1. **`base.ilisp` の純粋性保護**:
   - `base.ilisp` は R7RS-small `(scheme base)` のみに特化させ、Python 固有の非標準キーワード・構文を混在させない。
2. **マクロによるエレガントな脱糖**:
   - `import-python` を Special Form ではなく `(py-import ...)`, `(py-get ...)`, `(define ...)` を生成する `define-macro` として `stdlib/python.ilisp` に実装。
   - `(import-python (mod :as alias))`
   - `(import-python (mod mem1 mem2 ...))`
   - `(import-python (mod (orig :as alias)))`
   - `(import-python (mod orig :as alias))`
   - `(import-python (mod))` / `(import-python mod)`
   の各形式を統一的にサポート。
3. **対話型 REPL およびライブラリインポート双方での動作保証**:
   - `(import (ilisp python))` による明示的インポート。
   - REPL や対話セッション（`interaction-environment`）での初期利用可能性。
4. **品質ゲートとテスト全数通過**:
   - 全 379 件の ILISP 単体・統合テスト 100% PASS。
   - chibi-scheme 公式 R7RS 適合性テスト（1,233 件）100% PASS。
   - `flake8`, `mypy --strict`, `make check_format` エラー 0 件。

---

## 5. 完了確認 (Definition of Done)
- [x] `import-python` がマクロとして正しく展開され、`Unbound variable: 'import-python'` エラーが完全に解消されること。
- [x] 存在しない Python パッケージ（例: 未インストールの `torch`）指定時に、適切な Scheme 例外（`&error-object(kind=import)`）が送出されること。
- [x] `tests/ilisp/test_modules.py` に `TestImportPythonInterop` が追加され、全件合格すること。
- [x] 全品質ゲート（flake8, mypy, black, pytest）が 100% 合格すること。

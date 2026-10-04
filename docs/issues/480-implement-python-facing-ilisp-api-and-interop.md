---
ID: 480
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Python 側からの ILISP 呼び出し API (ilisp.eval, ilisp.Evaluator, ilisp.interop) の実装 (ID: 480)

## 1. 概要 / Summary

現在、`ilisp/docs/PYTHON_INTEROP.md` の「第 4 節 Python 側からの ILISP 利用仕様」において、Python アプリケーション側から ILISP の S 式評価やモジュールロードを行う理想仕様が規定されている。しかし現行コードベース（`ilisp/__init__.py`, `ilisp/repl.py`）では、トップレベルの `ilisp.eval` や `ilisp.Evaluator` クラス、およびモジュールローダー `ilisp.interop.load_ilisp_module` が未実装であり、Python から ILISP を呼び出すための公開 API にギャップが存在する。

本 Issue では、Python ↔ ILISP 間の双方向ゼロコピー相互運用を真に完結させるため、Python アプリケーションやデータサイエンス／AI スクリプト（PyTorch, Transformers 等）から手軽かつ透過的に ILISP を利用できるファーストクラス API を実装・提供する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書: [DSN-31: ILISP R7RS コアアーキテクチャ包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) (第 4.3 節 Python からの透過インポート)
- 仕様ドキュメント: [ilisp/docs/PYTHON_INTEROP.md](../../ilisp/docs/PYTHON_INTEROP.md) (第 4 節 Python 側からの ILISP 利用仕様)
- 関連 Issue: [Issue 479: (ilisp python) ライブラリの独立分離と import-python マクロの実装](closed/479-implement-import-python-macro-library.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ilisp/__init__.py](../../ilisp/__init__.py): `eval`, `Evaluator`, `load_ilisp_module` のトップレベルエクスポート
- [ ] [ilisp/interop.py](../../ilisp/interop.py): 新規作成。`Evaluator`、`IlispModuleProxy`、`load_ilisp_module`、`sys.meta_path` ローダーの実装
- [ ] [ilisp/repl.py](../../ilisp/repl.py): `run_string` / `eval_expr` との統合
- [ ] [ilisp/docs/PYTHON_INTEROP.md](../../ilisp/docs/PYTHON_INTEROP.md): サンプルコードの整合性確認
- [ ] [tests/ilisp/test_interop.py](../../tests/ilisp/test_interop.py): Python 側からの呼び出し、モジュールロード、透過的インポートの網羅的単体テスト

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/480-implement-python-facing-ilisp-api`

1. **`ilisp/interop.py` の新設**:
   - `Evaluator` クラス:
     - 内部に持続的な `Environment` インスタンスを保持。
     - `eval_string(code: str, backend: str = "interp") -> Any`: S 式文字列をパース・評価し、結果を返却。
     - `eval(code: str) -> Any`: 糖衣メソッド。
     - `get(symbol_name: str) -> Any`: 環境から指定シンボルのバインド値を取得。
     - `set(symbol_name: str, value: Any) -> None`: 環境へ変数を束縛。
   - `IlispModuleProxy` クラス:
     - Scheme 側で定義されたシンボル群（`foo-bar` など）を Python の属性アクセス（`proxy.foo_bar`）として透過ディスパッチ。
     - 関数オブジェクトは自動的に Python の `*args` を受け取り Scheme リスト/引数へ適合して実行。
   - `load_ilisp_module(filepath: str) -> IlispModuleProxy`:
     - 指定された `.ilisp` または `.scm` ファイルを評価し、その環境をラップした `IlispModuleProxy` を生成。
   - `IlispImportFinder` & `IlispImportLoader` (`importlib.abc` / `sys.meta_path`):
     - `register_import_hook()` により Python の標準 `import my_ilisp_code` を可能にする。

2. **トップレベル API の公開 (`ilisp/__init__.py`)**:
   - `ilisp.eval(code: str, env: Optional[Environment] = None) -> Any`
   - `ilisp.Evaluator`
   - `ilisp.load_module(filepath: str)`
   - `ilisp.register_import_hook()`

3. **テストの追加と品質ゲート検証**:
   - `tests/ilisp/test_interop.py` を新設し、各種 Python 呼び出しパターン、例外の透過伝播、`sys.meta_path` インポートを検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `import ilisp; ilisp.eval("(+ 1 2 3)") == 6` が正常動作すること。
- [ ] `evaluator = ilisp.Evaluator()` を用いて変数の連続評価・状態維持ができること。
- [ ] `load_ilisp_module("...")` により、Scheme の関数が `module.func_name(...)` として Python から直接呼び出せること。
- [ ] `sys.meta_path` を介した透過的インポートが動作すること。
- [ ] `tests/ilisp/test_interop.py` の全テストが 100% PASS すること。
- [ ] 全品質ゲート（`make check_format`, `make static_analysis`）をパスすること。

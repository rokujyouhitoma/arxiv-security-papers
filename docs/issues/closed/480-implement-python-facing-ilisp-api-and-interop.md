---
ID: 480
種別: Feature
優先度: High
ステータス: Closed
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

## 3. 脅威分析とセキュリティ要件 (Threat Model & Security Considerations)

1. **ファイルパス探索とディレクトリトラバーサル**:
   - `load_ilisp_module` における不正ファイルパスの取り扱い。存在しないファイルやパーミッションエラーに対して、明瞭かつ安全な例外（`FileNotFoundError`, `PermissionError`）を送出し、スタックトレースでの内部情報漏洩を制御。
2. **`sys.meta_path` インポートフックの安全性**:
   - `IlispImportFinder` が意図しない Python 標準拡張や外部パッケージと競合・ハイジャックしないよう、`.ilisp` および `.scm` 拡張子のみを厳格に限定探索。
   - `register_import_hook()` の二重登録防止および `unregister_import_hook()` による安全なアンロード機構の提供。
3. **識別子マッピングと衝突防止**:
   - Scheme のケバブケース（`foo-bar`）から Python のスネークケース（`foo_bar`）への変換において、完全一致の属性探索を最優先とし、意図しないシンボルの隠蔽や名前空間破壊を抑止。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ilisp/__init__.py](../../ilisp/__init__.py): `eval`, `Evaluator`, `load_module`, `load_ilisp_module`, `register_import_hook`, `unregister_import_hook`, `IlispModuleProxy` のトップレベルエクスポート
- [x] [ilisp/interop.py](../../ilisp/interop.py): 新規作成。`Evaluator`、`IlispModuleProxy`、`load_ilisp_module`、`IlispImportFinder`、`IlispImportLoader`、`register_import_hook`、`unregister_import_hook` の実装
- [x] [ilisp/docs/PYTHON_INTEROP.md](../../ilisp/docs/PYTHON_INTEROP.md): Python 側からの利用 API ドキュメントの最新化
- [x] [tests/ilisp/test_interop.py](../../tests/ilisp/test_interop.py): 新規テスト。Python 側からの呼び出し、モジュールロード、双方向関数呼出、`sys.meta_path` インポートの網羅的テスト

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/480-implement-python-facing-ilisp-api`

1. **`ilisp/interop.py` の新設**:
   - `Evaluator` クラス:
     - 内部に持続的な `Environment` インスタンスを保持（初期化オプションで `preload_stdlib=True`）。
     - `eval_string(code: str, filename: str = "<eval>", backend: str = "interp") -> Any`: S 式文字列をパース・連続評価し、最後の式の評価値を返却。
     - `eval(code: str, backend: str = "interp") -> Any`: `eval_string` のエイリアス。
     - `get(symbol_name: str) -> Any`: 環境から指定シンボルのバインド値を取得（ケバブケース自動フォールバック対応）。
     - `set(symbol_name: str, value: Any) -> None`: 環境へ変数を定義・束縛。
     - `call(symbol_name: str, *args: Any) -> Any`: 環境内の手続きを Python 引数で直接呼び出し。
   - `IlispModuleProxy` クラス:
     - Scheme 側で定義されたシンボル群（`foo-bar` など）を Python の属性アクセス（`proxy.foo_bar`）として透過ディスパッチ。完全一致優先、ハイフン→アンダースコア変換対応。
     - `__dir__()` を実装し、Python インタプリタや IDE でのシンボル補完を支援。
     - `eval(code: str) -> Any`: 当該モジュール環境内で追加式を評価。
   - `load_ilisp_module(filepath: Union[str, Path], env: Optional[Environment] = None, name: Optional[str] = None) -> IlispModuleProxy`:
     - 指定された `.ilisp` または `.scm` ファイルを評価し、その環境をラップした `IlispModuleProxy` を生成。
   - `IlispImportFinder` & `IlispImportLoader` (`importlib.abc` / `sys.meta_path`):
     - `sys.path` から `.ilisp` / `.scm` ファイルを自動解決し、通常の Python `import my_ilisp_module` を可能にする。
     - `register_import_hook()` および `unregister_import_hook()` の提供。

2. **トップレベル API の公開 (`ilisp/__init__.py`)**:
   - `ilisp.eval(code: str, env: Optional[Environment] = None, backend: str = "interp") -> Any`
   - `ilisp.Evaluator`
   - `ilisp.load_module(filepath: Union[str, Path])` / `ilisp.load_ilisp_module`
   - `ilisp.IlispModuleProxy`
   - `ilisp.register_import_hook()`
   - `ilisp.unregister_import_hook()`

3. **テストの追加と品質ゲート検証**:
   - `tests/ilisp/test_interop.py` を新設し、以下を網羅検証：
     - `ilisp.eval` による即時評価（計算、リスト操作、ラムダ式）
     - `Evaluator` によるセッション間状態維持と `get` / `set` / `call`
     - `load_ilisp_module` による外部ファイル読込と属性経由の関数実行（`foo_bar` 呼出）
     - Python 関数を ILISP 側へ渡して高階関数からコールバック実行
     - `sys.meta_path` 経由の透過的 `import` と `unregister_import_hook`
     - 存在しないファイルや構文エラー時の適切な例外送出

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `import ilisp; ilisp.eval("(+ 1 2 3)") == 6` が正常動作すること。
- [x] `evaluator = ilisp.Evaluator()` を用いて変数の連続評価・セッション状態維持（`evaluator.set`, `evaluator.get`, `evaluator.call`）ができること。
- [x] `load_ilisp_module("...")` により、Scheme の関数が `module.func_name(...)` として Python から直接呼び出せること。
- [x] `register_import_hook()` により `sys.meta_path` を介した透過的 `import` が正常動作し、`unregister_import_hook()` で安全に解除できること。
- [x] `tests/ilisp/test_interop.py` の全テストが 100% PASS すること。
- [x] 既存の chibi-scheme R7RS テストスイート（1229/1229 件 PASS）に 1 件のリグレッションも生じないこと。
- [x] 全品質ゲート（`make format`, `make static_analysis`, `make test`）をパスすること。


---
ID: 481
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] Python 相互運用の糖衣構文 (Clojure ライクな記法とドット参照) の実装 (ID: 481)

## 1. 概要 / Summary

ILISP から Python の関数やオブジェクトを呼び出す際、従来は `(py-call os 'getcwd)` や `(py-get resp 'status_code)`、あるいは `(import-python (os getcwd))` を用いる必要があった。しかし、データサイエンス、AI ワークフロー、セキュリティ自動化において Python オブジェクトやメソッドチェーンを頻繁に操作する場合、より簡潔で直感的かつ表現力の高い構文が不可欠である。

本 Issue では、Lisp / Clojure コミュニティで実証された **Clojure 風ドット構文**（`(.method obj arg ...)`、`(. obj method arg ...)`、`(.-attr obj)`）および **ドット記法シンボルの動的自動解決 (Auto-Desugaring)**（`os.getcwd`、`math.pi`、`obj.attr`）を導入し、ILISP における Python 相互運用の開発者体験（DX）と表現力を極限まで高める。

---

## 2. トレーサビリティ / Traceability

- 関連設計書: [DSN-31: ILISP R7RS コアアーキテクチャ包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) (第 4 節 Python 双方向ゼロコピー相互運用プロトコル)
- 仕様ドキュメント: [ilisp/docs/PYTHON_INTEROP.md](../../ilisp/docs/PYTHON_INTEROP.md) (第 3 節 ILISP から Python へのアクセス仕様)
- 関連 Issue: [Issue 479: (ilisp python) ライブラリの独立分離と import-python マクロの実装](closed/479-implement-import-python-macro-library.md)
- 関連 Issue: [Issue 480: Python 側からの ILISP 呼び出し API の実装](closed/480-implement-python-facing-ilisp-api-and-interop.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ilisp/reader.py](../../ilisp/reader.py): 先頭 `.` トークンの識別子化 (`(. obj ...)` を構文エラーにせず `Symbol(".")` としてパース)
- [x] [ilisp/evaluator.py](../../ilisp/evaluator.py): `eval_expr` における `(.method obj ...)`、`(.-attr obj)`、`(. obj ...)` の自動脱糖展開、および未束縛ドットシンボル（`mod.member`）の動的インポート解決
- [x] [ilisp/env.py](../../ilisp/env.py): コア環境への `.` プリミティブ定義
- [x] [ilisp/backend/py_codegen/compiler.py](../../ilisp/backend/py_codegen/compiler.py): Python AST トランスパイラ (`Backend A`) の `_expand_macros` および `_compile_expr` における Clojure 構文・ドットシンボルのサポート
- [x] [ilisp/stdlib/python.ilisp](../../ilisp/stdlib/python.ilisp): `.` 構文マクロ / ヘルパーの連携
- [x] [ilisp/module.py](../../ilisp/module.py): `(ilisp python)` 標準ライブラリからの `.` エクスポート
- [x] [ilisp/docs/PYTHON_INTEROP.md](../../ilisp/docs/PYTHON_INTEROP.md): Clojure 風ドット構文およびドット記法シンボルの詳細仕様・コード例の追記
- [x] [tests/ilisp/test_interop.py](../../tests/ilisp/test_interop.py) または [tests/ilisp/test_modules.py](../../tests/ilisp/test_modules.py): Clojure 記法・ドット参照の網羅的単体テスト

---

## 4. 脅威分析とセキュリティ設計 / Threat Model & Security Mitigations

1. **未束縛ドット記法シンボルによる意図しないモジュールロード**:
   - *脅威*: 悪意あるスクリプトが未検証のシンボル名を通じて意図しないネイティブ Python モジュールをロードするリスク。
   - *対策*: ドット分割された各識別子コンポーネントが Python 有効識別子 (`str.isidentifier()`) であることを検証。不正なパス走査文字（`/` や `\0` 等）を含むものは拒絶し、モジュール解決失敗時はクリーンな `NameError` を送出する。
2. **リーダー完全性と R7RS 互換性**:
   - *脅威*: `.` のトークナイズ変更により、標準 R7RS のドット対 `(a . b)` や不正なドット構文 `(a . b c)` の構文検証が破壊されるリスク。
   - *対策*: `.` をシンボルとして許容するのはリスト先頭位置 `(. ...)` またはアトム位置のみとし、後続位置での多重ドットや対表現エラーのチェックは厳格に保持する。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/481-implement-clojure-style-python-interop-syntax`

1. **S式リーダー (`ilisp/reader.py`) の拡張**:
   - `_read_list` において、リスト先頭の `.` (`not elements`) を `Symbol.intern(".")` として受け入れ可能にする。
   - `_read_atom` において、単独の `.` トークンを `Symbol.intern(".")` として生成する。

2. **ツリーウォーク評価器 (`ilisp/evaluator.py`) の脱糖フック実装**:
   - `(.-attr obj [opt-val])`:
     - 引数 1 個: `(py-get obj 'attr)` に脱糖。
     - 引数 2 個: `(py-set! obj 'attr val)` に脱糖。
   - `(.method obj arg ...)`:
     - 先頭が `.` で始まり `len > 1`、かつ `...` や `.-*` でない場合、`(py-call obj 'method arg ...)` に脱糖。
   - `(. obj spec arg ...)`:
     - `spec` が `-attr` シンボルの場合: `(py-get obj 'attr)` に脱糖。
     - `spec` が `method` シンボルの場合: `(py-call obj 'method arg ...)` に脱糖。
     - `spec` が `(method spec-arg ...)` リストの場合: `(py-call obj 'method spec-arg ... arg ...)` に脱糖。
   - **未束縛ドットシンボル自動解決 (`_resolve_dotted_symbol`)**:
     - 変数評価時に `.` を含むシンボルが未束縛の場合:
       1. 先頭識別子がローカル環境・親スコープに束縛されているか確認。束縛されていればそのオブジェクトから属性/キーを連続取得。
       2. 束縛されていない場合、モジュールプレフィックスを `importlib.import_module` でインポートし、残余の属性を連続取得。

3. **Backend A トランスパイラ (`ilisp/backend/py_codegen/compiler.py`) の同期**:
   - `_expand_macros` に Clojure 構文 (`.method`, `.-attr`, `.`) の脱糖処理を統合。
   - `_compile_expr` における未束縛ドットシンボルの Python AST 属性チェーン展開または動的解決。

4. **モジュールおよび標準ライブラリ (`ilisp/module.py`, `ilisp/env.py`) の更新**:
   - `base_env` に `.` プリミティブを登録。
   - `(ilisp python)` のエクスポート一覧に `.` を追加。

5. **テスト作成と品質ゲートの検証**:
   - `tests/ilisp/test_interop.py` に Clojure 記法・ドット参照・メソッドチェーン・パイプライン連携のテストクラスを追加。
   - `make check_format` および `make static_analysis`、全単体テスト (397+ tests) の完全合格。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `(.getcwd os)` がカレントディレクトリを返すこと。
- [x] `(.upper "hello")` が `"HELLO"` を返すこと。
- [x] `(.split "a,b,c" ",")` がリスト `("a" "b" "c")` を返すこと。
- [x] `(. os getcwd)` および `(. "hello" upper)` が動作すること。
- [x] `(.-status_code resp)` 等の属性アクセスが正常に動作すること。
- [x] `math.pi` が `3.14159...` を返し、`(math.sqrt 16)` が `4.0` を返すこと。
- [x] `(os.getcwd)` のようなドット記法シンボルの関数直接適用が動作すること。
- [x] `(->> "  hello  " .strip .upper)` のようなパイプライン連携が動作すること。
- [x] Backend A (`compile_ilisp`) でも同等の構文が正しく動作すること。
- [x] 関連する全テストが 100% PASS すること。
- [x] `make check_format` および `make static_analysis` がエラー 0 件で合格すること。

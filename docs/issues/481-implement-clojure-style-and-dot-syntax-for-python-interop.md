---
ID: 481
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Python 相互運用の糖衣構文 (Clojure ライクな記法とドット参照) の実装 (ID: 481)

## 1. 概要 / Summary

ILISP から Python の関数やオブジェクトを呼び出す際、現在は `(py-call os 'getcwd)` や `(py-get resp 'status_code)`、あるいは `(import-python (os getcwd))` を用いる必要がある。しかし、データサイエンスや AI ワークフローにおいて Python オブジェクトを頻繁に操作する場合、より簡潔で直感的な構文が求められる。

本 Issue では、Lisp / Clojure コミュニティで広く親しまれている **Clojure 風ドット構文**（`(.method obj arg ...)`、`(.-attr obj)`）および **ドット記法シンボルの自動解決**（`os.getcwd`）を導入し、Python 相互運用の開発者体験（DX）と表現力を劇的に向上させる。

---

## 2. トレーサビリティ / Traceability

- 関連設計書: [DSN-31: ILISP R7RS コアアーキテクチャ包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) (第 4 節 Python 双方向ゼロコピー相互運用プロトコル)
- 仕様ドキュメント: [ilisp/docs/PYTHON_INTEROP.md](../../ilisp/docs/PYTHON_INTEROP.md) (第 3 節 ILISP から Python へのアクセス仕様)
- 関連 Issue: [Issue 479: (ilisp python) ライブラリの独立分離と import-python マクロの実装](closed/479-implement-import-python-macro-library.md)
- 関連 Issue: [Issue 480: Python 側からの ILISP 呼び出し API の実装](480-implement-python-facing-ilisp-api-and-interop.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ilisp/stdlib/python.ilisp](../../ilisp/stdlib/python.ilisp): Clojure 風メソッド呼び出しマクロ `.` および属性アクセサ `.-` の定義とエクスポート
- [ ] [ilisp/evaluator.py](../../ilisp/evaluator.py) または [ilisp/syntax.py](../../ilisp/syntax.py): ドットを含むシンボル（`mod.attr`）の自動脱糖展開フック
- [ ] [ilisp/module.py](../../ilisp/module.py): `(ilisp python)` のエクスポートシンボル更新
- [ ] [ilisp/docs/PYTHON_INTEROP.md](../../ilisp/docs/PYTHON_INTEROP.md): 糖衣構文ドキュメントの追記
- [ ] [tests/ilisp/test_modules.py](../../tests/ilisp/test_modules.py) または新設テスト: Clojure 記法・ドット参照の単体テスト

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/481-implement-clojure-style-python-interop-syntax`

1. **Clojure 風メソッド呼び出し構文 (`.`) の導入**:
   - `(.method obj arg ...)` 形式の構文マクロ:
     ```scheme
     (.getcwd os)             ;; => (py-call os 'getcwd)
     (.split text ",")        ;; => (py-call text 'split ",")
     ```
   - 第一引数がピリオドから始まるシンボル `(.method ...)` の場合、先頭の `.` を除去してメソッド名とし、第二引数のオブジェクトに対して `py-call` をディスパッチ。

2. **Clojure 風フィールド／属性参照構文 (`.-`) の導入**:
   - `(.-attr obj)` 形式の構文マクロ:
     ```scheme
     (.-status_code resp)     ;; => (py-get resp 'status_code)
     (.-shape tensor)         ;; => (py-get tensor 'shape)
     ```

3. **ドット記法シンボルの自動解決 (Auto-Desugaring)**:
   - 式中のシンボルが `mod.member`（例: `os.getcwd`, `math.pi`）を含み、かつ未束縛である場合、モジュールインポートとプロパティ取得 `(py-get (py-import 'mod) 'member)` へ自動脱糖。

4. **品質ゲートとテスト**:
   - Python ネイティブオブジェクト（`str`, `dict`, `os`, `math` 等）を用いた網羅的テスト。
   - `make check_format` および `make static_analysis` のパス。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `(.getcwd os)` がカレントディレクトリを返すこと。
- [ ] `(.upper "hello")` が `"HELLO"` を返すこと。
- [ ] `(.-status_code resp)` 等の属性アクセスが正常に動作すること。
- [ ] `(os.getcwd)` または `math.pi` のようなドット記法シンボル参照が解決できること。
- [ ] 関連する全テストが 100% PASS すること。
- [ ] `make check_format` および `make static_analysis` がエラー 0 件で合格すること。

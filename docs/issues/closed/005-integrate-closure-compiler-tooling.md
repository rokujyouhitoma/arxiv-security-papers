---
ID: 005
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] yuzora 準拠の Google Closure Compiler ツール配置およびビルド設定統合 (ID: 005)

## 1. 概要 / Summary
`yuzora` リポジトリの Google Closure Compiler 運用方式をテーラリングし、`tools/closure-compiler/` 配下へのコンパイラ JAR 配置、外部 API 保護定義ファイル (`site/externs.js`) の作成、および `Makefile` への JavaScript バンドル・最適化ビルドターゲット (`make build_js`) を取り込みます。

---

## 2. トレーサビリティ / Traceability
- **参考リポジトリ**: `yuzora` (`tools/closure-compiler/`, `Makefile`, `externs.js`)
- **設計書**: `docs/designs/DSN-01-high_level_design.md`, `docs/designs/DSN-02-low_level_design.md`

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [`tools/closure-compiler/setup_compiler.py`](../../tools/closure-compiler/setup_compiler.py): コンパイラ JAR 自動取得・配置スクリプト
- [x] [`site/externs.js`](../../site/externs.js): Closure Compiler 用型・外部識別子保護定義
- [x] [`Makefile`](../../Makefile): `JS_SRCS`, `JS_OUT`, `CLOSURE_COMPILER`, `build_js` ターゲット追加
- [x] [`site/index.html`](../../site/index.html): 生産環境用 `app-min.js` 読み込み対応

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/005-integrate-closure-compiler-tooling`

1. **`tools/closure-compiler/` ディレクトリと `setup_compiler.py` の構築**:
   - `closure-compiler-v20240317.jar` を確実にダウンロード・配置する Python 自動化スクリプトを作成。
2. **`site/externs.js` の作成**:
   - `mermaid`, `MarkdownCompiler`, `fetch`, `history`, `performance` などのグローバル変数の最小化（Rename）を防止する宣言を記述。
3. **`Makefile` ターゲット追加と動作検証**:
   - `make build_js` コマンドを追加し、`site/app-min.js` の圧縮・ビルドを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `tools/closure-compiler/` に JAR ファイルが正常に配置されること。
- [x] `make build_js` により `site/app-min.js` が無エラーで正常生成されること。
- [x] `make py_compile` および `make test` が 100% PASS すること。

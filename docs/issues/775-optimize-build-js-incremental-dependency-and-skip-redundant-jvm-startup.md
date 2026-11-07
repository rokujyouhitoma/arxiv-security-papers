---
ID: 775
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Root Makefile の build_js ターゲットにおける増分ビルド依存導入と未変更時の Closure Compiler (JVM) 起動スキップ (ID: 775)

## 1. 概要 / Summary

ルート [Makefile](../../Makefile) において、`make test`, `make check`, `make verify_quality`, `make build` を実行するたびに `.PHONY: build_js` および `.PHONY: build_cti_query_parser` が毎回無条件に実行され、フロントエンド JS ソース（`JS_SRCS`）や `tools/grammars/graph_query.peg` に一切変更がなくても毎回 PEG JS コンパイラと Closure Compiler（JVM 起動）が走るボトルネックを解消する。
成果物ファイル（`src/web/site/app-min.js` および `src/web/site/js/frameworks/cti-query-parser.js`）に対する正確なファイル依存関係を導入し、入力ファイル未変更時は再コンパイルをO(1)でスキップできるようにする。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [Makefile](../../Makefile) (`build_js`, `build_cti_query_parser`, `test` ターゲット)
  - [scripts/compile_frontend.py](../../scripts/compile_frontend.py)
- 依存関係:
  - 関連 Issue: [Issue #773](773-optimize-makefile-py-compile-batch-and-parallel-execution.md), [Issue #774](774-optimize-compile-grammars-incremental-build-and-batch-formatting.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [Makefile](../../Makefile)
- [ ] [scripts/compile_frontend.py](../../scripts/compile_frontend.py)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/775-optimize-build-js-incremental-dependency-and-skip-redundant-jvm-startup`

1. **`cti-query-parser.js` と `$(JS_OUT)` (`src/web/site/app-min.js`) のファイルターゲット化**:
   - `src/web/site/js/frameworks/cti-query-parser.js` の依存元に `tools/grammars/graph_query.peg` を指定し、文法未変更時は再生成をスキップする。
   - `$(JS_OUT)` の依存元に `$(JS_SRCS)`・`cti-query-parser.js`・`scripts/compile_frontend.py` を指定し、JS ソース未変更時は Closure Compiler の起動をスキップする（または `compile_frontend.py` 側でも入力ハッシュ／タイムスタンプ判定をサポートする）。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] JS ソースおよび `graph_query.peg` 未変更時に `make test` / `make build_js` が冗長な Closure Compiler 再実行をスキップして高速に完了すること。
- [ ] JS ソース変更時には確実に `src/web/site/app-min.js` が再ビルドされること。
- [ ] `make check` / `make verify_quality` がエラー 0 件で PASS すること。


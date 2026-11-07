---
ID: 774
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Root Makefile の compile_grammars ターゲットにおける PEG 増分ビルド化とフォーマッタ一括実行による高速化 (ID: 774)

## 1. 概要 / Summary

ルート [Makefile](../../Makefile) の `compile_grammars` ターゲットにおいて、12個の `.peg` 文法ファイルに対して `compile_peg.py`・`isort`・`black` を直列で計36回プロセス起動しており、未変更の `.peg` ファイルも毎回無条件に再コンパイルしている問題を解消する。
Make のファイルタイムスタンプ依存ルールによる増分ビルド化（変更された `.peg` のみ再コンパイル、かつ `make -j` 並列実行可能化）および生成ファイルに対する `isort` / `black` の1回一括実行へ刷新し、PEG パーサ群のコンパイル速度を大幅に向上させる。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [Makefile](../../Makefile) (`compile_grammars` ターゲット)
  - [tools/peg/compile_peg.py](../../tools/peg/compile_peg.py)
- 依存関係:
  - 関連 Issue: [Issue #773](773-optimize-makefile-py-compile-batch-and-parallel-execution.md), [Issue #775](775-optimize-build-js-incremental-dependency-and-skip-redundant-jvm-startup.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [Makefile](../../Makefile)
- [ ] [tools/peg/compile_peg.py](../../tools/peg/compile_peg.py)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/774-optimize-compile-grammars-incremental-build-and-batch-formatting`

1. **生成パーサファイルごとの Make ターゲット定義と増分ビルド化**:
   - 各生成パーサ（`generated_*_parser.py`）が対応する `.peg` ファイルと `tools/peg/compile_peg.py` に依存するターゲットとして定義し、未変更時の再コンパイルをスキップかつ `make -j` で並列生成可能にする。
2. **`isort` / `black` のバッチ適用**:
   - 1ファイルごとに `isort` と `black` を計24回起動する代わりに、生成されたパーサファイル群に対して1回で一括フォーマットを実行する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `.peg` ファイル未変更時に2回目以降の増分ターゲット実行が即座に完了すること。
- [ ] 全12個の `.peg` 文法のフル再ビルド時も `isort` / `black` の一括化・並列化により従来比で大幅に高速化されること。
- [ ] `make verify_peg_bootstrap` および `make verify_quality` がエラー 0 件で PASS すること。


---
ID: 774
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
完了日: 2026-11-08
---

# [FEAT/ENH] Root Makefile の compile_grammars ターゲットにおける PEG 増分ビルド化とフォーマッタ一括実行による高速化 (ID: 774)

## 1. 概要 / Summary

ルート [Makefile](../../../Makefile) の `compile_grammars` ターゲットにおいて、従来 12 個の `.peg` 文法ファイルに対して `compile_peg.py`・`isort`・`black` を直列で計 36 回プロセス起動しており、未変更の `.peg` ファイルであっても毎回無条件に全件再コンパイルを行っていたボトルネックを解消した。

従来は文法ファイルが一切変更されていない状態でも毎回 **約 7.1 秒**（real 7.084s, user 6.584s）の実行時間を消費していた。

本改修により、GNU Make のファイルタイムスタンプ依存関係を活用した **個別ファイルターゲットによる増分ビルド（Incremental Build）** を導入した。未変更時はコンパイルを完全にスキップして **0.035 秒（約 200 倍以上高速化）** で即座に終了するようになり、さらに文法変更時は `make -j` によるマルチコア並列コンパイル（12 ファイル全件再ビルドで **2.349 秒、約 3 倍高速化**）、および生成ファイル群に対する **`isort` / `black` の 1 回一括バッチフォーマット** を実現し、ビルド時間と開発体験（DX）を抜本的に改善した。

---

## 2. 現状のボトルネック分析と実測値 / Bottleneck Analysis & Benchmarks

### 2.1 改修前実装 (`Makefile` L101-139)
改修前の `compile_grammars` は単一の `.PHONY` ターゲット内に 12 文法分のコンパイルおよび個別フォーマッタ呼び出し（36 行のシェルコマンド）が直列にベタ書きされていた：

```makefile
.PHONY: compile_grammars
compile_grammars: activate ## Compile .peg grammar specifications to standalone Python parsers
	PYTHONPATH=src ${VENV_PYTHON} tools/peg/compile_peg.py tools/grammars/peg_meta.peg -o src/core/peg/compiler/generated_meta_parser.py
	${VENV_BIN}/isort src/core/peg/compiler/generated_meta_parser.py
	${VENV_BIN}/black -q src/core/peg/compiler/generated_meta_parser.py
	# ... 計 36 コマンドが毎回無条件に直列実行 ...
```

### 2.2 ボトルネックの構造
1. **タイムスタンプ依存の不在と無条件全件再実行**:
   - `compile_grammars` が `.PHONY` ターゲットとして定義されており、生成先ファイル（`generated_*_parser.py`）と元文法（`*.peg`）のタイムスタンプ比較が行われないため、未変更時でも 12 個すべてを毎回最初から再生成していた。
2. **フォーマッタプロセスの過剰起動 ($O(N)$ fork/exec)**:
   - 1 ファイル生成されるたびに `isort` と `black` を個別に起動（12 × 2 = 24 回の Python プロセス起動）。
   - 実測として、全 12 ファイルを一括で `isort` および `black` に渡した場合は合計 **約 0.25 秒** で完了するのに対し、個別起動ではフォーマッタだけで **約 3.0 秒** を消費していた。
3. **並列ビルド不可**:
   - 単一のターゲットレシピ内に直列記述されていたため、`make -j` を指定しても並列実行されず、CPU リソースを活かせなかった。

### 2.3 実測ベンチマーク比較 (12 Grammars)
| 方式 | 実行コマンド | 所要時間 (real) | 高速化倍率 | 特徴 |
| :--- | :--- | :---: | :---: | :--- |
| **改修前 (Baseline)** | `make compile_grammars` (直列 36 回実行) | **7.084s** | 1.0x (基準) | 未変更時も無条件全再生成、並列不可 |
| **改修後 (ホット・未変更時)** | `make compile_grammars` (増分スキップ) | **0.035s** | **約 202x** | タイムスタンプ判定により全スキップ、即座に終了 |
| **改修後 (単一文法変更時)** | `touch tools/grammars/turtle.peg && make compile_grammars` | **0.989s** | **約 7.2x** | 該当ファイルのみコンパイル、フォーマッタ 1 回実行 |
| **改修後 (12文法全件並列)** | `touch tools/grammars/*.peg && make -j 8 compile_grammars` | **2.349s** | **約 3.0x** | 8 コア並列コンパイル + 1 回一括バッチフォーマット |

---

## 3. トレーサビリティ / Traceability

- 関連資料・設定:
  - [Makefile](../../../Makefile) (`compile_grammars` L101-160, `verify_peg_bootstrap`)
  - [tools/peg/compile_peg.py](../../../tools/peg/compile_peg.py) (PEG コンパイラ CLI エントリポイント)
  - [tests/core/peg/compiler/test_bootstrap.py](../../../tests/core/peg/compiler/test_bootstrap.py) (PEG AOT コンパイラ自己ホスト不動点検証)
  - [docs/manuals/DEV-01-developer_manual.md](../../manuals/DEV-01-developer_manual.md) (ビルドターゲット定義)
- 依存関係:
  - 関連 Issue: [Issue #773](773-optimize-makefile-py-compile-batch-and-parallel-execution.md) (py_compile 並列バッチ化・完了済み)
  - 関連 Issue: [Issue #775](../775-optimize-build-js-incremental-dependency-and-skip-redundant-jvm-startup.md) (Closure Compiler 増分ビルド化)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [Makefile](../../../Makefile) (`compile_grammars` ターゲットおよび各生成パーサのファイル依存ルール定義、`clean` ターゲット更新)
- [x] [docs/issues/README.md](../README.md) (Issue 台帳のステータス更新)

---

## 5. セキュリティ・堅牢性設計 / Security & Robustness Considerations

1. **SQL 系パーサの `--no-aot` オプション完全維持**:
   - `sql_dql.peg`, `sql_dml.peg`, `sql_ddl.peg`, `sql_admin.peg` の 4 つは再帰的構文木生成のため意図的に `--no-aot`（コンビネータランタイム版）が指定されている。
   - ルール定義時にもこのフラグを確実に維持し、AST 互換性および既存 SQL クエリハンドラの動作破壊を防止した。
2. **自己ホスト循環依存の安全性 (`verify_peg_bootstrap`)**:
   - `peg_meta.peg` は自身をパースするメタ文法であるため、生成された `generated_meta_parser.py` の動作不動点が `tests/core/peg/compiler/test_bootstrap.py` により厳格に保証されている。改修後もこのテストが 100% PASS することを確認済み。
   - `PEG_COMPILER_DEPS` 定義時、`generated_meta_parser.py` が自身に依存して Make の Circular Dependency 警告が発生しないよう `-not -name "generated_*"` で除外設計。
3. **アトミックビルドとマーカーファイル (`.peg_needs_format`) の状態管理**:
   - 増分ビルド時に「いずれかの文法が再生成された場合のみフォーマッタを実行する」ためのマーカーファイル `.peg_needs_format` を安全に作成・消費（クリーンアップ）し、未変更時はフォーマッタ起動すらスキップして完全 O(1) 終了を実現。
   - `make clean` にも `.peg_needs_format` 削除を組み込みクリーン性を担保。

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/774-optimize-compile-grammars-incremental-build-and-batch-formatting`

### Step 1: `Makefile` の変数およびファイルターゲットルールの定義
`Makefile` に以下の変数と各パーサのターゲット依存関係を定義：

```makefile
PEG_COMPILER = tools/peg/compile_peg.py
PEG_COMPILER_DEPS = $(PEG_COMPILER) $(shell find src/core/peg -type f -name "*.py" -not -name "generated_*" 2>/dev/null)

PEG_GENERATED_SRCS = \
	src/core/peg/compiler/generated_meta_parser.py \
	src/ontology/turtle/generated_parser.py \
	src/search/query/generated_search_query_parser.py \
	src/graph/generated_graph_query_parser.py \
	src/database/sql/generated_sql_expr_parser.py \
	src/database/sql/generated_sql_dql_parser.py \
	src/database/sql/generated_sql_dml_parser.py \
	src/database/sql/generated_sql_ddl_parser.py \
	src/database/sql/generated_sql_admin_parser.py \
	src/pipeline/transformer/generated_yaml_frontmatter_parser.py \
	src/pdf_engine/bibtex/generated_parser.py \
	src/pdf_engine/cmap/generated_parser.py

# AOT 標準ターゲット
src/core/peg/compiler/generated_meta_parser.py: tools/grammars/peg_meta.peg $(PEG_COMPILER_DEPS)
	PYTHONPATH=src ${VENV_PYTHON} $(PEG_COMPILER) $< -o $@ && touch .peg_needs_format

# ... 他文法も同様に定義 ...

# --no-aot 指定ターゲット
src/database/sql/generated_sql_dql_parser.py: tools/grammars/sql_dql.peg $(PEG_COMPILER_DEPS)
	PYTHONPATH=src ${VENV_PYTHON} $(PEG_COMPILER) $< --no-aot -o $@ && touch .peg_needs_format
```

### Step 2: `compile_grammars` 統合ターゲットと一括フォーマット
```makefile
.PHONY: compile_grammars
compile_grammars: activate $(PEG_GENERATED_SRCS) ## Compile .peg grammar specifications to standalone Python parsers (incremental build)
	@if [ -f .peg_needs_format ]; then \
		rm -f .peg_needs_format; \
		${VENV_BIN}/isort $(PEG_GENERATED_SRCS); \
		${VENV_BIN}/black -q $(PEG_GENERATED_SRCS); \
	fi
```

### Step 3: 動作検証とベンチマーク実測
- `make compile_grammars`: 未変更時 0.035 秒で完了確認。
- `touch tools/grammars/turtle.peg && make compile_grammars`: 単一文法再ビルド 0.989 秒で完了確認。
- `touch tools/grammars/*.peg && make -j 8 compile_grammars`: 全件マルチコア並列リビルド 2.349 秒で完了確認。
- `make verify_peg_bootstrap`: 4 テスト 100% PASS。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] 12 個の PEG 生成パーサがファイル依存関係ルール（`generated_*_parser.py: *.peg`）として定義されていること。
- [x] SQL 系 4 文法（`sql_dql`, `sql_dml`, `sql_ddl`, `sql_admin`）の `--no-aot` オプションが完全維持されていること。
- [x] 未変更時の `make compile_grammars` が増分スキップにより 0.05 秒未満（実測 0.035s）で即座に完了すること（従来比約 202 倍高速化）。
- [x] 文法更新時のみ `isort` と `black` が全生成対象に対して 1 回一括実行され、個別 24 回のプロセス起動が撤去されていること。
- [x] `make -j` による複数文法のマルチコア並列生成が正常に動作すること（実測 2.349s、約 3 倍高速化）。
- [x] `make verify_peg_bootstrap`（自己ホスト不動点テスト）が 100% PASS すること。
- [x] `make check_format` および `make static_analysis` がエラー 0 件で PASS すること。
- [x] ドキュメント内リンク検証において絶対パスが 0 件であること。

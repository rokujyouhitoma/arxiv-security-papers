---
ID: 775
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
完了日: 2026-11-08
---

# [FEAT/ENH] Root Makefile の build_js ターゲットにおける増分ビルド依存導入と未変更時の Closure Compiler (JVM) 起動スキップ (ID: 775)

## 1. 概要 / Summary

ルート [Makefile](../../../Makefile) において、`make test`, `make check`, `make verify_quality`, `make build` を実行するたびに `.PHONY: build_js` および `.PHONY: build_cti_query_parser` が毎回無条件に実行され、フロントエンド JavaScript ソースや `tools/grammars/graph_query.peg` に一切変更がなくても毎回 PEG JS パーサ生成と Google Closure Compiler（JVM 起動）が走り、**約 13 秒**（実測: real 12.856s, user 39.442s, sys 1.590s）ものビルド時間を浪費していたボトルネックを解消した。

本改修により、GNU Make 4.3 のグループターゲット構文（`&:`）およびファイルタイムスタンプ依存関係を導入し、成果物ファイル（`src/web/site/js/frameworks/cti-query-parser.js`, `src/web/site/app-min.js`, `src/web/site/dashboard-min.js`）に対する完全な増分ビルド（Incremental Build）を確立した。
これにより、入力ファイル未変更時は JVM および Python の再実行をスキップして **0.05〜0.07 秒（約 180〜250 倍高速化）** で即座に終了するようになり、さらに [scripts/compile_frontend.py](../../../scripts/compile_frontend.py) 単体でも mtime 判定と `--force` オプションをサポートして開発効率を飛躍的に高めた。

---

## 2. 現状のボトルネック分析と実測値 / Bottleneck Analysis & Benchmarks

### 2.1 改修前実装 (`Makefile` L163-175)
```makefile
.PHONY: build_cti_query_parser
build_cti_query_parser: activate ## Build client-side CTI query PEG parser for web dashboard
	PYTHONPATH=src ${VENV_PYTHON} -m core.peg.compiler tools/grammars/graph_query.peg -o src/web/site/js/frameworks/cti-query-parser.js --target js --ast-only --no-runtime --class-name CTIQuery

.PHONY: build_js
build_js: activate build_cti_query_parser ## Build minified JS bundles using pure Python pipeline & Closure Compiler
	${VENV_PYTHON} tools/closure-compiler/setup_compiler.py
	${VENV_PYTHON} scripts/compile_frontend.py

.PHONY: test
test: build_js pytest ## pytest
```

### 2.2 ボトルネックの構造
1. **JVM 起動と重複コンパイルの多重オーバーヘッド**:
   - `build_js` は `app-min.js`（29 ファイル）と `dashboard-min.js`（24 ファイル）の 2 つのバンドルを Closure Compiler（Java プロセス）で別々にコンパイル（計 2 回 JVM 起動）。
   - Java VM の起動・JIT ウォームアップ・AST 型解析・SIMPLE_OPTIMIZATIONS 圧縮に合計 **約 12.9 秒** を要していた。
2. **すべてのテスト・品質ゲートターゲットへの波及**:
   - `test`（pytest 実行）が `build_js` に依存していたため、単体テストを 1 つ実行するだけでも毎回 13 秒の JVM 待ちが発生していた。
   - `make check`, `make verify_quality`, `make build` にも連鎖し、開発サイクル全体の最大の遅延要因となっていた。
3. **`clean` ターゲットの不備**:
   - `Makefile` の `clean` が `${JS_OUT}`（`app-min.js`）のみを削除し、`dashboard-min.js` が除外されていた。

### 2.3 実測ベンチマーク比較
| 方式 | 実行コマンド | 所要時間 (real) | 高速化倍率 | 特徴 |
| :--- | :--- | :---: | :---: | :--- |
| **改修前 (Baseline)** | `make build_js` (毎回無条件再実行) | **12.856s** | 1.0x (基準) | 未変更時も 2 回 JVM 起動、直列待機 |
| **改修後 (未変更時増分スキップ)** | `make build_js` (ファイル依存判定) | **0.070s** | **約 183x** | 入力未変更時は Make が即座にスキップ |
| **改修後 (文法変更時)** | `touch tools/grammars/graph_query.peg && make build_js` | **12.9s** | 1.0x | PEG JS パーサのみ再生成し、バンドル再コンパイル |

---

## 3. トレーサビリティ / Traceability

- 関連資料・設定:
  - [Makefile](../../../Makefile) (`build_js`, `build_cti_query_parser`, `JS_SRCS`, `JS_OUT`, `JS_BUNDLES`, `clean`)
  - [scripts/compile_frontend.py](../../../scripts/compile_frontend.py) (フロントエンドコンパイルドライバ)
  - [tools/closure-compiler/setup_compiler.py](../../../tools/closure-compiler/setup_compiler.py)
  - [tests/web/test_frontend_frameworks.py](../../../tests/web/test_frontend_frameworks.py) (フレームワーク順序および `JS_SRCS` 整合性テスト)
  - [docs/manuals/DEV-01-developer_manual.md](../../manuals/DEV-01-developer_manual.md) (フロントエンドビルド手順)
- 依存関係:
  - 関連 Issue: [Issue #773](773-optimize-makefile-py-compile-batch-and-parallel-execution.md) (py_compile 並列バッチ化・完了済み)
  - 関連 Issue: [Issue #774](774-optimize-compile-grammars-incremental-build-and-batch-formatting.md) (compile_grammars 増分ビルド化・完了済み)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [Makefile](../../../Makefile) (`JS_BUNDLES`, `JS_COMPILER_DEPS`, `build_cti_query_parser`, `build_js`, `clean` ターゲットの更新)
- [x] [scripts/compile_frontend.py](../../../scripts/compile_frontend.py) (タイムスタンプ判定および `--force` CLI オプション追加)
- [x] [tests/test_bare_metal_ulisp.py](../../../tests/test_bare_metal_ulisp.py) (32GB アリーナ mtime / サイズ検証の同期)
- [x] [docs/issues/README.md](../README.md) (Issue 台帳のステータス更新)

---

## 5. セキュリティ・堅牢性設計 / Security & Robustness Considerations

1. **`test_frontend_frameworks.py` の静的解析アサーション完全準拠**:
   - `tests/web/test_frontend_frameworks.py` 内の `test_makefile_includes_frameworks_in_js_srcs()` は、`Makefile` 内の `JS_SRCS` 変数テキストを正規表現・文字列検索で解析し、全 19 個のフレームワークファイルが `site/app.js` の前に定義されていることを厳格に検証している。
   - そのため、`JS_SRCS` の変数名およびフレームワーク一覧の並び順定義をそのまま維持し、テスト破壊を防止した。
2. **GNU Make 4.3 グループターゲット構文 (`&:`) によるアトミック性**:
   - `compile_frontend.py` は 1 回のスクリプト実行で `app-min.js` と `dashboard-min.js` の両方を生成する。
   - Make 4.3 のグループターゲット `app-min.js dashboard-min.js &:` を用いることで、Make が 2 つの成果物に対して別々にレシピを多重実行（重複ビルド）する事態を完全に防止。
3. **依存関係の完全性**:
   - `graph_query.peg` 変更時は `cti-query-parser.js` が再生成され、タイムスタンプ更新により自動的に `app-min.js` と `dashboard-min.js` が再コンパイルされるカスケード依存を保証。
   - `externs.js` や `compile_frontend.py` 自体の変更時も確実に再コンパイルが走るように依存リストに組み込み。
4. **`--force` フラグによる決定論的クリーンビルド保証**:
   - タイムスタンプのずれや CI 環境でのアーティファクト復元時にも、`--force` フラグまたは `make clean && make build_js` により常に確実にクリーンリビルドが行えるフェイルセーフを設けた。

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/775-optimize-build-js-incremental-dependency-and-skip-redundant-jvm-startup`

### Step 1: `scripts/compile_frontend.py` の増分判定・`--force` オプション追加
1. `is_bundle_up_to_date(src_paths, dest_path, extra_deps)` 関数を実装。
2. `compile_bundle(...)` に `force: bool = False` 引数を追加。
3. `argparse` に `--force`, `-f` 引数を追加。

### Step 2: `Makefile` のファイル依存ルール改修
```makefile
JS_OUT = src/web/site/app-min.js
JS_DASHBOARD_OUT = src/web/site/dashboard-min.js
JS_BUNDLES = $(JS_OUT) $(JS_DASHBOARD_OUT)
ALL_JS_SRCS = $(JS_SRCS) src/web/site/js/dashboard.js $(shell find src/web/site/js -type f -name "*.js" 2>/dev/null | sort -u)
JS_COMPILER_DEPS = scripts/compile_frontend.py tools/closure-compiler/setup_compiler.py src/web/site/externs.js

src/web/site/js/frameworks/cti-query-parser.js: tools/grammars/graph_query.peg $(PEG_COMPILER_DEPS)
	PYTHONPATH=src ${VENV_PYTHON} -m core.peg.compiler $< -o $@ --target js --ast-only --no-runtime --class-name CTIQuery

.PHONY: build_cti_query_parser
build_cti_query_parser: activate src/web/site/js/frameworks/cti-query-parser.js ## Build client-side CTI query PEG parser (incremental)

$(JS_BUNDLES) &: $(ALL_JS_SRCS) $(JS_COMPILER_DEPS) src/web/site/js/frameworks/cti-query-parser.js | activate
	${VENV_PYTHON} tools/closure-compiler/setup_compiler.py
	${VENV_PYTHON} scripts/compile_frontend.py

.PHONY: build_js
build_js: activate build_cti_query_parser $(JS_BUNDLES) ## Build minified JS bundles using pure Python pipeline & Closure Compiler (incremental)
```

- `clean` レシピ内の `${JS_OUT}` を `${JS_BUNDLES}` に更新。

### Step 3: 動作検証とベンチマーク実測
- `make build_js`: 未変更時 0.070 秒で完了確認。
- `touch tools/grammars/graph_query.peg && make build_js`: カスケード再生成確認。
- `pytest tests/web/test_frontend_frameworks.py`: 15 テスト全件 PASS。
- `pytest tests/test_bare_metal_ulisp.py`: 10 テスト全件 PASS。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `src/web/site/js/frameworks/cti-query-parser.js` が `graph_query.peg` に対するファイル依存ターゲットとして定義されていること。
- [x] `src/web/site/app-min.js` および `src/web/site/dashboard-min.js` がグループターゲット（`&:`）として Make ファイル依存関係に組み込まれていること。
- [x] `scripts/compile_frontend.py` がタイムスタンプ判定による増分スキップおよび `--force` オプションに対応していること。
- [x] 未変更時の `make build_js` が 0.05〜0.07 秒（実測 0.070s、従来比約 183 倍高速化）で即座に完了すること。
- [x] JS ソースまたは PEG 文法変更時に確実に自動再ビルドが実行されること。
- [x] `make clean` で両バンドル（`app-min.js`, `dashboard-min.js`）が確実に削除されること。
- [x] `tests/web/test_frontend_frameworks.py` を含む全テストが 100% PASS すること。
- [x] `make check_format` および `make static_analysis` がエラー 0 件で PASS すること。
- [x] ドキュメント内リンク検証において絶対パスが 0 件であること。

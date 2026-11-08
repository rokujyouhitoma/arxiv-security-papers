---
ID: 773
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-11-08
---

# [FEAT/ENH] Root Makefile の py_compile ターゲットにおけるサブプロセス逐次起動ループ廃止と一括・並列コンパイル化 (ID: 773)

## 1. 概要 / Summary

ルート [Makefile](../../../Makefile) の `py_compile` ターゲット（およびそれを呼び出す `static_analysis`, `check`, `verify_quality`, `build`, Git pre-commit フック, CI ワークフロー）において、従来シェル `for` ループで `PYTHON_SRCS`（`src`, `ilisp`, `alisp` 配下の全 660 個の `.py` ファイル）に対して **1ファイルずつ Python インタプリタプロセスを新規起動** していた致命的なボトルネックを解消した。

従来は `make py_compile` 1回の実行に **約 24.5 秒**（real 24.478s, user 20.610s, sys 3.789s）を要しており、Git コミット時（pre-commit フック）や開発中の品質検証のたびに作業リズムを阻害していた。

本改修により、Python 標準モジュール `compileall` のマルチコア並列コンパイル（`-j 0`）およびバッチ実行への全面刷新を行い、Python プロセスの生成コスト（$O(N)$ 回の fork/exec）を完全排除した。これにより `make py_compile` は **ホットキャッシュ時 0.07 秒（約 350 倍高速化）、コールド時 1.2 秒（約 20 倍高速化）** で完了するようになり、さらに複数ファイルのエラー一括報告による開発体験（DX）を飛躍的に向上させた。

---

## 2. 現状のボトルネック分析と実測値 / Bottleneck Analysis & Benchmarks

### 2.1 改修前実装 (`Makefile` L95-99)
```makefile
.PHONY: py_compile
py_compile: activate ## py_compile syntax check for all python sources
	@for py in $(PYTHON_SRCS); do \
		${VENV_PYTHON} -m py_compile $$py || exit 1; \
	done
```

### 2.2 ボトルネックの構造
1. **プロセス起動オーバーヘッドの $O(N)$ 蓄積**:
   - `$(PYTHON_SRCS)` に含まれる Python ファイル数は現時点で **660 ファイル**。
   - 1 ファイルごとに `${VENV_PYTHON}`（CPython 3.14 インタプリタ）を fork/exec 起動するため、インタプリタの初期化・モジュール検索パス解決・終了処理が 660 回直列に繰り返されていた。
2. **エラー検出の直列停止（フェイルファストの弊害）**:
   - `|| exit 1` で最初の構文エラーで停止するため、複数ファイルに構文エラーが存在する場合、修正して再実行するたびに 24 秒待たされる「モグラ叩き」状態が発生していた。
3. **CPU リソースの遊休**:
   - マルチコア環境であっても常に 1 コアしか使用されず、並列性能が全く活かされていなかった。

### 2.3 実測ベンチマーク比較 (660 Python Files)
| 方式 | 実行コマンド | 所要時間 (real) | 高速化倍率 | 特徴 |
| :--- | :--- | :---: | :---: | :--- |
| **改修前 (Baseline)** | `for py in ...; do python -m py_compile $$py; done` | **24.478s** | 1.0x (基準) | 660回プロセス起動、直列実行、最初のエラーで即停止 |
| 候補 A (py_compile バッチ) | `python -m py_compile $(PYTHON_SRCS)` | 1.187s | **約 20.6x** | 1回プロセス起動、直列コンパイル、最初のエラーで即停止 |
| **改修後 (コールド時)** | `python -m compileall -q -j 0 $(PYTHON_SRCS)` (`make clean` 直後) | 1.269s | **約 19.3x** | 全コア並列コンパイル、全エラー一括報告 |
| **改修後 (ホット時)** | `python -m compileall -q -j 0 $(PYTHON_SRCS)` (通常時) | **0.073s** | **約 335x** | 全コア並列、タイムスタンプ増分スキップ、全エラー一括報告 |

---

## 3. トレーサビリティ / Traceability

- 関連資料・設定:
  - [Makefile](../../../Makefile) (`PYTHON_SRCS` L14, `py_compile` L95-99, `static_analysis` L93, `verify_quality` L183, `build` L186)
  - [.agents/AGENTS.md](../../../.agents/AGENTS.md) (第 2.5 節: Diagnostic Auto-Fix & Makefile Quality Enforcement)
  - [.agents/hooks.json](../../../.agents/hooks.json) (Pre-task hook: `make py_compile`)
  - [.github/workflows/ci.yml](../../../.github/workflows/ci.yml) (Quality Gate 2: Static Analysis)
  - [docs/manuals/DEV-01-developer_manual.md](../../manuals/DEV-01-developer_manual.md) (第 4.3 節: Python 構文コンパイル検査)
  - [.agents/skills/verify-quality-gates/SKILL.md](../../../.agents/skills/verify-quality-gates/SKILL.md) (Gate 1: `make py_compile`)
- 依存関係:
  - 関連 Issue: [Issue #774](../774-optimize-compile-grammars-incremental-build-and-batch-formatting.md) (PEG 増分ビルドとフォーマッタ一括化)
  - 関連 Issue: [Issue #775](../775-optimize-build-js-incremental-dependency-and-skip-redundant-jvm-startup.md) (Closure Compiler 増分ビルド化)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [Makefile](../../../Makefile) (`py_compile` ターゲットの更新)
- [x] [docs/issues/README.md](../README.md) (Issue 台帳のステータス更新)

---

## 5. セキュリティ・堅牢性設計 / Security & Robustness Considerations

1. **コマンドライン引数長上限 (`ARG_MAX`) の安全性**:
   - `PYTHON_SRCS` の展開文字列長は 660 ファイルで約 25 KB。Linux の `ARG_MAX`（通常 2,097,152 バイト = 2 MB）に対してわずか 1.2% に過ぎず、引数オーバーフロー（`Argument list too long`）のリスクは皆無。
2. **引数空文字時の暴走防止ガード**:
   - `compileall` に引数が渡されなかった場合、デフォルトで `sys.path` 全体（仮想環境内の全サードパーティライブラリ含む）をコンパイルしてしまう仕様が存在する。
   - そのため、Makefile 内で `@if [ -n "$(PYTHON_SRCS)" ]; then ...; fi` による非空検証ガードを設け、引数不在時の意図しない探索を確実に防止。
3. **副作用のない純粋構文解析の保証**:
   - `compileall` および `py_compile` は Python の AST 生成とバイトコード出力のみを実行し、モジュール内のトップレベルコード（`__main__` や初期化処理）を実行しないため、悪意あるコードの混入時も副作用の実行リスクがない。
4. **終了コードの保全と品質ゲート完全性**:
   - いずれかのファイルで `SyntaxError` や `IndentationError` が発生した場合、`compileall` は非ゼロ終了コード（`exit 1`）を確実に返却する。
   - これにより、`make static_analysis` や Git pre-commit フック、CI の品質ゲートが確実にトリガーされ、構文エラーを含んだコードのコミット・マージを 100% 阻止する（ネガティブテストおよび複数ファイルエラー一括検知テスト合格確認済み）。

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/773-optimize-makefile-py-compile-batch-and-parallel-execution`

### Step 1: `Makefile` の `py_compile` ターゲット改修
[Makefile](../../../Makefile) の L95-99 を以下のように更新：

```makefile
.PHONY: py_compile
py_compile: activate ## py_compile syntax check for all python sources
	@if [ -n "$(PYTHON_SRCS)" ]; then \
		${VENV_PYTHON} -m compileall -q -j 0 $(PYTHON_SRCS); \
	fi
```

- `-q`: 正常コンパイル時は無用なファイルリスト出力を抑制し、構文エラー発生時のみトレースバックとエラーファイル名を表示。
- `-j 0`: システムの利用可能 CPU コア数を自動検出し、マルチワーカープロセスで並列コンパイルを実行。
- `$(PYTHON_SRCS)`: `find src ilisp alisp -type f -name "*.py"` で抽出された対象ファイル群を一括引き渡し。

### Step 2: 動作検証とエラー検知テスト
1. **正常系検証**:
   - `make clean && make py_compile`: 初回クリーン状態（コールドキャッシュ）でも並列実行により 1.269 秒で完了確認。
   - `make py_compile`: 2回目（ホットキャッシュ）が 0.073 秒で即座に完了確認。
2. **異常系検証（ネガティブテスト）**:
   - 一時的な不正構文ファイル（`src/core/syntax_broken_test.py`）を作成し `make py_compile` を実行。正確に該当ファイル名と行番号が表示され、終了コード 1（非ゼロ）で make が停止することを確認。
   - 複数ファイル（`broken1.py`, `broken2.py`）の構文エラー一括報告も検証完了。
3. **統合品質ゲート検証**:
   - `make check_format`: PASS
   - `make static_analysis`: PASS (radon CC/raw/MI/hal, xenon Grade A, mypy --strict 617 files, py_compile)
   - `make verify_quality`: PASS

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `Makefile` の `py_compile` ターゲットが `compileall -q -j 0` による並列バッチ処理に刷新されていること。
- [x] 逐次 `for` ループによるサブプロセス多重起動（660回）が完全撤去されていること。
- [x] `$(PYTHON_SRCS)` が空の場合の暴走防止ガード（`if [ -n ... ]`）が備わっていること。
- [x] `make py_compile` の実行時間がコールド状態で 1.5 秒未満（実測 1.269s）、ホット状態で 0.2 秒未満（実測 0.073s、従来比約 335 倍高速化）であること。
- [x] 構文エラー発生時にエラー内容と該当ファイルが stderr/stdout に明瞭に表示され、終了コード 1 で make が即座に失敗すること。
- [x] `make static_analysis` および `make verify_quality` が 100% PASS すること。
- [x] ドキュメント内相対パス検証（`verify-quality-gates`）で絶対パスが 0 件であること。

---
ID: 773
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Root Makefile の py_compile ターゲットにおけるサブプロセス逐次起動ループ廃止と一括・並列コンパイル化 (ID: 773)

## 1. 概要 / Summary

ルート [Makefile](../../Makefile) の `py_compile` ターゲット（およびそれを呼び出す `static_analysis`, `check`, `verify_quality`, `build`, Git pre-commit フック）において、現在シェル `for` ループで `PYTHON_SRCS`（`src`, `ilisp`, `alisp` 配下の全 `.py` ファイル）に対して **1ファイルずつ Python インタプリタプロセスを新規起動** しているボトルネックを解消する。
単一プロセスへの全ファイル一括渡し（`${VENV_PYTHON} -m py_compile $(PYTHON_SRCS)`）または `compileall -j 0` によるマルチコア並列コンパイルへ置換し、`make py_compile` の実行時間を桁違いに高速化する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [Makefile](../../Makefile) (`py_compile`, `static_analysis` ターゲット)
  - [.agents/AGENTS.md](../../.agents/AGENTS.md) (第 2.5 節: Diagnostic Auto-Fix & Makefile Quality Enforcement)
- 依存関係:
  - 関連 Issue: [Issue #774](774-optimize-compile-grammars-incremental-build-and-batch-formatting.md), [Issue #775](775-optimize-build-js-incremental-dependency-and-skip-redundant-jvm-startup.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [Makefile](../../Makefile)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/773-optimize-makefile-py-compile-batch-and-parallel-execution`

1. **`py_compile` ターゲットの一括プロセス実行化**:
   - `for py in $(PYTHON_SRCS); do ${VENV_PYTHON} -m py_compile $$py || exit 1; done` を廃止し、`${VENV_PYTHON} -m py_compile $(PYTHON_SRCS)`（または `xargs` / `compileall`）により Python インタプリタ起動回数を $O(N)$ 回から $1$ 回へ削減する。
2. **構文エラー検出精度の維持確認**:
   - いずれかの `.py` ファイルに構文エラーが存在する場合に、従来通り非ゼロ終了コード（`exit 1`）で即座に失敗することを検証する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `make py_compile` がサブプロセス逐次ループなしで高速に完了すること。
- [ ] `make static_analysis` および `make verify_quality` がエラー 0 件で PASS すること。


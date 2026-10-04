---
ID: 450
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] ILISP 標準ライブラリと構文マクロ群 (stdlib/base.ilisp) の実装 (ID: 450)

## 1. 概要 / Summary
Phase 1 で構築された Kernel ILISP の最小核（6大基本式と23プリミティブ）の上で動作する、Lisp 自身で記述された標準ライブラリ `ilisp/stdlib/base.ilisp` を実装する。
`let`, `let*`, `cond`, `and`, `or`, `when`, `unless` などの主要な制御構文マクロ、および `map`, `filter`, `fold-left`, `reverse`, `append`, `assoc` などの必須高階関数を整備し、実用的な R7RS-small Scheme としての表現力を確立する。
あわせて、ファイル読み込みプリミティブ `load` を整備し、REPL や評価器の初期化時に自動プリロード可能にする。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `ilisp/stdlib/base.ilisp` (ILISP 自体で記述されたコア標準ライブラリ)
- [x] `ilisp/env.py` (`load` プリミティブおよび標準ライブラリ自動プリロード機能)
- [x] `tests/ilisp/test_stdlib.py` (標準ライブラリ・構文マクロ網羅テストスイート)
- [x] `docs/issues/README.md` (Issue 450 登録)

---

## 3. 実装方針 / Implementation Plan
Target Branch: `feat/450-implement-ilisp-stdlib-base`

1. **ファイル読み込みプリミティブ (`load`) の追加 (`ilisp/env.py`)**:
   - `(load "path/to/file.ilisp")` により、指定ファイルを読み込んで現在の環境で順次評価するプリミティブを登録。
   - `make_initial_env(preload_stdlib=True)` オプションを設け、`base.ilisp` を透過的にプリロード。
2. **コア構文マクロの実装 (`ilisp/stdlib/base.ilisp`)**:
   - `when`, `unless`: 条件実行マクロ
   - `let`: `(let ((var val) ...) body ...)` を `((lambda (var ...) body ...) val ...)` に脱糖
   - `let*`: 逐次スコープへのネスト展開
   - `cond`: `(cond ((test expr ...) ...) (else ...))` のネスト `if` への脱糖
   - `and`: 引数の短絡真偽評価マクロ
   - `or`: 引数の短絡評価マクロ（一時変数束縛）
3. **リスト・高階関数ライブラリの実装 (`ilisp/stdlib/base.ilisp`)**:
   - リストアクセス: `caar`, `cadr`, `cdar`, `cddr`
   - リスト基本: `length`, `reverse`, `append`
   - 高階関数: `map`, `filter`, `for-each`, `fold-left`
   - 探索: `member`, `memq`, `assoc`, `assq`
4. **テストスイートの構築 (`tests/ilisp/test_stdlib.py`)**:
   - 全構文マクロ（`let`, `let*`, `cond`, `and`, `or`, `when`, `unless`）の正常系・境界系テスト。
   - 全高階関数（`map`, `filter`, `fold-left`, `reverse` 等）の動作検証。
   - Trampoline TCO との協調動作検証。
5. **品質管理ゲート検証**:
   - `make check_format`
   - `make static_analysis`
   - `make test`

---

## 4. 完了条件 / Success Criteria (DoD)
- [x] `ilisp/stdlib/base.ilisp` が Kernel ILISP の文法のみで記述され、エラーなくロードできること
- [x] `let`, `let*`, `cond`, `and`, `or`, `when`, `unless` が正確にマクロ展開・評価されること
- [x] `map`, `filter`, `fold-left`, `reverse`, `append`, `assoc` が正確に動作すること
- [x] `make_initial_env()` により標準ライブラリが自動的に利用可能であること
- [x] 新規テストスイート（`tests/ilisp/test_stdlib.py`）を含む全テストが 100% PASS すること
- [x] リポジトリの全品質ゲート（`flake8`, `isort`, `black`, `mypy --strict`, `pytest`）が 100% PASS すること

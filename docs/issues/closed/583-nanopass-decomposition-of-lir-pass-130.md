---
ID: 583
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] LIR パス (130_lir.scm) の機能責務別ナノパス分割（クロージャ・ABI呼出・継続・制御構文・ランタイム機能） (ID: 583)

## 1. 概要 / Summary

Phase 1 (Issue #573 / Commit `10d8b61d5`) においてプリミティブ命令選択（zero-arg, unary, binop, triop, raw syscall）が `passes/129_lir_primitives.scm` (469行) として抽出されたが、依然として `ulisp/passes/130_lir.scm` は 1,262 行に達するメガパスのままであり、以下の独立した責務が単一ファイルに混在していた：

1. **クロージャ・スタック割り当て**: ヒープクロージャ (`%alloc`)、スタックペア (`%alloc-stack`)、スタッククロージャ
2. **呼び出し・ABI・末尾最適化 (TCO)**: 一般プロシージャ呼び出し、直接呼び出し、TCO 引数シフティング、正確な GC スタックマップセーフポイント登録
3. **継続・レジスタシャッフル・ループ回転**: in-place レジスタシャッフル最適化、継続関数 (`%cont-fun`) / 継続呼び出し (`%cont-call`) のブロック降格
4. **制御構文・結合ノード分割**: `let` 束縛（直列スタック退避、未ボックス化追跡）、`if` 分岐、`begin` 連続実行、Joinノードのパス分割 (Path Splitting)
5. **ランタイム・高度制御構文**: 多値 (`values` / `call-with-values`)、構造化例外 (`with-handler`)、ファーストクラス継続 (`call/cc`)

本 Issue (583) では、Nanopass コンパイラ設計思想（DSN-33 仕様）に基づき、Pass 030 の分割（Pass 026〜029 導入）と同様のアーキテクチャを踏襲し、`130_lir.scm` を 5 つのモジュラー・サブパス（Pass 123〜127）へと完全分解した。
これにより、`130_lir.scm` は即値解決・環境管理・式ディスパッチ (`lir-compile-expr`)・関数/プログラム生成 (`generate-lir`) に特化した軽量なオーケストレータ（251 行、約 80.1% 削減）となり、各責務の 1:1 単体テスト（計 32 パステスト）を確立して保守性と認知的負荷の劇的低減を実現した。

---

## 2. トレーサビリティ / Traceability
- **Nanopass Framework 原則**: 単一パスの責務を最小化し、中間言語不変条件とモジュール性を最大化
- **DSN-33 コンパイラアーキテクチャ仕様**: 第 8 節 LIR 3番地機械抽象中間表現およびブロック引数 SSA
- **関連実績**:
  - [Issue #571 (Closed)](571-extract-lir-branch-fusion-and-comparison-lowering.md): 条件分岐・比較融合 (Pass 128) の独立分離
  - [Issue #573 (Closed)](573-nanopass-decomposition-of-lir-pass-130.md): プリミティブ命令選択 (Pass 129) の独立分離 (Phase 1)
  - [Issue #574 (Closed)](574-nanopass-decomposition-of-desugar-pass-030.md): 構文脱糖 Pass 030 のナノパス分割 (026〜029) 先行成功事例
  - [Issue #572 (Closed)](572-unify-pass-tests-to-one-to-one-mapping-with-ulisp-passes.md): 1:1 単体テスト完全対応網羅

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### パス実装ファイル (`ulisp/passes/`)
- [x] [ulisp/passes/123_lir_closures.scm](../../ulisp/passes/123_lir_closures.scm) (新規: クロージャ・スタック割り当て責務)
- [x] [ulisp/passes/124_lir_call_abi.scm](../../ulisp/passes/124_lir_call_abi.scm) (新規: 一般プロシージャ呼び出し・直接呼び出し・TCO・Safepoint 責務)
- [x] [ulisp/passes/125_lir_continuation.scm](../../ulisp/passes/125_lir_continuation.scm) (新規: 継続呼び出し・in-place シャッフル・ループ回転・%cont-fun 責務)
- [x] [ulisp/passes/126_lir_control.scm](../../ulisp/passes/126_lir_control.scm) (新規: let/if/begin 制御構文および Join ノード Path Splitting 責務)
- [x] [ulisp/passes/127_lir_runtime.scm](../../ulisp/passes/127_lir_runtime.scm) (新規: values, call-with-values, with-handler, call/cc 責務)
- [x] [ulisp/passes/130_lir.scm](../../ulisp/passes/130_lir.scm) (リファクタリング: コア環境・即値・式ディスパッチ `lir-compile-expr` およびドライバへの純化)

### 単体テストファイル (`ulisp/tests/passes/`)
- [x] [ulisp/tests/passes/test_123_lir_closures.scm](../../ulisp/tests/passes/test_123_lir_closures.scm) (新規: Pass 123 単体テスト)
- [x] [ulisp/tests/passes/test_124_lir_call_abi.scm](../../ulisp/tests/passes/test_124_lir_call_abi.scm) (新規: Pass 124 単体テスト)
- [x] [ulisp/tests/passes/test_125_lir_continuation.scm](../../ulisp/tests/passes/test_125_lir_continuation.scm) (新規: Pass 125 単体テスト)
- [x] [ulisp/tests/passes/test_126_lir_control.scm](../../ulisp/tests/passes/test_126_lir_control.scm) (新規: Pass 126 単体テスト)
- [x] [ulisp/tests/passes/test_127_lir_runtime.scm](../../ulisp/tests/passes/test_127_lir_runtime.scm) (新規: Pass 127 単体テスト)
- [x] [ulisp/tests/passes/test_130_lir.scm](../../ulisp/tests/passes/test_130_lir.scm) (既存: Braun SSA & ブロック引数回帰確認)

### ビルドおよび台帳
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`PASSES_LIB` および `NANOPASS_TESTS` リスト更新: 27パスから32パスへ拡張)
- [x] [docs/issues/README.md](README.md) (Issue台帳のステータス管理)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/583-nanopass-decomposition-of-lir-pass-130`

### Step 1: `passes/123_lir_closures.scm` の切り出し（約 95 行）
以下のクロージャ生成・スタック割り当て関数を `130_lir.scm` から抽出し独立モジュール化：
- `lir-compile-make-closure`
- `lir-compile-stack-cons`
- `lir-compile-make-stack-closure`

### Step 2: `passes/124_lir_call_abi.scm` の切り出し（約 90 行）
以下のプロシージャ呼び出し・ABI・スタックマップ連携関数を抽出：
- `lir-compile-call`
- `lir-compile-direct-call`

### Step 3: `passes/125_lir_continuation.scm` の切り出し（約 520 行）
以下の継続ジャンプ・レジスタシャッフル・ループ回転解析関数を抽出：
- `expr-references-var?`, `expr-free-references-var?`
- `extract-in-place-const`, `cont-target-all-regs?`, `emit-in-place-jump!`
- `lir-compile-in-place-cont-call`
- `cont-recurse-tail?`, `cont-loop-rotation-candidate?`
- `cont-body-has-external-call?`, `lir-compile-cont-fun`, `lir-compile-cont-call`

### Step 4: `passes/126_lir_control.scm` の切り出し（約 200 行）
以下の束縛・分岐・順序実行関数を抽出：
- `lir-compile-let`
- `lir-compile-if`
- `lir-compile-begin`

### Step 5: `passes/127_lir_runtime.scm` の切り出し（約 130 行）
以下のランタイム高度機能関数を抽出：
- `lir-compile-with-handler`
- `lir-compile-values`
- `lir-compile-call-with-values`
- `lir-compile-raw-call-cc`

### Step 6: `passes/130_lir.scm` のオーケストレータ化（約 250 行へ純化）
- 共有基盤状態: `*lir-instructions*`, `*lir-min-si*`, `reset-lir!`, `emit-lir!`, `track-lir-si!`
- 環境・型情報: `get-raw-vars`, `set-raw-vars`, `raw-expr?`
- 即値エンコーディング: `immediate?`, `lir-immediate`
- 変数参照解決: `lir-compile-variable`
- 式ディスパッチャ: `lir-compile-expr` (Pass 123〜129 をディスパッチ)
- 関数/プログラムドライバ: `lir-compile-function`, `generate-lir`

### Step 7: `ulisp/Makefile` のパイプライン順序更新と 1:1 単体テスト新設
1. `PASSES_LIB` に `123_lir_closures.scm`, `124_lir_call_abi.scm`, `125_lir_continuation.scm`, `126_lir_control.scm`, `127_lir_runtime.scm` を `128_lir_branch_fusion.scm` の前に追加。
2. `NANOPASS_TESTS` に対応する 5 本の単体テストを追加（計 32 テスト）：
   - `tests/passes/test_123_lir_closures.scm`
   - `tests/passes/test_124_lir_call_abi.scm`
   - `tests/passes/test_125_lir_continuation.scm`
   - `tests/passes/test_126_lir_control.scm`
   - `tests/passes/test_127_lir_runtime.scm`

### Step 8: 品質検証プロトコル
1. `make -C ulisp test_all_passes` で全 32 パステストが 100% PASS することを確認。
2. `make -C ulisp compiler` で `compiler.scm` を再生成。
3. `make py_compile && make static_analysis` による全体品質ゲートの完全パスを確認。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/passes/` 下に `123_lir_closures.scm`, `124_lir_call_abi.scm`, `125_lir_continuation.scm`, `126_lir_control.scm`, `127_lir_runtime.scm` の 5 ファイルが新規作成されていること
- [x] `ulisp/passes/130_lir.scm` から各機能が適切に委譲され、コード行数が 1,262 行から 251 行へと大幅に削減（80.1%削減）されていること
- [x] `ulisp/Makefile` の `PASSES_LIB` および `NANOPASS_TESTS` に Pass 123〜127 が正しい順序で統合されていること
- [x] `ulisp/tests/passes/` 下に対応する 5 本の 1:1 単体テストスイート（`test_123_*.scm` 〜 `test_127_*.scm`）が配備されていること
- [x] `make -C ulisp test_all_passes`（全 32 パステスト）が 100% PASS すること
- [x] リポジトリ全体の品質ゲートが全て PASS すること

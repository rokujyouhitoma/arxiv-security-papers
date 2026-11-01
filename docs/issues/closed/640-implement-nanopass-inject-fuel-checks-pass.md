---
ID: 640
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] Nanopass ループバックエッジ・プロローグ セーフポイント判定自動注入パス (inject-safepoints) の実装 (ID: 640)

## 1. 概要 / Summary

[DSN-37](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) Phase 3 Task 3.4 に基づき、uLisp 多段 Nanopass コンパイラにおいて、アフィン部分言語コア（ASC: Affine Sub-language Core）内の全関数のプロローグおよびループバックエッジ（名前付き `let`、自己末尾再帰呼び出し、ループ構文）に命令バジェット（Reduction）減算・枯渇判定コードを自動注入する **セーフポイント自動注入パス (`pass-synapse-inject-safepoints`)** を Pure Scheme で実装する。

協調的な手動 `yield` 呼び出しに一切依存せず、CPU バウンドな高負荷計算や予期せぬ無限ループを含むマイクロタスクであっても、AOT コンパイラ層で最大 4096 リダクション（命令バジェット）ごとに確実に他タスクへ CPU コアを譲渡（プリエンプト）する決定論的強プリエンプション保証を確立する。
Issue #637, #638, #639 で確立された直交アーキテクチャ・レイヤ分離に従い、コンパイラコア（`frontend/`）を汚さず、並行性ライブラリ側（`ulisp/lib/ulisp/concurrency/passes/`）に配置して Pass Manager に動的 Inject するプラグイン型拡張として構築する。

---

## 2. ガバナンス・専門エージェント多角レビュー / Governance & Reviews

本 Issue は、リポジトリ統治規約（[`.agents/AGENTS.md`](../../../.agents/AGENTS.md)）に従い、PM 主導のもと全 16 専門エージェントによる多角的設計レビューを統合して策定された。

- **Project Manager (PM) (Chair / Governance)**:
  - Phase 3（Nanopass コンパイラ統合）の最終マイルストーン（Task 3.4）として、Task 3.1（プレーン分離 #637）、Task 3.2（アフィン線形所有権検査 #638）、Task 3.3（FBIP インプレース再利用 #639）の完了を受けて着手する。コンパイラコアを一切汚さず、プラグイン注入型パスとして直交性を保ちながら、全件自動テスト合格（DoD）を徹底管理する。
- **IT Specialist (Programming Languages & Compilers / PLC)**:
  - Nanopass フレームワークの `define-pass` 思想に準拠し、AST の変換を宣言的に記述する。関数プロローグ（`lambda` 式や名前付き関数）およびループバックエッジ（名前付き `let` によるループや末尾自己再帰呼び出し）を静的に走査し、`(%synapse-safepoint-poll!)` 抽象中間ノードを漏れなく注入する。
  - バックエンドコード生成において、Reduction 判定は「通常時はデクリメントして素通り（Fall-through）」、枯渇時のみ `scheduler-yield!` を呼ぶ Unlikely 分岐としてレイアウトし、パイプラインフラッシュを最小化する。
- **Systems Architect (SA)**:
  - ホスト・カーネル分離型アーキテクチャにおいて、Layer 1（R7RS コントロールプレーン）にはセーフポイントを一切挿入せず、Layer 2（ASC 計算プレーン / `%asc-kernel`）のみに局所適用する。これにより、コントロールプレーンの自由な Scheme コードの実行性能を損なうことなく、並行タスクプールの決定論的公平スケジューリング（Fair Scheduling）を達成する。
- **Information Security Specialist (SEC)**:
  - DoS / CPU リソース枯渇（CWE-400）および制御フローハイジャックへの対策として、悪意ある、あるいはバグのある無限ループスクリプトであっても、最大 4096 リダクション以内で確実に強制コンテキストスイッチを発動させる。また、セーフポイント判定自体のスタック整合性（Canary 破壊防止 CWE-787）を担保する。
- **Software Quality Assurance Specialist (SQA)**:
  - 単体テストスイート `tests/concurrency/test_pass_inject_safepoints.scm` において、関数プロローグへの注入検証、無限ループ `(let loop () (loop))` へのバックエッジ注入検証、多重再帰呼び出しへの注入検証、R7RS コードへの非侵入性検証、および Pass Manager 連携（`inject-synapse-safepoints-pass!`）と DAG 依存性（`pass-synapse-fbip` 直後）の自動テストを網羅する。
- **Software Development (SWD)**:
  - パス本体 `pass_inject_safepoints.scm`、ライブラリ定義 `inject_safepoints.sld` を作成し、Pass Manager の `(inject-pass-after! 'pass-synapse-fbip ...)` を通じて動的注入可能にする。S 式括弧整合性および相対パス 100% 準拠を徹底する。
- **IT Service Manager (SM)** / **Systems Auditor (AU)**:
  - プロダクション稼働における運用可観測性のため、セーフポイント通過時のリダクション消費量およびプリエンプション発生回数（`task-exhaustion-count`）が既存のランタイム監視基盤（`preempt.scm`）とシームレスに連動することを確認する。

---

## 3. 脅威分析とセキュリティ要件 / Threat Modeling & Security Requirements

| 脅威分類 (STRIDE) | 脆弱性タイプ (CWE) | 潜在リスク・攻撃シナリオ | 防護策・緩和設計 (Mitigation) |
| :--- | :--- | :--- | :--- |
| **Denial of Service** | CWE-400 (Uncontrolled Resource Consumption) | AI 生成コードや第三者スクリプトが CPU バウンドな高負荷処理や無限ループ `(let loop () (loop))` を実行し、Worker スレッドを永久占有してシステム全体をフリーズ・餓死（Starvation）させる。 | すべてのループバックエッジおよび関数プロローグに決定論的 Reduction 減算・セーフポイント判定を自動注入し、最大 4096 リダクション以内で確実に他タスクへコアを譲渡（プリエンプト）する。 |
| **Tampering / Memory Corruption** | CWE-787 (Out-of-bounds Write) / CWE-672 | セーフポイント判定によるコンテキストスイッチ発生時に、スタック境界や Callee-saved レジスタが破損し、不正メモリアクセスを引き起こす。 | セーフポイントはステートメント境界でのみポーリングされ、Task 2.1 のスタック Canary 検証および Callee-saved レジスタ退避（`swap_context`）と完全に整合したタイミングでのみサスペンドする。 |
| **Information Disclosure / Elevation of Privilege** | CWE-200 / CWE-284 | コントロールプレーン（R7RS）の特権的な式にセーフポイントが誤って混入し、意図しないタイミングでタスクが中断されて不整合が生じる。 | プレーン分離（Task 3.1）でマークされた `%asc-kernel` 内部の AST のみにセーフポイント注入を限定し、コントロールプレーン側式には一切変更を加えない（非侵入性）。 |

---

## 4. トレーサビリティ / Traceability

- **正典設計仕様書**:
  - [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
    - 第 7.2 節: リダクション方式セーフポイント注入による決定論的プリエンプション
    - 第 9.4 節: セーフポイント注入による純粋数値計算・ループ性能のオーバーヘッドと局所適用
    - 第 12.4 節: `inject-safepoints` (セーフポイント判定コード注入)
    - 第 14.5 節: Phase 3 Nanopass コンパイラ統合 ＆ FBIP (Task 3.4)
  - [DSN-33: ULisp x86 Native AOT コンパイラアーキテクチャ仕様書](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
    - 第 2.6 節: 統一 Pass Manager 基盤と動的パス注入機構 (Pass Injection API)
- **関連・先行 Issue**:
  - [Issue 636: リダクション方式セーフポイント注入と協調的・強制的プリエンプション機構の実装](../closed/636-implement-synapse-fuel-preemption-mechanism.md)
  - [Issue 637: ホスト・カーネル分離パス (split-planes-pass) および動的パス注入機構](../closed/637-implement-nanopass-split-planes-pass.md)
  - [Issue 638: アフィン線形所有権静的検査パス (check-affine-types) および自動 RAII Drop の実装](../closed/638-implement-nanopass-check-affine-types-and-raii-drop.md)
  - [Issue 639: FBIP (Perceus) インプレース再利用最適化パスの実装](../closed/639-implement-nanopass-fbip-inplace-optimization.md)

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

### 新規作成
- `ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm`: セーフポイント判定自動注入パス本体
  - AST 走査、関数プロローグ判定、ループバックエッジ検出、セーフポイントノード注入
  - パス記述子 `synapse-inject-safepoints-descriptor` および注入 API `inject-synapse-safepoints-pass!`
- `ulisp/lib/ulisp/concurrency/passes/inject_safepoints.sld`: R7RS ライブラリ定義
  - `(ulisp concurrency passes inject-safepoints)`
- `tests/concurrency/test_pass_inject_safepoints.scm`: 単体・統合テストスイート
  - プロローグ注入、名前付き `let` ループ注入、自己再帰注入、R7RS 非侵入性、Pass Manager 連携検証

### 既存更新
- `ulisp/Makefile`:
  - `test_pass_inject_safepoints` ターゲット追加
  - `lint_sexpr` への新規ファイル追加
  - `test` ターゲットへの統合
- `docs/issues/README.md`: Issue #640 ステータス管理

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/640-nanopass-inject-safepoints`

### Step 1: セーフポイント抽象中間ノードおよび AST 述語の定義 (`pass_inject_safepoints.scm`)
1. **抽象中間ノードの定義**:
   - `(%synapse-safepoint-poll!)`: ランタイムの Reduction 判定および条件付きプリエンプション（`safepoint-poll!`）にマッピングされるセーフポイント式。
   - `(safepoint-poll-form? x)`: 式がセーフポイント判定ノードであるかを判定する述語。
2. **AST パターン述語の整備**:
   - `(lambda-form? x)`: `(lambda (args ...) body ...)` の判定。
   - `(named-let-form? x)`: `(let name ((var init) ...) body ...)` の判定。
   - `(call-form? x target)`: 特定のループ識別子 `target` への呼び出し式 `(target ...)` の判定。

### Step 2: 関数プロローグへのセーフポイント注入ロジックの実装
1. **関数エントリの検出**:
   - `lambda` 抽象の本体先頭、名前付き関数の先頭、および `%asc-kernel` 本体の先頭を特定。
2. **プロローグ注入**:
   - 本体の直前に `(%synapse-safepoint-poll!)` を 1 回注入。すでにセーフポイントが先頭にある場合は二重注入を抑止（Idempotency 保証）。

### Step 3: ループバックエッジの検出とセーフポイント注入ロジックの実装
1. **名前付き `let` (Named let) の変換**:
   - ループ名 `name` をループ環境にバインドし、ループ本体内を走査。
   - ループ本体の先頭に `(%synapse-safepoint-poll!)` を注入。
   - ループ再帰呼び出し `(name ...)` をバックエッジとして検知し、必要に応じてその直前にもセーフポイントを挟み込む。
2. **自己末尾再帰呼び出しの検出**:
   - スコープ内の関数自身を呼び出すバックエッジを検出し、セーフポイント判定を注入。

### Step 4: `%asc-kernel` 統合および Pass Manager 動的注入
1. **ASC カーネル変換器**:
   - `%asc-kernel` でタグ付けされた式のみを展開・走査し、内部のすべての関数・ループにセーフポイントを注入。
   - 非 `%asc-kernel` 形式の通常の R7RS 式は無変更でそのまま通過（非侵入性の維持）。
2. **Pass Manager への登録**:
   - `synapse-inject-safepoints-descriptor` を定義（ID: `'pass-synapse-inject-safepoints`、Prerequisites: `'(pass-synapse-fbip)`）。
   - `inject-synapse-safepoints-pass!` で `(inject-pass-after! 'pass-synapse-fbip ...)` を実行。

### Step 5: テストスイートの作成と Makefile 統合
1. `tests/concurrency/test_pass_inject_safepoints.scm` を作成し、多角的テストケースを実装。
2. `ulisp/Makefile` に `test_pass_inject_safepoints` を追加し、`make -C ulisp lint_sexpr` および全件テストを実行。

---

## 7. 完了条件 / Success Criteria (DoD)

### 定量的検証項目
1. **関数プロローグへの注入**:
   - `%asc-kernel` 内の関数エントリ直後にセーフポイントポーリング式が確実に 1 回注入されること。
2. **ループバックエッジへの注入**:
   - 名前付き `let` による無限ループ `(let loop () (loop))` において、バックエッジにセーフポイントが漏れなく注入されること。
3. **コントロールプレーンコードへの非侵入性**:
   - 非 `%asc-kernel` 形式の通常の R7RS 式に対してはセーフポイントを挿入せず、そのまま通過させること。
4. **Pass Manager 連携**:
   - `inject-synapse-safepoints-pass!` により `pass-synapse-fbip` の直後に挿入され、Prerequisite DAG 検証が PASS すること。
5. **全テストハーネスの合格**:
   - `make -C ulisp test_pass_inject_safepoints`: 全テストケース PASS。
   - `make -C ulisp lint_sexpr`: 全ファイル S 式括弧整合性 PASS。
   - 相対パスリンク 100% 準拠（絶対パス 0 件）。

---

## 8. 検証結果 / Verification Results

### 8.1 単体・統合テスト検証 (`make -C ulisp test_pass_inject_safepoints`)
```text
=======================================================
 Starting Synapse Reduction Safepoint Injection Tests
=======================================================

--- Group 1: AST Predicates & Construction ---
  [PASS] 1.1 safepoint-poll-form? detects %synapse-safepoint-poll!
  [PASS] 1.2 safepoint-poll-form? detects %safepoint-poll!
  [PASS] 1.3 safepoint-poll-form? rejects arbitrary symbols
  [PASS] 1.4 make-safepoint-poll produces valid polling form
  [PASS] 1.5 lambda-form? detects valid lambda
  [PASS] 1.6 lambda-form? rejects non-lambda
  [PASS] 1.7 named-let-form? detects named let loop
  [PASS] 1.8 named-let-form? rejects standard let
  [PASS] 1.9 asc-kernel-form? detects %asc-kernel

--- Group 2: Function Prologue Safepoint Injection ---
  [PASS] 2.1 lambda prologue gets safepoint injected
  [PASS] 2.2 lambda prologue does not duplicate existing safepoint
  [PASS] 2.3 multi-expression lambda preserves all expressions after safepoint

--- Group 3: Loop Backedge & Named-Let Injection ---
  [PASS] 3.1 named-let infinite loop receives entry safepoint and backedge safepoint
  [PASS] 3.2 conditional loop backedge receives safepoint before recursive call
  [PASS] 3.3 nested loops both receive entry and backedge safepoints

--- Group 4: ASC Kernel Transformation ---
  [PASS] 4.1 kernel output retains %asc-kernel tag
  [PASS] 4.2 kernel header preserved
  [PASS] 4.3 kernel body has top-level safepoint poll

--- Group 5: Non-Intrusiveness on Control Plane Code ---
  [PASS] 5.1 standard R7RS forms left completely untouched

--- Group 6: Pass Manager Injection & Pipeline Integration ---
  [PASS] 6.1 pass-synapse-split-planes present in pipeline
  [PASS] 6.2 pass-synapse-check-affine present in pipeline
  [PASS] 6.3 pass-synapse-fbip present in pipeline
  [PASS] 6.4 pass-synapse-inject-safepoints present in pipeline
  [PASS] 6.5 safepoints pass directly follows fbip pass
  [PASS] 6.6 injected pipeline satisfies all DAG prerequisites
  [PASS] 6.7 non-kernel form preserved
  [PASS] 6.8 kernel form transformed
  [PASS] 6.9 safepoints pass cleanly removed

=======================================================
 Test Suite Completed: 28 / 28 assertions passed.
=======================================================
```

### 8.2 Synapse 並行処理系・Nanopass 回帰テスト一括合格
`test_arena`, `test_atomic`, `test_queue`, `test_channel`, `test_context_switch`, `test_scheduler`, `test_preemption`, `test_pass_split_planes`, `test_pass_check_affine`, `test_pass_fbip`, `test_pass_inject_safepoints` の合計 654 アサーション以上のテストが 100% PASS することを確認。

### 8.3 S 式構文整合性検証
`make -C ulisp lint_sexpr` により、全 108 ファイルの括弧不整合 0 件（All balanced）を確認。

### 8.4 レイヤ分離および Pass Injection 整合性
コンパイラコア（`frontend/`）を一切汚さず、並行性ライブラリ側（`ulisp/lib/ulisp/concurrency/passes/`）から `inject-synapse-safepoints-pass!` により動的注入する直交プラグイン構造が完全に機能することを確認。全ファイル相対パス 100%（絶対パス 0 件）。

---

## 9. 結論
[DSN-37] Phase 3 Task 3.4 のすべての要件および DoD 完了基準を完全に満たしたため、本 Issue をクローズとする。

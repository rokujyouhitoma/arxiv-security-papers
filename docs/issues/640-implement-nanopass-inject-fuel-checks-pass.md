---
ID: 640
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT] Nanopass ループバックエッジ・プロローグ セーフポイント判定自動注入パス (inject-safepoints) の実装 (ID: 640)

## 1. 概要 / Summary
[DSN-37] Phase 3 Task 3.4 に基づき、uLisp 多段 Nanopass コンパイラにおいて、アフィン部分言語コア（ASC）内の全関数のプロローグおよびループバックエッジ（名前付き `let` や自己末尾再帰呼び出し、ループ構文）に命令バジェット（Reduction）減算・枯渇判定コードを自動注入する **セーフポイント自動注入パス (`pass-synapse-inject-safepoints`)** を実装する。

協調的な手動 `yield` 呼び出しに一切依存せず、CPU バウンドな高負荷計算や予期せぬ無限ループを含むマイクロタスクであっても、AOT コンパイラ層で最大 4096 リダクション（命令バジェット）ごとに確実に他タスクへ CPU コアを譲渡（プリエンプト）する決定論的強プリエンプション保証を確立する。
Issue #637, #638, #639 で確立された直交アーキテクチャに従い、コンパイラコア（`frontend/`）を汚さず、ライブラリ側（`ulisp/lib/ulisp/concurrency/passes/`）に配置して Pass Manager に動的 Inject するプラグイン型拡張として構築する。

---

## 2. 背景と設計原則 / Background & Design Principles
- **決定論的強プリエンプション (Erlang BEAM 方式 / DSN-37 Section 7.2 & 12.4)**:
  OS シグナル（`SIGALRM` 等）による非決定論的な非同期割り込みは、メモリアロケータ内部やアトミック操作中での不整合・デッドロックリスクを伴う。
  本方式では、AOT コンパイラが AST レベルで明示的なセーフポイント判定式（`(%synapse-safepoint-poll!)`）を注入することにより、完全に安全かつ決定論的なタイミングでのみプリエンプションを発生させる。
- **DoS / CPU コア独占の根絶 (CWE-400 リソース枯渇対策)**:
  AI 生成コードや第三者スクリプトが `(let loop () (loop))` のような悪意ある、あるいはバグのある無限ループを実行した場合でも、約 4,000 反復で確実に `scheduler-yield!` が発動し、他タスクの餓死（Starvation）およびプロセス全体のフリーズを恒久的に防止する。
- **Unlikely 分岐と実行時オーバーヘッド最小化 (DSN-37 Section 9.4)**:
  Reduction カウンタが 0 以下に到達する頻度は 4096 回に 1 回と極めて低いため、判定条件は「通常時はデクリメントして素通り（Fall-through）」、枯渇時のみ分岐して `yield` を呼ぶ Unlikely 分岐としてレイアウトし、パイプラインフラッシュおよび実行速度ペナルティを 5% 未満に抑制する。
- **直交的 Pass Manager 連携 (Issue #637, #638, #639 準拠)**:
  コンパイラコアの `compiler/pass_manager.scm` が提供する `inject-pass-after!` API を通じて `pass-synapse-fbip` の直後に挿入され、パイプラインの独立性を保つ。

---

## 3. トレーサビリティ / Traceability
- **アーキテクチャ設計仕様書**:
  - [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
    - 第 7.2 節: リダクション方式セーフポイント注入による決定論的プリエンプション
    - 第 9.4 節: セーフポイント注入による純粋数値計算・ループ性能のオーバーヘッドと局所適用
    - 第 12.4 節: `inject-safepoints` (セーフポイント判定コード注入)
    - 第 14.5 節: Phase 3 Nanopass コンパイラ統合 ＆ FBIP (Task 3.4)
  - [DSN-33: ULisp x86 Native AOT コンパイラアーキテクチャ仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
    - 第 2.6 節: 統一 Pass Manager 基盤と動的パス注入機構 (Pass Injection API)
- **前提 Issue**:
  - [Issue #636: リダクション方式セーフポイント注入と協調的・強制的プリエンプション機構の実装](closed/636-implement-synapse-fuel-preemption-mechanism.md)
  - [Issue #637: ホスト・カーネル分離パス (split-planes-pass) および動的パス注入機構](closed/637-implement-nanopass-split-planes-pass.md)
  - [Issue #638: アフィン線形所有権静的検査パス (check-affine-types) および自動 RAII Drop の実装](closed/638-implement-nanopass-check-affine-types-and-raii-drop.md)
  - [Issue #639: FBIP (Perceus) インプレース再利用最適化パスの実装](closed/639-implement-nanopass-fbip-inplace-optimization.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

### 新規作成
- `ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm`: セーフポイント判定自動注入パス本体
- `ulisp/lib/ulisp/concurrency/passes/inject_safepoints.sld`: R7RS ライブラリ定義 `(ulisp concurrency passes inject-safepoints)`
- `tests/concurrency/test_pass_inject_safepoints.scm`: セーフポイント注入およびループバックエッジ検出単体テストスイート

### 既存更新
- `ulisp/Makefile`:
  - `test_pass_inject_safepoints` ターゲットの追加
  - `lint_sexpr` への新規ファイル追加
  - `test` ターゲットへの統合
- `docs/issues/README.md`: Issue #640 ステータス更新（In Progress）

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/640-nanopass-inject-safepoints`

### 5.1 セーフポイント抽象中間ノードの定義
ASC カーネル内において、セーフポイント判定式として以下の抽象中間ノードを定義・生成する：
```scheme
;; セーフポイント判定抽象ノード
(%synapse-safepoint-poll!)

;; もしくは具象展開ノード:
(if (<= (%task-reductions) 0)
    (begin
      (%task-reductions-set! 4096)
      (%task-yield!))
    (%task-reductions-dec!))
```
※ AST レベルでは簡潔かつ下流パス（LIR 生成）で最適化可能な `(%synapse-safepoint-poll!)` またはプリエンプション条件分岐式を出力する。

### 5.2 注入対象パターンの静的走査
`%asc-kernel` 内の式において、以下の 2 つの重要ポイントを走査・検出する：
1. **関数プロローグ（Function Prologue）**:
   - `lambda` 抽象の先頭
   - 名前付き関数の先頭
   - `%asc-kernel` 本体の開始直後
2. **ループバックエッジ（Loop Backedge）**:
   - **名前付き `let` (Named let)**: `(let loop ((x init) ...) ...)`
     ループ本体の先頭、および自己呼び出し `(loop ...)` の直前にセーフポイントを挟み込む。
   - **自己末尾再帰呼び出し**: 同一スコープのループ関数を再帰呼び出しする直前。
   - **低レベルループ構文**: `do` 構文などの反復エントリポイント。

### 5.3 Pluggable Pass Injection 登録
- `synapse-inject-safepoints-descriptor`:
  - ID: `'pass-synapse-inject-safepoints`
  - Prerequisites: `'(pass-synapse-fbip)` （Task 3.3 の直後）
- 注入手続き:
  `(inject-synapse-safepoints-pass!)`:
  Pass Manager の `(inject-pass-after! 'pass-synapse-fbip (synapse-inject-safepoints-descriptor))` を呼び出し。

---

## 6. 完了条件 / Success Criteria (DoD)

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

## 7. セキュリティ要件・脅威分析 (Threat Modeling)
- **CWE-400 (Uncontrolled Resource Consumption)**:
  - 脅威: 無限ループまたは高計算量タスクによる CPU コア占有・Starvation。
  - 対策: すべてのループバックエッジおよび関数プロローグに決定論的 Reduction 減算を注入し、最大 4096 リダクションで確実にコアを譲渡。
- **CWE-672 (Operation on Resource after Expiration or Release)**:
  - 脅威: コンテキストスイッチ中や Yield 中にタスクコンテキストやスタックが不整合になる問題。
  - 対策: セーフポイントはステートメント境界でのみポーリングされ、スタック canary および callee-saved レジスタ退避（Task 2.1）と整合性を保持。


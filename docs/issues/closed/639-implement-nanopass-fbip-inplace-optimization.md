---
ID: 639
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] FBIP (Perceus) インプレース再利用最適化パス (fbip-inplace-transform) の実装 (ID: 639)

## 1. 概要 / Summary
[DSN-37] Phase 3 Task 3.3 に基づき、uLisp 多段 Nanopass コンパイラにおいて、アフィン線形所有権静的検査パス（Issue #638: `check-affine-types`）の出力を受け、参照カウント 1（単一参照）であることが静的に保証された不変データ構造の更新を、新規アリーナ割り当てを行わずに生メモリ直接上書きへ変換する **FBIP（Functional But In-Place / Perceus）最適化パス (`fbip-inplace-transform`)** を実装した。

関数型プログラミングの参照透過性・不変データ構造の記述性を完全に維持しながら、コンパイル後の実行時においてはアリーナバンプアロケータのオフセット加算コードをバイパスし、メモリ割り当てゼロ（完全ゼロアロケーション）での高速なデータ構造更新・再帰走査を実現する。
Issue #637, #638 で確立された直交アーキテクチャに従い、コンパイラコア（`frontend/`）を汚さず、ライブラリ側（`ulisp/lib/ulisp/concurrency/passes/`）に配置して Pass Manager に動的 Inject するプラグイン型拡張として構築した。

---

## 2. 背景と設計原則 / Background & Design Principles
- **FBIP: Functional But In-Place（Perceus 理論 / DSN-37 Section 1.1 & 12.3）**:
  Koka や Lean 4 で確立された Perceus リファレンスカウンティング・FBIP 理論を、アフィン部分言語コア（ASC）の静的所有権モデルへと適用する。
  線形型検査（Task 3.2）を通過した変数 $x$ は、破棄・Drop される直前において「生存するエイリアスが 0 件（唯一の所有者）」であることが数学的に保証される。
  したがって、直後に同一メモリレイアウトの構造体を生成して返却する場合、既存のセルを直接インプレース上書き（In-place Mutation）しても他のいかなる計算コンテキストにも影響を与えない（参照透過性の保持）。
- **極小エフェメラルアリーナの延命と OOM 根絶 (DSN-37 Section 5 & 9.3)**:
  マイクロタスクは 2KB〜8KB の極小スタック・アリーナで動作するため、再帰的なリスト走査やデータ変換で新規アロケーションを繰り返すとアリーナが急速に枯渇し、フォールバックチャンク確保のオーバーヘッドが生じる。FBIP 最適化によりアロケーションを 0 に抑え、極小アリーナ内での超長周期ループを可能にする。
- **直交的 Pass Manager 連携 (Issue #637 準拠)**:
  コンパイラコアの `compiler/pass_manager.scm` が提供する `inject-pass-after!` API を通じて `pass-synapse-check-affine` の直後に挿入され、パイプラインの独立性を保つ。

---

## 3. トレーサビリティ / Traceability
- **アーキテクチャ設計仕様書**:
  - [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
    - 第 1.1 節: 既存技術の統合と本システムの出自 (Perceus / FBIP)
    - 第 12.3 節: `fbip-inplace-transform` (Perceus 再利用)
    - 第 14.5 節: Phase 3 Nanopass コンパイラ統合 ＆ FBIP (Task 3.3)
  - [DSN-33: ULisp x86 Native AOT コンパイラアーキテクチャ仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
    - 第 2.6 節: 統一 Pass Manager 基盤と動的パス注入機構 (Pass Injection API)
- **前提 Issue**:
  - [Issue #637: ホスト・カーネル分離パス (split-planes-pass) および動的パス注入機構](closed/637-implement-nanopass-split-planes-pass.md)
  - [Issue #638: アフィン線形所有権静的検査パス (check-affine-types) および自動 RAII Drop の実装](closed/638-implement-nanopass-check-affine-types-and-raii-drop.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

### 新規作成
- `ulisp/lib/ulisp/concurrency/passes/pass_fbip.scm`: FBIP インプレース再利用最適化パス本体
- `ulisp/lib/ulisp/concurrency/passes/fbip.sld`: R7RS ライブラリ定義 `(ulisp concurrency passes fbip)`
- `tests/concurrency/test_pass_fbip.scm`: FBIP 再利用変換およびゼロアロケーション単体テストスイート

### 既存更新
- `ulisp/Makefile`:
  - `test_pass_fbip` ターゲットの追加
  - `lint_sexpr` への新規ファイル追加
  - `test` ターゲットへの統合
- `docs/issues/README.md`: Issue #639 ステータス更新（In Progress）

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/639-nanopass-fbip-inplace-transform`

### 5.1 FBIP 再利用パターンの静的検出
`%asc-kernel` 内の式において、以下の構造パターンを静的に走査・検出する：
1. **Cons セル再利用パターン (`reuse-pair`)**:
   ```scheme
   (let ((head (car old-pair))
         (tail (cdr old-pair)))
     ;; old-pair はこれ以降参照されず、RAII drop 候補となっている
     ...
     (cons new-head new-tail))
   ```
2. **パターン検出条件**:
   - `old-cell` が線形型環境において未消費のままスコープ末尾に達していること。
   - 生成式（`cons` 等）がスコープの返却値位置に存在すること。
   - `old-cell` と新セルのメモリフットプリントが同一（Pair の場合は 16 バイト）であること。

### 5.2 インプレース更新 IR ノードへの変換
- 新規割り当て式 `(cons e1 e2)` を、解放対象セルの再利用式 `(%fbip-reuse-pair! old-cell e1 e2)` へ変換。
- 自動挿入されていた `(%affine-drop! old-cell)` は、セルが再利用されるため除去（バイパス）。
- これにより、下流のコード生成・アリーナ割り当て処理においてバンプポインタ加算（`add r12, 16`）が物理的にスキップされ、既存のポインタアドレス `old-cell` への直接ストア（`mov [rax - 1], e1` 等）のみが出力される。

### 5.3 Pluggable Pass Injection 登録
- `synapse-fbip-descriptor`:
  - ID: `'pass-synapse-fbip`
  - Prerequisites: `'(pass-synapse-check-affine)`
- 注入手続き:
  `(inject-synapse-fbip-pass!)`:
  Pass Manager の `(inject-pass-after! 'pass-synapse-check-affine (synapse-fbip-descriptor))` を呼び出し。

---

## 6. 完了条件 / Success Criteria (DoD)

### 定量的検証項目
1. **Cons 再利用パターンの正確な検出と変換**:
   - 分解された古い Pair と新規 `cons` 返却パターンが、`(%fbip-reuse-pair! old-pair new-head new-tail)` へ 100% 正確に変換されること。
2. **不要な RAII Drop の安全な除去**:
   - 再利用されたセルに対する `(%affine-drop! old-pair)` が適切に消去され、二重解放やメモリ破壊が起きないこと。
3. **生存参照があるケースの非破壊性保持**:
   - 古いセルが後続の計算で依然として参照されている場合は FBIP 変換を行わず、通常の新規 `cons` アロケーションが維持されること。
4. **Pass Manager 連携**:
   - `inject-synapse-fbip-pass!` により `pass-synapse-check-affine` の直後に挿入され、Prerequisite DAG 検証が PASS すること。
5. **全テストハーネスの合格**:
   - `make -C ulisp test_pass_fbip`: 全テストケース PASS。
   - `make -C ulisp lint_sexpr`: 全ファイル S 式括弧整合性 PASS。
   - 相対パスリンク 100% 準拠（絶対パス 0 件）。

---

## 7. 検証結果 / Verification Results

### 7.1 単体・統合テスト検証 (`make -C ulisp test_pass_fbip`)
```text
=======================================================
 Starting Synapse FBIP In-Place Reuse Tests
=======================================================

--- Group 1: FBIP Predicates & Drop Collection ---
  [PASS] 1.1 affine-drop-form? detects %affine-drop!
  [PASS] 1.2 affine-drop-form? rejects other symbols
  [PASS] 1.3 cons-form? detects binary cons
  [PASS] 1.4 cons-form? rejects unary cons
  [PASS] 1.5 cons-form? rejects ternary cons
  [PASS] 1.6 collect-drops collects p1
  [PASS] 1.7 collect-drops collects p2

--- Group 2: Cons In-Place Reuse Transformation ---
  [PASS] 2.1 fresh cons converted to %fbip-reuse-pair!
  [PASS] 2.2 target of reuse is old-pair
  [PASS] 2.3 car argument preserved
  [PASS] 2.4 cdr argument preserved
  [PASS] 2.5 redundant %affine-drop! is eliminated

--- Group 3: Non-Reused Allocations ---
  [PASS] 3.1 cons without available drop remains normal cons

--- Group 4: ASC Kernel FBIP Transformation ---
  [PASS] 4.1 kernel output is %asc-kernel
  [PASS] 4.2 kernel body has no leftover %affine-drop!

--- Group 5: Pass Manager Injection & Pipeline Integration ---
  [PASS] 5.1 pass-synapse-split-planes in pipeline
  [PASS] 5.2 pass-synapse-check-affine in pipeline
  [PASS] 5.3 pass-synapse-fbip in pipeline
  [PASS] 5.4 fbip pass directly follows check-affine pass
  [PASS] 5.5 pipeline satisfies all DAG prerequisites
  [PASS] 5.6 non-kernel form preserved
  [PASS] 5.7 kernel form transformed
  [PASS] 5.8 fbip pass cleanly removed

=======================================================
 Test Suite Completed: 23 / 23 assertions passed.
=======================================================
```

### 7.2 Synapse 並行処理系・Nanopass 回帰テスト一括合格
`test_arena`, `test_atomic`, `test_queue`, `test_channel`, `test_context_switch`, `test_scheduler`, `test_preemption`, `test_pass_split_planes`, `test_pass_check_affine`, `test_pass_fbip` の合計 626 アサーション以上のテストが 100% PASS することを確認。

### 7.3 S 式構文整合性検証
`make -C ulisp lint_sexpr` により、全 105 ファイルの括弧不整合 0 件（All balanced）を確認。

### 7.4 直交アーキテクチャ・パス整合性検証
コンパイラコア（`frontend/`）に一切手を加えず、ライブラリ側（`ulisp/lib/ulisp/concurrency/passes/`）から `inject-synapse-fbip-pass!` により動的注入するプラグイン型アーキテクチャが完全に機能することを確認。全ファイル相対パス 100%（絶対パス 0 件）。

---

## 8. 結論
[DSN-37] Phase 3 Task 3.3 のすべての要件および DoD 完了基準を完全に満たしたため、本 Issue をクローズとする。

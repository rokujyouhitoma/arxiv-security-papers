---
ID: 638
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] アフィン線形所有権静的検査パス (check-affine-types) および自動 RAII Drop の実装 (ID: 638)

## 1. 概要 / Summary
[DSN-37] Phase 3 Task 3.2 に基づき、uLisp 多段 Nanopass コンパイラにおいて、プレーン分離パス（Issue #637: `split-planes-pass`）によって抽出されたアフィン部分言語コア（Layer 2: ASC / `%asc-kernel`）構文木を対象に、**アフィン線形型静的検査および自動 RAII Drop 注入パス (`check-affine-types`)** を実装した。

本パスは、変数の二重消費（Use-After-Move / CWE-416）や可変副作用（`set!` 等 / CWE-362）、非局所的脱出（`call/cc`）をコンパイル時に静的排除するとともに、未消費のままスコープを離脱する線形リソースに対して自動的に即時解放コード（`%affine-drop!`）を AST 末尾に注入し、ガベージコレクションに依存しない決定論的メモリ管理を実現する。
Issue #637 で確立されたアーキテクチャ原則に従い、コンパイラコア（`frontend/`）を汚さず、ライブラリ側（`ulisp/lib/ulisp/concurrency/passes/`）に配置して Pass Manager に動的 Inject するプラグイン型拡張として構築した。

---

## 2. 背景と設計原則 / Background & Design Principles
- **線形論理に基づく所有権の数理的保証 (DSN-37 Section 4.3)**:
  アフィン部分言語コア（ASC）内の各変数 $x$ は、以下の不変条件を厳格に満たす：
  $$\forall x \in \text{Variables}, \quad \text{Count}(x) \le 1$$
  - $\text{Count}(x) = 1$: 単一の関数呼び出し、チャネル送信（`channel-send!` / `send!`）への譲渡（Move）。
  - $\text{Count}(x) > 1$: 同一スコープ内での再利用（Use-After-Move）。コンパイル時エラーとして拒絶。
  - $\text{Count}(x) = 0$: スコープ離脱時に未消費。自動 RAII Drop（`%affine-drop!`）を注入して即時解放。
- **純粋計算性の静的保証 (DSN-37 Section 2.2 & 12.2)**:
  ASC カーネル内では、共有状態の破壊や競合を物理排除するため、破壊的代入構文（`set!`, `set-car!`, `set-cdr!`, `vector-set!`, `string-set!`, `bytevector-u8-set!`）および継続大域脱出（`call/cc`, `dynamic-wind`）を静的エラーとしてコンパイル拒絶する。
- **Pass Manager による直交的パス注入 (Issue #637 アーキテクチャ整合)**:
  本パスは `ulisp/compiler/pass_manager.scm` の `inject-pass-after!` API を通じて `pass-synapse-split-planes` の直後に挿入され、コンパイラコアの R7RS 独立性を 100% 維持する。

---

## 3. トレーサビリティ / Traceability
- **アーキテクチャ設計仕様書**:
  - [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
    - 第 2.2 節: 並列計算プレーン（Layer 2: アフィン部分言語コア / ASC）
    - 第 4.1 節: 線形所有権移譲チャネル（Linear Ownership Transfer Channel）
    - 第 4.3 節: 線形型理論に基づく不変条件とバックプレッシャー
    - 第 12.2 節: `check-affine-types` (線形所有権検査と自動 RAII Drop)
    - 第 14.5 節: Phase 3 Nanopass コンパイラ統合 ＆ FBIP (Task 3.2)
  - [DSN-33: ULisp x86 Native AOT コンパイラアーキテクチャ仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
    - 第 2.6 節: 統一 Pass Manager 基盤と動的パス注入機構 (Pass Injection API)
- **前提 Issue**:
  - [Issue #633: 線形所有権型 P2P チャネル](closed/633-implement-synapse-first-class-p2p-channel.md)
  - [Issue #637: ホスト・カーネル分離パス (split-planes-pass) および動的パス注入機構](closed/637-implement-nanopass-split-planes-pass.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

### 新規作成
- `ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm`: アフィン線形所有権静的検査および RAII Drop 注入パス本体
- `ulisp/lib/ulisp/concurrency/passes/check_affine.sld`: R7RS ライブラリ定義 `(ulisp concurrency passes check-affine)`
- `tests/concurrency/test_pass_check_affine.scm`: 線形性違反検出および RAII Drop 注入単体テストスイート (全 35 アサーション PASS)

### 既存更新
- `ulisp/Makefile`:
  - `test_pass_check_affine` ターゲットの追加
  - `lint_sexpr` への新規ファイル追加 (102 ファイル PASS)
  - `test` ターゲットへの統合
- `docs/issues/README.md`: Issue #638 ステータス更新（Closed）

---

## 5. 実装詳細 / Implementation Details

### 5.1 禁止構文・副作用の静的検出アルゴリズム
- 検査対象 AST: `%asc-kernel` ノードの内部式。
- 破壊的代入（`set!`, `set-car!`, `set-cdr!`, `vector-set!`, `string-set!`, `bytevector-u8-set!`）および大域継続（`call/cc`, `call-with-current-continuation`, `dynamic-wind`）を静的検出・排除。
- 安全な診断アナライザ `(validate-affine-ast expr env)` により `(error forbidden-syntax <op>)` を正確にレポート。

### 5.2 線形所有権環境（Linear Ownership Environment）と消費追跡
1. **線形変数判定 (`linear-variable?`)**:
   - `rx`, `tx`, `chan`, `*-ch`, `*-chan`, `*-channel`, `buf`, `res` 等のプレフィックス/サフィックスを線形リソースとして識別。
2. **状態遷移モデル**:
   - `lin-env`: `((var . status) ...)`
   - `available` (未消費・所有権保持) $\to$ `moved` (消費済み・所有権移譲完了)
3. **消費操作（Move）の検知**:
   - `(channel-send! ch val)`, `(send! ch val)`, `(channel-recv! ch)`, `(recv! ch)`
   - 一般関数適用 `(f arg ...)` の引数スロットへの指定
4. **Use-After-Move 検出 (CWE-416 防御)**:
   - 既に `moved` 状態にある線形変数の再参照を静的に拒絶 (`(error use-after-move <var>)`)。
5. **条件分岐（`if`）の消費状態統合**:
   - `then` 節と `else` 節での消費状態を検査し、合流環境へマージ。

### 5.3 自動 RAII Drop コード生成
- スコープ終端（`let` 本体末尾、`%asc-kernel` 本体末尾）において、環境内に `available` のまま残存している線形変数を特定。
- リソース解放呼び出し `(%affine-drop! <var>)` を生成し、返却値を保護する `(let ((__raii_res ...)) (%affine-drop! ...) __raii_res)` ブロックを自動注入。

### 5.4 Pluggable Pass Injection 登録
- `synapse-check-affine-descriptor`:
  - ID: `'pass-synapse-check-affine`
  - Prerequisites: `'(pass-synapse-split-planes)`
- `(inject-synapse-check-affine-pass!)`:
  - `(inject-pass-after! 'pass-synapse-split-planes (synapse-check-affine-descriptor))`

---

## 6. 検証結果 / Verification Results
- `make -C ulisp lint_sexpr`: 102 ファイル全件 S 式括弧整合性 PASS
- `make -C ulisp test_pass_check_affine`: 全 35 アサーション PASS
- `make -C ulisp test_arena test_atomic test_queue test_channel test_context_switch test_scheduler test_preemption test_pass_split_planes test_pass_check_affine`: 全 603 アサーション 0 失敗で完全 PASS
- 相対パスリンク検証: 0 件の絶対パス違反

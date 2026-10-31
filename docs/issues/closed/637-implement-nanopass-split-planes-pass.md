---
ID: 637
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] Nanopass コンパイラへの動的パス注入機構 (Pass Injection) と Synapse プレーン分離パス (split-planes-pass) の実装 (ID: 637)

## 1. 概要 / Summary
[DSN-37] Phase 3 Task 3.1 に基づき、uLisp 多段 Nanopass コンパイラにおいて、外側のコントロールプレーン（Layer 1: R7RS）構文木と内側の並列計算プレーン（Layer 2: アフィン部分言語コア / ASC）構文木を境界で静的に検知・分離するプレーン境界分離パス `split-planes-pass` を実装した。

特に、コンパイラコアの純粋性と関心事の分離（Separation of Concerns）を維持するため、個別ライブラリ（`concurrency`）の都合をコンパイラ本体（`frontend/`）に固定ハードコードするのではなく、**Pass Manager (`ulisp/compiler/pass_manager.scm`) に汎用的な動的パス注入機構 (`inject-pass-after!`, `inject-pass-before!`, `remove-injected-pass!`)** を導入した。
プレーン分離パス本体は並行ライブラリ側 (`lib/ulisp/concurrency/passes/pass_split_planes.scm` および `split_planes.sld`) に配置し、Pass Manager へ Inject してパイプラインを拡張するプラグイン型直交アーキテクチャを実現した。

---

## 2. 背景と設計原則 / Background & Design Principles
- **ホスト・カーネル分離型アーキテクチャの必然性 (DSN-37 Section 1.2 & 12.1)**:
  R7RS の完全な表現力（大域 `call/cc`、動的型、共有ヒープ、トレーシング GC）と、高並行並列計算コア（アフィン線形所有権、プロセスローカル・エフェメラルアリーナ、強プリエンプション）は同一のメモリモデル・中間表現では共存できない。
  したがって、パイプラインの適切な位置において両プレーンの境界を検知し、安全に二面分離する。
- **コンパイラコアとライブラリ拡張の直交分離 (Pass Injection Pattern)**:
  ライブラリの構文（`spawn-task`, `with-channel`）や ASC 抽出パスをコンパイラコアに固定配置せず、ライブラリ側がパスを定義して Pass Manager に差し込む。通常コードのコンパイル時はオーバーヘッドゼロで、コンパイラコアの R7RS 自己完結性が完全に保たれる。
- **Shared-Nothing 境界サニタイズ (CWE-362 / CWE-662 防御)**:
  プレーン境界を跨ぐ自由変数は、生ポインタのまま共有してはならない。即値プリミティブ（fixnum, boolean, char 等）はレジスタ即値渡し（`'immediate`）、チャネルは線形 Move（`'linear-move`）、可変複合構造体（pair, vector, string, record 等）は明示的ディープコピー（`'deep-copy`）として分類・マーキングする。
- **直交的パイプライン設計**:
  分離された内側 AST は、独立した `%asc-kernel` IR ノードとしてカプセル化され、後続の Phase 3 パス群（Task 3.2: `check-affine-types`、Task 3.3: `fbip-inplace-transform`、Task 3.4: `inject-safepoints`）へ透過的にパイプライン処理される。

---

## 3. トレーサビリティ / Traceability
- **アーキテクチャ設計仕様書**:
  - [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
    - 第 1.2 節: ホスト・カーネル分離型アーキテクチャの工学的必然性
    - 第 2.3 節: プレーン間境界制御（Boundary Guard）
    - 第 8.1 節: 境界におけるデータサニタイズ（Shared-Nothing）
    - 第 12.1 節: `split-planes-pass` (Plane 境界分離)
    - 第 14.5 節: Phase 3 Nanopass コンパイラ統合 ＆ FBIP (Task 3.1)
- **前提 Issue (Phase 0〜2 完了)**:
  - [Issue #630: タスク独立型プロセスローカル・エフェメラルアリーナ](630-implement-synapse-task-independent-bump-arena.md)
  - [Issue #631: 低レベルアトミック並行プリミティブ](631-implement-synapse-low-level-atomic-primitives.md)
  - [Issue #632: Michael-Scott ロックフリー FIFO キュー](632-implement-synapse-michael-scott-lockfree-queue.md)
  - [Issue #633: 線形所有権型 P2P チャネル](633-implement-synapse-first-class-p2p-channel.md)
  - [Issue #634: Callee-Saved ネイティブコンテキストスイッチ](634-implement-synapse-callee-saved-context-switch.md)
  - [Issue #635: Chase-Lev ワークスティーリング スケジューラ](635-implement-synapse-work-stealing-scheduler.md)
  - [Issue #636: リダクション方式セーフポイント注入とプリエンプション機構](636-implement-synapse-fuel-preemption-mechanism.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

### 新規作成
- `ulisp/lib/ulisp/concurrency/passes/pass_split_planes.scm`: Synapse プレーン分離 Nanopass 実装（境界構文検知、自由変数解析、キャプチャ分類、AST 変換、注入 API）
- `ulisp/lib/ulisp/concurrency/passes/split_planes.sld`: R7RS ライブラリ定義 `(ulisp concurrency passes split-planes)`
- `tests/concurrency/test_pass_split_planes.scm`: プレーン分離パスおよび注入動作の包括的テストスイート (35 アサーション)

### 既存更新
- `ulisp/compiler/pass_manager.scm`:
  - `inject-pass-after!`, `inject-pass-before!`, `remove-injected-pass!` API の実装
- `ulisp/tests/test_pass_manager.scm`:
  - Group 7: Pass Injection Mechanism テストケース追加 (全 60 アサーション PASS)
- `ulisp/Makefile`:
  - `test_pass_split_planes` ターゲットおよび依存ルール統合
  - `lint_sexpr` および `test` ターゲットへの組み込み
- `docs/issues/README.md`: Issue #637 ステータス更新（Closed）

---

## 5. 実装詳細 / Implementation Details

### 5.1 Pass Manager 汎用動的注入 API
- `(inject-pass-after! target-id descriptor)`:
  既存パス `target-id` の直後に `descriptor` を挿入。既存の同一 ID パスを事前クリーンアップし、DAG 順序を維持。
- `(inject-pass-before! target-id descriptor)`:
  指定パスの直前に挿入。
- `(remove-injected-pass! id)`:
  指定した拡張パスをパイプラインから除去。

### 5.2 境界構文パターンと AST 定義
1. **検出対象境界ノード**:
   - `(spawn-task body ...)`
   - `(spawn-task (options ...) body ...)`
   - `(with-channel (rx tx [cap]) body ...)`
2. **中間表現（IR）構造**:
   - **`%asc-kernel` (内側 ASC カーネル表現)**:
     ```scheme
     (%asc-kernel (kernel-name
                   (captured-var ...))
       body ...)
     ```
   - **`%boundary-bridge` (外側コントロールプレーン表現)**:
     ```scheme
     (%boundary-bridge
       ((captured-var capture-mode) ...)  ; capture-mode: 'immediate | 'deep-copy | 'linear-move
       kernel-name
       (spawn-task-invocation ...))
     ```

### 5.3 自由変数解析 ＆ キャプチャ分類アルゴリズム
1. **自由変数抽出 (`extract-free-variables`)**:
   - 式の内部で参照され、局所環境 `bound-env` になく、かつ組み込みプリミティブ（`+`, `-`, `send!`, `recv!` 等）でないシンボルを再帰的に抽出。
2. **キャプチャモード判定 (`classify-capture-mode`)**:
   - 即値型 (`'immediate`): `count`, `idx`, `n`, `is-ready?` 等
   - チャネル (`'linear-move`): `rx`, `tx`, `chan`, `data-channel` 等
   - 複合データ (`'deep-copy`): `payload-buffer`, `shared-vec` 等（Shared-Nothing CWE-362/662 防御）
3. **二面分離変換 (`split-planes-pass`)**:
   - コントロールプレーン側には `%boundary-bridge` を残し、抽出した `%asc-kernel` 定義群をトップレベル式列に追加出力。

---

## 6. 検証結果 / Verification Results
- `make -C ulisp lint_sexpr`: 99 ファイル全件 S 式括弧整合性 PASS
- `make -C ulisp test_pass_manager`: 全 60 アサーション PASS（Injection API 検証含む）
- `make -C ulisp test_pass_split_planes`: 全 35 アサーション PASS
- `make -C ulisp test_arena test_atomic test_queue test_channel test_context_switch test_scheduler test_preemption test_pass_split_planes`: 全 568 アサーション 0 失敗で完全 PASS
- 相対パスリンク検証: 0 件の絶対パス違反

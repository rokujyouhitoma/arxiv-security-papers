---
ID: 810
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] safepoint 挿入除外判定の名前プレフィックス廃止と declare no-safepoints 構文の導入 (ID: 810)

## 1. 概要 / Summary

現在の `pass-synapse-inject-safepoints`（[ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm)）では、ランタイム内部の不可分操作や再入ループの防止を目的として、大域変数 `*safepoint-excluded-prefixes*`（56 種類におよぶプレフィックス: `"synapse"`, `"task"`, `"channel"`, `"queue"`, `"arena"`, `"make"`, `"set-"`, `"budgeted-task"`, `"sys"` 等）による関数名前方一致のブラックリスト判定を実施している。

しかし、この**名前依存ヒューリスティック (Name-based Heuristics)** には重大な構造的欠陥が存在する：

1. **ユーザー定義関数のサイレントなプリエンプション無効化（CPU 独占 / CWE-400）**:
   - ユーザーが記述した自己再帰関数が偶然ブラックリスト文字列で始まる場合（例: `(make-tree depth)`、`(task-worker-loop state)`、`(channel-poll-service)`、`(queue-process items)` など）、プロローグおよびバックエッジへの safepoint 注入が不可視のままスキップされる。
   - この結果、該当タスクが無限ループまたは長期計算に入った際、Reduction カウンタが減算されず、外部タスクからの `kill`（`task-handle-termination!`）やスケジューラによる時分割プリエンプションが一切機能しなくなり、ワーカー CPU が永久に占有される（ゾンビタスク化）。
2. **Pass 025 / Pass 030 との宣言パース連携の不備（`declare` 構文の脱落）**:
   - `pass_inject_safepoints.scm` には `(declare (no-safepoints))` をパースする述語 `safepoint-no-safepoint-decl?` が先行定義されていたが、Pass 025 (`rewrite-top-level`) による `(define name (lambda ...))` への正規化や Pass 030 (`desugar-all`) による複数式ボディの `(begin ...)` ラップによって、`lambda` ボディ先頭の `(begin (declare (no-safepoints)) ...)` が検出できず、宣言が後続の LIR パスまで未除去のまま流出して未定義シンボルエラー (`[LIR COMPILER ERROR] Unbound Symbol: no-safepoints`) となる不具合が潜在している。

本 Issue では、`*safepoint-excluded-prefixes*` による関数名ブラックリスト判定を完全に撤廃し、以下を導入・確立する：
1. `safepoint-no-safepoint-decl?` の検出およびストリッピング機構を、Pass 030 由来の `(begin (declare (no-safepoints)) ...)` に完全対応させる。
2. Pass 025 (`expand-define-record-type`) が自動生成するコンストラクタ、述語、フィールドゲッター、セッターに `(declare (no-safepoints))` を自動付与し、型検査や O(1) アクセサでの相互再帰（Issue #808 で顕在化した `budgeted-task?` 等）を宣言ベースで根絶する。
3. `ulisp/runtime/concurrency/` 内の不可分ランタイム手続き（`preempt.scm`, `context.scm`, `scheduler.scm`, `channel.scm` 等）に明示的な `(declare (no-safepoints))` を配置し、ブラックリスト依存をゼロにする。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [DSN-37 Synapse Dual-Plane Concurrency Runtime Architecture Section 7.2 & 14.4](../../docs/designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
  - [DSN-33 Nanopass AOT Compiler Architecture Section 6](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連 Issue**:
  - [Issue #792 (Affine 検査における変数名ヒント強制判定の廃止)](closed/792-refactor-affine-check-to-eliminate-name-based-heuristics.md)
  - [Issue #796 (セーフポイント注入パスの本番パイプライン正式統合)](closed/796-integrate-pass-inject-safepoints-into-compiler-passes-pipeline.md)
  - [Issue #797 (split-planes パスおよび ASC カーネルにおける変数名依存ヒューリスティックの完全撤廃)](closed/797-eliminate-name-based-heuristics-in-split-planes-capture-and-affine-check.md)
  - [Issue #802 (セーフポイント注入時における末尾呼び出し最適化 (TCO) の保護)](closed/802-preserve-tail-call-optimization-in-safepoint-injection.md)
  - [Issue #808 (safepoint 有効化状態でのプリエンプション実機統合テストの追加と Makefile 除外設定の整理)](closed/808-add-hardware-safepoint-preemption-tests-and-clean-makefile-disables.md)
  - [Issue #809 (%synapse-safepoint-poll! の LIR コード未生成の修正および aarch64 向けスタブの提供)](closed/809-fix-safepoint-poll-lir-code-emission-and-add-aarch64-stub.md)
  - [Issue #811 (型推論不能な変数のチャネル境界通過時における静的コンパイル警告の導入)](811-warn-on-untyped-variable-crossing-channel-boundary.md)

---

## 3. 多角的多重エージェント審議レビュー / Multi-Agent Architectural Review

1. **Project Manager (PM) (Chair)**:
   - Issue #792, #797 に続く「コンパイラ・ランタイムにおける暗黙的名前ヒューリスティック全廃計画」の総仕上げである。ユーザー定義の識別子命名自由度を 100% 保証し、言語仕様としての堅牢性を飛躍させる。
2. **Systems Architect (SA)**:
   - DSN-37 Section 7.2 が要求する「ランタイム不可分領域の明示的境界画定」を、名前ではなく構文属性 `(declare (no-safepoints))` で宣言的に定義。宣言属性は AST 前処理でクリーンに消費・除去されるため、ランタイムオーバーヘッドおよび LIR への汚染はゼロである。
3. **Information Security Specialist (ISS)**:
   - **CWE-400 (制御不能なリソース消費 / CPU 枯渇)**: `make-tree` や `task-runner` 等のユーザー自己再帰関数がブラックリストによって除外される穴を完全に塞ぎ、すべてのユーザー計算ループが有界時間内にプリエンプト可能となることを保証。
   - **CWE-674 (制御不能な再帰 / スタックオーバーフロー)**: レコード型アクセサへの `(declare (no-safepoints))` 自動付与により、`%synapse-safepoint-poll!` と型述語間の無限相互再帰を静的に遮断。
4. **Software Quality Assurance (SQA)**:
   - `make-tree`, `task-worker`, `channel-send-loop` など従来除外されていた名前のユーザー関数にセーフポイントが確実に注入される単体テストを追加。
   - `declare no-safepoints` を付与した関数が正しく注入除外され、かつ正常にコンパイル・実行できることを検証。
5. **IT Specialist (Programming Languages & Compilers / PLC)**:
   - `025_top_level.scm` の `expand-define-record-type` において、生成される ctor, pred, getter, setter すべてに `(declare (no-safepoints))` を挿入。
   - `pass_inject_safepoints.scm` の `safepoint-no-safepoint-decl?` および `clean-body` 抽出処理を、`(begin (declare ...) ...)` のネストに対応させ、AST の健全性を担保。
6. **Software Development (SWD)**:
   - `runtime/concurrency/` 配下のファイル（`preempt.scm`, `context.scm`, `scheduler.scm`, `channel.scm`, `arena.scm` 等）に宣言を追加し、全 20 並行性テストおよびブートストラップが完全 PASS することを確認。
7. **Systems Auditor**:
   - `*safepoint-excluded-prefixes*` の削除差分を全数監査し、ランタイム側で必要な除外関数が漏れなくホワイトリスト注釈されていることを確認。

---

## 4. セキュリティ・アーキテクチャ分析 / Security & Integrity Analysis

| 脅威 / リスク | CWE 分類 | 潜在的影響 | 本 Issue での対策・検証 |
| :--- | :--- | :--- | :--- |
| **名前衝突によるセーフポイント欠落** | CWE-400 | `make-*` や `task-*` で始まるユーザー関数が除外され、CPU 独占・DoS | `*safepoint-excluded-prefixes*` を完全削除し、全ユーザー関数に等しく注入 |
| **型述語・アクセサの相互再帰オーバーフロー** | CWE-674 | safepoint 内で呼ぶ型述語に safepoint が注入されスタック枯渇 | `expand-define-record-type` で全レコード手続きに `(declare (no-safepoints))` を自動注入 |
| **宣言構文の未解決シンボル流出** | CWE-703 | `declare` が LIR まで流出してコンパイル時 unbound variable エラー | `pass_inject_safepoints.scm` で `(declare ...)` を完全にストリップし消費 |
| **低レベル不可分コンテキストの不正中断** | CWE-662 | コンテキストスイッチやスレッドスタック操作中に非同期脱出が発生しクラッシュ | `context.scm` や `preempt.scm` の低レベル関数に明示的な `(declare (no-safepoints))` を配置 |

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm): `*safepoint-excluded-prefixes*` 撤廃、`begin` ラップ宣言検出・ストリップ対応
- [ulisp/frontend/025_top_level.scm](../../ulisp/frontend/025_top_level.scm): `expand-define-record-type` における `(declare (no-safepoints))` 自動付与
- [ulisp/runtime/concurrency/preempt.scm](../../ulisp/runtime/concurrency/preempt.scm): ランタイム手続きへの宣言付与
- [ulisp/runtime/concurrency/context.scm](../../ulisp/runtime/concurrency/context.scm): 低レベルコンテキスト操作手続きへの宣言付与
- [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm): スケジューラ内部手続きへの宣言付与
- [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm): チャネル内部手続きへの宣言付与
- [ulisp/runtime/concurrency/arena.scm](../../ulisp/runtime/concurrency/arena.scm): アリーナ内部手続きへの宣言付与
- [tests/concurrency/test_pass_inject_safepoints.scm](../../tests/concurrency/test_pass_inject_safepoints.scm): プレフィックス除外廃止および declare 構文のテスト更新
- [ulisp/compiler.scm](../../ulisp/compiler.scm): 統合コンパイラソース再生成

---

## 6. 実装方針 (フェーズ別計画) / Phased Implementation Plan

Target Branch: `feat/810-deprecate-name-prefix-safepoint-exclusion-and-introduce-declare-no-safepoints`

### Phase 1: `declare no-safepoints` 構文の堅牢化と AST ストリッピングの完備
1. [ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm) において、`safepoint-no-safepoint-decl?` を拡張：
   - `(declare no-safepoint)`, `(declare no-safepoints)`, `(declare (no-safepoint))`, `(declare (no-safepoints))` のすべての表記ゆれを完全サポート。
2. `lambda` 式および `define` 式のボディにおいて、Pass 030 (`desugar-all`) でラップされた `(begin (declare (no-safepoints)) body ...)` から宣言を確実に検知し、ボディから宣言ノードを除去（ストリップ）するロジックを実装。
3. `(define (f x) (declare (no-safepoints)) x)` を単体コンパイルし、LIR に `declare` や `no-safepoints` が流出せず正常終了することを確認。

### Phase 2: `define-record-type` 展開ルーチンへの宣言自動付与
1. [ulisp/frontend/025_top_level.scm](../../ulisp/frontend/025_top_level.scm) の `expand-define-record-type` を改修：
   - コンストラクタ定義 (`ctor-def`)
   - 述語定義 (`pred-def`)
   - ゲッター定義 (`get-def`)
   - セッター定義 (`set-defs`)
   のボディ先頭に `(declare (no-safepoints))` を挿入。
2. これにより、型述語（`budgeted-task?` 等）が自動的に safepoint 注入除外対象となることを保証。

### Phase 3: ランタイム内部手続きへの宣言付与
1. [ulisp/runtime/concurrency/preempt.scm](../../ulisp/runtime/concurrency/preempt.scm) の主要手続き（`task-reductions`, `task-reductions-set!`, `task-state`, `task-state-set!`, `task-replenish!`, `check-safepoint!`, `safepoint-poll!`, `budgeted-task-execute!` 等）に `(declare (no-safepoints))` を配置。
2. [ulisp/runtime/concurrency/context.scm](../../ulisp/runtime/concurrency/context.scm)、[ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)、[ulisp/runtime/concurrency/arena.scm](../../ulisp/runtime/concurrency/arena.scm) の低レベル手続きにも同様に宣言を付与。

### Phase 4: `*safepoint-excluded-prefixes*` の完全撤廃
1. `pass_inject_safepoints.scm` から `*safepoint-excluded-prefixes*` リストおよびプレフィックス走査ループを完全削除。
2. 除外判定基準を以下の 3 つのみに集約：
   - 低レベル `%`-プレフィックス関数（`safepoint-string-starts-with? str "%"`）
   - 極小トリビアルアクセサ（`safepoint-trivial-body?`）
   - 明示的宣言 `(declare (no-safepoints))`（`safepoint-no-safepoint-decl?`）

### Phase 5: テストスイートの更新と検証
1. [tests/concurrency/test_pass_inject_safepoints.scm](../../tests/concurrency/test_pass_inject_safepoints.scm) の Group 8 を改修：
   - プレフィックス判定テストを撤廃し、`make-tree` や `task-worker` に safepoint が正しく注入されることを検証。
   - `(declare (no-safepoints))` を指定した関数のみ safepoint が除外されることを検証。
2. `make -C ulisp test_pass_inject_safepoints`
3. `make -C ulisp test_concurrency`（全 20 並行性テストの PASS 確認）

### Phase 6: 全品質ゲートとコンパイラ同期
1. `make -C ulisp compiler` で `compiler.scm` を再生成。
2. `make -C ulisp lint_sexpr`
3. `make -C ulisp test_lir_suite`
4. `make py_compile && make static_analysis`

---

## 7. 完了条件 / Success Criteria (DoD)

- [ ] `ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm` から `*safepoint-excluded-prefixes*` が完全に削除されていること。
- [ ] `(declare (no-safepoints))` が Pass 030 の `begin` ラップ下でも確実に認識され、AST から正常にストリップされること。
- [ ] `(define (f x) (declare (no-safepoints)) x)` が LIR 未定義シンボルエラーを出さずに正常にコンパイル・実行できること。
- [ ] `ulisp/frontend/025_top_level.scm` の `expand-define-record-type` が生成するすべての手続きに `(declare (no-safepoints))` が付与されていること。
- [ ] `ulisp/runtime/concurrency/` 内の不可分・内部手続きに `(declare (no-safepoints))` が明示配置されていること。
- [ ] `make-tree` や `task-worker` 等のユーザー定義再帰関数に正常にセーフポイントが注入されること。
- [ ] `make -C ulisp test_pass_inject_safepoints` が全件 PASS すること。
- [ ] `make -C ulisp test_concurrency` の全 20 並行性ターゲットに回帰が発生しないこと。
- [ ] `make -C ulisp lint_sexpr` がエラー 0 件で通過すること。
- [ ] `make -C ulisp compiler` で `ulisp/compiler.scm` が同期再生成されていること。
- [ ] `make py_compile && make static_analysis` が 100% PASS すること。
- [ ] ドキュメント内のすべてのリンクが相対パスで記述されていること。

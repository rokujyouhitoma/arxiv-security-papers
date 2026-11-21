---
ID: 898
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] Implement JIT Loop Merge Point and Guard Annotations (ID: 898)

## 1. 概要 / Summary
[[DSN-33-05]](../designs/DSN-33-05-ulisp_endogenous_meta_tracing_jit_architecture.md) 第 3 章および [[DSN-33-04]](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) 第 6 章（メタトレーシング JIT との協調）に基づき、評価器ループの先頭および動的分岐に対して極小注釈（`jit-merge-point!` および `jit-guard-type!`）基盤を実装する。

先行 Issue（#892〜#897, #909）で完成した言語ワークベンチ基盤（客体言語 FrameDescriptor、NaN-boxing / Tagging、Direct Cogen）および既存プロトタイプ（`ulisp/jit/tracer/`）を統合し、ユーザー定義の素朴な評価器（`eval-expr` / `dispatch` ループ）に対して、手動または自動計装（Auto-Instrumentation）によって JIT マージポイントと型ガードを配線する。これにより、客体言語のコードを解釈実行しながらホットループを自動検知し、第2段階の限定継続線形トレースレコーダ（Issue #899）およびガード最適化（Issue #900）へシームレスに引き渡す制御境界を確立する。

---

## 2. 背景と設計意図 / Background & Architectural Rationale
1. **言語ワークベンチとメタトレーシング JIT の境界確立**:
   - ワークベンチで生成される客体言語インタプリタは、そのままでは素朴な再帰評価器に過ぎない。
   - 評価器のループ頭部（`while`、`for`、再帰関数、末尾呼び出し）に `(jit-merge-point! loop-tag state-bindings)` を配置することで、インタプリタの実行カウンタを追跡し、閾値（Hot Threshold）超過時に透過的にトレース記録モードへ切り替える。
2. **動的型ガード（`jit-guard-type!`）と投機的実行**:
   - 動的言語（Python, Scheme, DSL 等）では、実行時にオペランドの型が変化する。
   - `(jit-guard-type! val expected-type fail-thunk)` により、JIT トレース内に投機的型前提（`%guard type-fixnum reg expected bailout`）を記録し、型が一致する限り最適化された単一パスのネイティブ機械語を実行できるようにする。
3. **ゼロオーバーヘッド原則（Zero-Overhead Principle）**:
   - JIT が無効化されている環境（AOT 単体ビルドやデバッグモード）では、注釈マクロがコンパイル時に完全にインライン消去（単なる `(void)` または素の式への展開）され、実行時性能へのペナルティを 0% に抑える。

---

## 3. トレーサビリティ / Traceability
- **関連個別仕様書**:
  - [[DSN-33-05] ULisp 内因的メタトレーシング JIT アーキテクチャ包括設計書 (第3章・第4章)](../designs/DSN-33-05-ulisp_endogenous_meta_tracing_jit_architecture.md)
  - [[DSN-33-04] ULisp 言語ワークベンチ設計書 (第6章 メタトレーシング JIT との協調)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
  - [[DSN-33-02] ULisp 多言語フロントエンド ＆ 型付き機械語 LIR 設計書 (§3.4 Diagnostic)](../designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md)
  - [[DSN-33-07] ULisp Zero-libc Bare-Metal Runtime](../designs/DSN-33-07-ulisp_zero_libc_pure_scheme_bare_metal_runtime.md)
- **依存・先行完了 Issue**:
  - [Issue #892: ゲスト言語スタックフレーム抽象（FrameDescriptor）とローカルスロット降格](closed/892-implement-guest-frame-descriptor-and-local-slot-lowering.md)
  - [Issue #893: ゲスト言語動的型タグ表現（Tagged Pointer / NaN-boxing）](closed/893-implement-guest-dynamic-value-tagging-and-nan-boxing.md)
  - [Issue #896: Dual Source Span およびゲスト言語 DWARF .debug_line ソースマッピング](closed/896-implement-dual-source-span-and-guest-dwarf-debug-line-emitter.md)
  - [Issue #897: セキュリティ CTI フィルタ言語 cti-ql のリファレンス実装と E2E AOT コンパイル検証](closed/897-implement-cti-ql-dsl-reference-implementation-and-e2e-verification.md)
- **後続依存 Issue**:
  - [Issue #899: ホットループ検出プロファイラおよび限定継続（shift/reset）線形トレースレコーダの実装](899-implement-hot-loop-profiler-and-linear-trace-recorder.md)
  - [Issue #900: JIT トレース最適化（ガード除去・仮想化）および脱出 Deopt トランポリンの実装](900-implement-jit-trace-optimizer-and-guard-failure-deopt-trampoline.md)

---

## 4. 脅威モデルとセキュリティ対策 / Security Analysis & Threat Mitigations
| 脅威分類 (CWE) | リスクシナリオ | 具体的対策・防御プロトコル |
| :--- | :--- | :--- |
| **CWE-400 (Uncontrolled Resource Consumption)** | 悪意あるループやネストにより JIT トレース記録が無限膨張し、メモリ枯渇・コンパイル DoS を引き起こす | `*jit-max-trace-length*` (最大 1,000 命令) および `*jit-max-guard-count*` (最大 256 ガード) によるハードリミット監視。超過時は自動アボートしてインタプリタへフォールバック |
| **CWE-617 (Reachable Assertion / Unexpected Panic)** | 未知の動的型が渡された際に評価器や JIT がクラッシュ | `jit-guard-type!` における厳格な型述語検証と、不一致時の例外安全な Deopt トランポリン脱出（Bailout）の保証 |
| **CWE-119 / CWE-787 (Memory Corruption / Deopt Discrepancy)** | ガード脱出（Bailout）時にレジスタと環境フレーム（GFD）の不整合が生じ、不正メモリ参照が発生 | GFD スロットレイアウトと 1:1 対応した状態スナップショット（State Snapshot）のキャプチャを強制 |
| **CWE-78 (OS Command / Subshell Injection)** | JIT 注釈マクロの引数やデバッグタグへの外部文字列混入 | JIT ループタグのシンボル/整数厳格化（英数字・ハイフン・アンダースコア限定）、外部シェル起動ゼロの維持 |

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/jit/core/annotations.scm](ulisp/jit/core/annotations.scm) - JIT マージポイント（`jit-merge-point!`）および型ガード（`jit-guard-type!`）マクロ・プロシージャ定義
- [x] [ulisp/jit/tracer/tracer.scm](ulisp/jit/tracer/tracer.scm) - ホットカウンタ、トレースバッファ、状態機械（`IDLE`, `RECORDING`, `COMPILED`）との連携リファクタ
- [x] [ulisp/jit/tracer/auto_instrument.scm](ulisp/jit/tracer/auto_instrument.scm) - AST に対する `jit-merge-point!` / `jit-guard-type!` 自動注入器の拡張
- [x] [ulisp/tests/jit/test_jit_annotations.scm](ulisp/tests/jit/test_jit_annotations.scm) - マージポイントおよび型ガード注釈の網羅的単体・統合テスト
- [x] [ulisp/Makefile](ulisp/Makefile) - `test_jit_annotations` ターゲットの追加と `.PHONY` 登録
- [x] [docs/issues/README.md](README.md) - 台帳ステータス更新（進行中に同期）

---

## 6. 詳細設計と実装方針 / Implementation Plan
Target Branch: `feat/898-implement-jit-loop-merge-point-and-guard-annotations`

```
  +-----------------------------------------------------------------------------+
  |              Interpreter Evaluation Loop (eval-expr / dispatch)             |
  +--------------------------------------+--------------------------------------+
                                         |
                       [1. jit-merge-point! loop-tag env]
                                         |
                 +-----------------------+-----------------------+
                 |                                               |
         [Loop Count < Hot]                             [Loop Count >= Hot]
                 |                                               |
                 v                                               v
     [Normal Interpretation]                        [Transition to RECORDING]
                 |                                               |
                 |                         [2. jit-guard-type! var type fail-k]
                 |                                               |
                 |                                 +-------------+-------------+
                 |                                 |                           |
                 |                           [Type Match]               [Type Mismatch]
                 |                                 |                           |
                 |                                 v                           v
                 |                      [Emit %guard Instruction]      [Bailout to Interp]
                 |                                 |
                 v                                 v
  +-----------------------------------------------------------------------------+
  |               Recorded Linear S-expression Trace (Issue #899 へ渡す)        |
  +-----------------------------------------------------------------------------+
```

### 6.1 `ulisp/jit/core/annotations.scm` の設計・実装
1. **JIT 有効化フラグとゼロオーバーヘッド消去**:
   ```scheme
   (define *jit-enabled* (cons #t '()))
   (define-syntax jit-merge-point!
     (syntax-rules ()
       ((jit-merge-point! pc state)
        (if (car *jit-enabled*)
            (%jit-merge-point-runtime pc state)
            #f))))
   ```
2. **型ガード注釈マクロ `jit-guard-type!`**:
   ```scheme
   (define-syntax jit-guard-type!
     (syntax-rules ()
       ((jit-guard-type! val expected-type fail-k)
        (if (car *jit-enabled*)
            (%jit-guard-type-runtime val 'expected-type fail-k)
            val))))
   ```
3. **ランタイムフックプロシージャ**:
   - `(%jit-merge-point-runtime pc state)`:
     - `hot-loop?` を判定し、ホット未達ならカウントアップして `#f` を返す。
     - ホット到達時は `start-recording!` をトリガー。
     - すでに `RECORDING` 中で同じ `pc` に戻ってきた場合は `finish-recording!` を実行。
     - すでに `COMPILED` なトレースが存在する場合は、コンパイル済みトレース仕様を返す。
   - `(%jit-guard-type-runtime val type-sym fail-k)`:
     - 値 `val` が `type-sym`（`fixnum`, `string`, `vector`, `pair`, `boolean` 等）に適合するか検証。
     - 適合する場合: `RECORDING` 中であれば `(trace-guard! type-sym val type-sym fail-k)` を発行し、`val` をそのまま返す。
     - 不適合の場合: `fail-k`（脱出サンクまたはターゲットPC）を呼び出し、直ちにインタプリタへ復帰（Bailout）。

### 6.2 `ulisp/jit/tracer/auto_instrument.scm` の拡張
1. **ループ検出パターンの拡充**:
   - 既存の Named let, 末尾再帰 define に加え、`while` / `for` 構文糖衣展開後のループ頭部を検出。
2. **型分岐コンテキストにおけるガード自動挿入**:
   - `case` や `cond` による型タグ判定（例: `(case (val-tag x) ...)`）の各ブランチ先頭に `(jit-guard-type! x expected-type ...)` を自動配線。

### 6.3 単体・統合テストスイート `ulisp/tests/jit/test_jit_annotations.scm`
1. **Group 1: 静的マクロ展開とゼロオーバーヘッド検証**:
   - `*jit-enabled*` が `#f` の場合に注釈が実行時オーバーヘッドなしに素通りすることを確認。
2. **Group 2: `jit-merge-point!` カウンタと状態遷移**:
   - 閾値 3 回での `IDLE` $\implies$ `RECORDING` $\implies$ `COMPILED` 遷移の完全追跡。
3. **Group 3: `jit-guard-type!` 型判定とトレース命令発行**:
   - `fixnum`, `string`, `vector` に対する型ガード検証と、`%guard` 命令のバッファ蓄積。
4. **Group 4: ガード失敗時の Bailout 脱出検証**:
   - 不適合型が渡された際に `fail-k` が正確にトリガーされ、プログラムがクラッシュせずに通常評価へ復帰することを確認。
5. **Group 5: 未注釈インタプリタへの自動計装と E2E 実行**:
   - 素朴なフィボナッチ / カウンタ関数を自動計装し、ホットループ検知からトレース完成までの一連の流れを検証。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/jit/core/annotations.scm` に `jit-merge-point!` および `jit-guard-type!` マクロ・ランタイムが実装されていること。
- [x] `*jit-enabled*` が `#f` の場合にゼロオーバーヘッドで透過動作すること。
- [x] 型ガード失敗時に安全にフォールバック（Bailout）し、例外やクラッシュを起こさないこと（CWE-617 対策）。
- [x] トレースバッファ命令長が上限（1,000命令）を超えた場合に安全に中断されること（CWE-400 対策）。
- [x] `make -C ulisp test_jit_annotations` が 100% PASS すること。
- [x] `make -C ulisp lint_sexpr verify_zero_gauche` が PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。
- [x] Issue 台帳（`docs/issues/README.md`）のステータスが `Closed (Completed)` に同期されていること。

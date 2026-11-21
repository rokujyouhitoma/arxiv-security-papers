---
ID: 899
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] Implement Hot-Loop Profiler and Linear Trace Recorder (ID: 899)

## 1. 概要 / Summary
[[DSN-33-05]](../designs/DSN-33-05-ulisp_endogenous_meta_tracing_jit_architecture.md) 第 3 章および第 4 章（トレース記録と限定継続）に基づき、ホットループ検出プロファイラ（`hot-loop-profiler`）、限定継続（`shift`/`reset`）を用いた内因的トレースレコーダ、および直線的 LIR 命令列（`%lir-program`）抽出エンジンを実装する。

先行 Issue（#898: JIT マージポイントおよび型ガード注釈基盤）で完成した `jit-merge-point!` および `jit-guard-type!` を受けて、評価器ループの実行頻度を動的追跡し、閾値（Hot Threshold）到達時に限定継続プロンプト境界（`reset` / `shift`）を発動してループ 1 周期分の実行パスを副作用なく単一の直線トレースとしてキャプチャする。さらに、抽出されたトレースを ULisp 正規の `%lir-program`（Pass 6 規格）へと正確にマッピングし、後続のトレースオプティマイザ（Issue #900）およびネイティブ JIT バッファ（Issue #901）へ受け渡すパイプラインを確立する。

---

## 2. 背景と設計意図 / Background & Architectural Rationale
1. **内因的メタトレーシング（Endogenous Meta-Tracing）の核心機序**:
   - 外部コンパイラ（LLVM 等）に依存せず、評価器自身（Pure Scheme）の実行機構の内部からトレースを直接抽出する。
   - 評価器のループを限定継続 `reset` のプロンプト境界で保護し、ホットループ検知時に `shift` を介して後続の評価ステップをシンボリックに捕獲。ループが 1 周期して元の PC に戻ってきた時点でトレース記録をクローズする。
2. **ホットループ検出プロファイラの動的適応性**:
   - 実行頻度の高いループのみを JIT コンパイル対象とし、コールドコード（初期化や 1 回限りのループ）のコンパイルオーバーヘッドを回避する。
   - カウンタ飽和防止およびメモリ保護のため、プロファイルエントリ上限（4,096個）と適応的閾値制御（デフォルト `HOT_THRESHOLD = 50`、テスト時可変）を提供する。
3. **直線的 LIR トレースへの写像と Phi ノードの完全排除**:
   - トレーシング JIT の最大の利点は、複雑な制御フローグラフ（CFG）や SSA の $\phi$（Phi）関数を扱う必要がなく、単一の直線的命令列（Straight-Line Code）として機械語を生成できる点にある。
   - `to_lir.scm` を介して、S 式トレース内の `%mov`, `%add`, `%sub`, `%mul` および `%guard` を、仮想レジスタ割当付きの `%lir-program` へ直接降格する。

---

## 3. トレーサビリティ / Traceability
- **関連個別仕様書**:
  - [[DSN-33-05] ULisp 内因的メタトレーシング JIT アーキテクチャ包括設計書 (第3章・第4章)](../designs/DSN-33-05-ulisp_endogenous_meta_tracing_jit_architecture.md)
  - [[DSN-33-02] ULisp 多言語フロントエンド ＆ 型付き機械語 LIR 設計書 (Pass 6 LIR 規格)](../designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md)
  - [[DSN-33-04] ULisp 言語ワークベンチ設計書 (第6章 メタトレーシング JIT との協調)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
- **依存・先行完了 Issue**:
  - [Issue #898: 評価器ループに対する JIT マージポイントおよび型ガード注釈基盤の実装](closed/898-implement-jit-loop-merge-point-and-guard-annotations.md)
  - [Issue #892: ゲスト言語スタックフレーム抽象（FrameDescriptor）とローカルスロット降格](closed/892-implement-guest-frame-descriptor-and-local-slot-lowering.md)
  - [Issue #893: ゲスト言語動的型タグ表現（Tagged Pointer / NaN-boxing）](closed/893-implement-guest-dynamic-value-tagging-and-nan-boxing.md)
- **後続依存 Issue**:
  - [Issue #900: JIT トレース最適化（ガード除去・仮想化）および脱出 Deopt トランポリンの実装](900-implement-jit-trace-optimizer-and-guard-failure-deopt-trampoline.md)
  - [Issue #901: 最適化済み LIR トレースからインメモリ W^X 実行可能バッファへのネイティブ機械語直接アセンブル配線](901-integrate-jit-trace-buffer-with-in-memory-native-x86-emitter.md)

---

## 4. 脅威モデルとセキュリティ対策 / Security Analysis & Threat Mitigations
| 脅威分類 (CWE) | リスクシナリオ | 具体的対策・防御プロトコル |
| :--- | :--- | :--- |
| **CWE-400 (Uncontrolled Resource Consumption)** | 膨大なループ PC や極小ループの大量実行により、プロファイラカウンタテーブルがメモリを枯渇させる | `*jit-max-profiler-entries*`（最大 4,096 エントリ）による上限管理。上限到達時は最頻・コールドエントリの淘汰（Eviction）またはプロファイル更新停止 |
| **CWE-674 (Uncontrolled Recursion / Stack Exhaustion)** | 限定継続 `reset` / `shift` の過剰な多重ネストによる Scheme メタ継続スタックのオーバーフロー | `*meta-continuation-stack*` の深さリミット（最大 64 段）。超過時は安全に例外を送出し、プロンプトを巻き戻す |
| **CWE-119 / CWE-787 (Buffer Overflow / Register Spill Corruption)** | トレース内の仮想レジスタ数が物理レジスタプールを超過した際のアドレス計算破壊 | `allocate-lir-registers` において、`*reg-pool*`（`%rax`, `%rdx`, `%rcx`, `%r10`）枯渇時に厳格な負のスタックオフセット（`-16, -24, -32, ...`）への一貫したスピル降格 |
| **CWE-78 (OS Command / Subshell Injection)** | トレースラベル生成（`gen-trace-label`）時の外部入力混入によるアセンブラ破壊 | ラベルプレフィックスの英数字正規化、Zero Shell Invocation の維持 |

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/jit/tracer/tracer.scm](ulisp/jit/tracer/tracer.scm) - ホットループプロファイラ、限定継続キャプチャ、トレース命令記録
- [x] [ulisp/jit/core/delimcc.scm](ulisp/jit/core/delimcc.scm) - メタ継続スタック深度ガード（CWE-674 対策）とプロンプト境界制御
- [x] [ulisp/jit/bridge/to_lir.scm](ulisp/jit/bridge/to_lir.scm) - S 式トレースから canonical な `%lir-program` への直線化・命令変換
- [x] [ulisp/tests/jit/test_jit_tracer.scm](ulisp/tests/jit/test_jit_tracer.scm) - プロファイラ、限定継続レコーダ、LIR ブリッジの包括的テストスイート
- [x] [ulisp/Makefile](ulisp/Makefile) - `test_jit_tracer` ターゲットの追加と `.PHONY` 登録
- [x] [docs/issues/README.md](README.md) - 台帳ステータス更新（進行中に同期）

---

## 6. 詳細設計と実装方針 / Implementation Plan
Target Branch: `feat/899-implement-hot-loop-profiler-and-linear-trace-recorder`

```
  +-----------------------------------------------------------------------------+
  |              Interpreter Execution Loop wrapped in (with-jit-prompt ...)    |
  +--------------------------------------+--------------------------------------+
                                         |
                       [1. (jit-merge-point! pc env)]
                                         |
                 +-----------------------+-----------------------+
                 |                                               |
         [Count < Hot Threshold]                        [Count >= Hot Threshold]
                 |                                               |
                 v                                               v
     [Increment Profiler Counter]               [Trigger Delimited Capture: shift]
                 |                                               |
                 |                                               v
                 |                              [2. Set State = RECORDING]
                 |                              [   Record Loop Entry %trace-loop-entry]
                 |                                               |
                 |                              [3. Execute Loop 1 Iteration]
                 |                              [   Record %mov, %add, %guard...]
                 |                                               |
                 |                              [4. Loop Head Reached (Same PC)]
                 |                              [   Finalize Linear Trace (%trace-loop)]
                 |                                               |
                 v                                               v
  +-----------------------------------------------------------------------------+
  |                      5. Bridge to Low-Level IR (to_lir.scm)                 |
  |                      Linear S-expression Trace -> %lir-program              |
  |                      Virtual Register Allocation + Stack Spill Fallback     |
  +-----------------------------------------------------------------------------+
```

### 6.1 ホットループプロファイラの拡張 (`ulisp/jit/tracer/tracer.scm`)
1. **プロファイル状態と閾値設定**:
   - `*loop-counters*`: `((pc . count) ...)` の連想リスト。
   - `*jit-max-profiler-entries*`: 4,096 エントリのハードリミット（CWE-400 対策）。
   - `(get-loop-count pc)`: 指定 PC の実行回数取得。
   - `(inc-loop-count! pc)`: エントリ上限を検証した安全なカウントアップ。
   - `(hot-loop? pc)`: `(>= (get-loop-count pc) *tracer-hot-threshold*)` の判定。
   - `(decay-loop-counters! factor)`: 長時間実行時のコールドループ減衰処理。

### 6.2 限定継続（`shift`/`reset`）線形トレースレコーダの統合
1. **プロンプト境界ヘルパー**:
   - `(call-with-jit-prompt thunk)`: `reset-thunk` を用いて評価器ループの外側にプロンプト境界を設置。
   - `(with-jit-prompt expr ...)`: マクロ構文。
2. **限定継続トレースキャプチャ**:
   - ホット判定時に `shift` を介して現在の実行継続を捕獲。
   - トレース記録中（`RECORDING`）に同じループ PC に到達した際、限定継続を脱出して完成した `%trace-loop` オブジェクトを返す。
   - 記録中の命令長上限（`*tracer-max-trace-length* = 1000`）およびガード数上限の安全ガード。

### 6.3 LIR トレース変換エンジン (`ulisp/jit/bridge/to_lir.scm`) の強化
1. **トレースから `%lir-program` への直線化マッピング**:
   - 入力:
     ```scheme
     (%trace-loop
       (%pc loop_1)
       (%body ((%trace-loop-entry loop_1)
               (%guard type-fixnum reg_i fixnum deopt_1)
               (%add reg_sum reg_sum reg_i)
               (%add reg_i reg_i 1)
               (%trace-loop-jump loop_1))))
     ```
   - 出力:
     ```scheme
     (%lir-program
       (%lir-data)
       (%lir-functions)
       (%lir-entry
         (%label jit_loop_1_entry)
         ;; Deopt guard: cmp type and jump on failure
         (%cmp-type reg_i 1) ; fixnum
         (%jump-if-not-zero jit_bailout_deopt_1)
         (%add reg_sum reg_i)
         (%add reg_i 1)
         (%jump jit_loop_1_entry)))
     ```
2. **仮想レジスタ割当とスタックスピル**:
   - `*reg-pool*`（`%rax`, `%rdx`, `%rcx`, `%r10`）への割り当て。
   - レジスタ不足時は自動的に負のスタックスロット（`(%stack -16)`, `(%stack -24)`）へ透過マッピング。

### 6.4 単体・統合テストスイート `ulisp/tests/jit/test_jit_tracer.scm`
1. **Group 1: ホットループプロファイラ機能テスト**:
   - カウントアップ、閾値判定、リセット、上限エントリ防護（CWE-400）の検証。
2. **Group 2: 限定継続（`shift`/`reset`）プロンプト境界とキャプチャ**:
   - `with-jit-prompt` 内での安全な継続キャプチャと巻き戻し。
   - プロンプトスタック深度上限ガード（CWE-674）の検証。
3. **Group 3: 線形 S 式トレース（`%trace-loop`）の生成とサイクル完結**:
   - ループ 1 周期の正確なキャプチャと、開始・終了 PC の一致検証。
4. **Group 4: LIR プログラム（`%lir-program`）へのブリッジ変換**:
   - 生成された LIR が Pass 6 規格に完全準拠し、未定義オペコードを含まないことの検証。
5. **Group 5: 条件分岐・型ガードの直線化（Linearization）検証**:
   - 分岐を含むループにおいて、ホットパスのみが直線命令列として抽出され、オルタナティブパスが `%guard` として外側に切り出されることの検証。
6. **Group 6: 仮想レジスタプール枯渇とスタックスピルフォールバック**:
   - 5 個以上の変数を扱うループで、レジスタとスタックスロットが正しく配分されることの検証。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] ホットループプロファイラがループ実行回数を正確に追跡し、閾値でホット検知すること。
- [x] プロファイルエントリ数が上限（4,096）を超えた場合に安全に防護されること（CWE-400 対策）。
- [x] 限定継続（`shift`/`reset`）により、ループ 1 周期の実行パスが副作用なく線形トレースとしてキャプチャされること。
- [x] 限定継続プロンプト深度が上限（64段）を超えた場合に安全に防護されること（CWE-674 対策）。
- [x] キャプチャされたトレースが `to_lir.scm` により正規の `%lir-program` へ正しく変換されること。
- [x] レジスタプール枯渇時に安全にスタックスロットへスピルすること。
- [x] `make -C ulisp test_jit_tracer` が 100% PASS すること。
- [x] `make -C ulisp lint_sexpr verify_zero_gauche` が PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。
- [x] Issue 台帳（`docs/issues/README.md`）のステータスが `Closed (Completed)` に同期されていること。

---
ID: 956
種別: Feature
優先度: Medium
ステータス: Closed (2026-11-25)
作成日: 2026-11-25
担当: Project Manager (PM), IT Specialist (PLC), Information Security Specialist, Systems Architect, Software Development (SWD), Software Quality Assurance Specialist
---

# [FEAT/ENH] 並行処理ビルド向け safepoint の `mfence` 単体展開を実フラグ poll（`cmp` + `jne slow`）へ置換 (ID: 956)

## 1. 背景と目的 / Context & Objective

`main` (`b0fbb568d`, `#955` 完了後) において、`pass-synapse-inject-safepoints` が挿入する `(%synapse-safepoint-poll!)` / `(%safepoint-poll!)` のコンパイル・コード生成には以下 **3 つの構造的欠陥・冗長性** が存在する。

1. **スタンドアロン / 分割コンパイル時の LIR プリミティブが単なる `mfence` + 固定値ロードになっている**
   - [129_lir_primitives.scm](../../../ulisp/lir/129_lir_primitives.scm) (L37–39) および [131_lower_managed_dialect.scm](../../../ulisp/lir/131_lower_managed_dialect.scm) (L72–73) は、safepoint poll を `(%memory-fence)`（x86-64: `mfence` / AArch64: `dmb ish`）と `(%mov %rax (repr-encode-void))` のみに展開している。
   - このパスでは**プリエンプション要求フラグもリダクション予算も検査せず**、`ulisp_fn__pctsynapse_safepoint_poll_excl`（[preempt.scm](../../../ulisp/runtime/concurrency/preempt.scm) L279）を呼び出さないまま、`mfence` の直列化コスト（1 回 30〜100 サイクル）だけが発生している。

2. **同一 TU にランタイムを含む並行処理ビルドでの過剰クロージャ割当 (`110_closure_convert.scm`)**
   - `runtime/concurrency/preempt.scm` が同一 TU に含まれるビルド（例: [test_preemption.scm](../../../tests/concurrency/test_preemption.scm)）では、`%synapse-safepoint-poll!` が `*top-level-fns*` と `(lir-primitive? op)` の双方に登録されているため、[110_closure_convert.scm](../../../ulisp/frontend/110_closure_convert.scm) (L108–115, L213–228) の `convert-expr` が「プリミティブでも直接呼び出しでもない一般呼び出し」へフォールバックしてしまう。
   - その結果、`build/test_preemption.s` の全 **274** 箇所で毎回ヒープ上に 24B クロージャ `((%make-closure-env ulisp_fn__pctsynapse_safepoint_poll_excl))` を確保して `call r11`（`%call-closure`）する著しい性能・メモリ劣化が発生している。

3. **文脈（文位置）における冗長な `%rax` 代入 (`#951` からの移管事項)**
   - [pass_inject_safepoints.scm](../../../ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm) は常に関数冒頭やループ末尾で `(begin (%synapse-safepoint-poll!) body ...)` の非末尾位置（返却値を使用しない文位置）へ挿入する。しかし [126_lir_control.scm](../../../ulisp/lir/126_lir_control.scm) (`lir-compile-begin`) から呼ばれた `lir-compile-zero-arg` は無条件に `(%mov %rax 63)` を出力するため、`rule-lir-dead-reg-overwrite-elim` で消えない冗長 `%rax` 書き込み（1,032 箇所相当）が残存する。

### 設計比較: Read-Only フラグ Poll vs インライン減算カウンタ

| 評価軸 | 方式 A (採用): Read-Only フラグ Poll (`cmp` + `jne slow`) | 方式 B (不採用): インライン予算減算 (`dec [ctr]` + `jz slow`) |
|---|---|---|
| 高速パス命令・キャッシュ挙動 | `cmp byte ptr [rip + ulisp_safepoint_flag], 0` + `je .L_done`（Shared 状態のまま ~1 サイクル、ストア発生なし） | ループ毎に共有メモリを書換えるため store buffer 圧迫・マルチコアでキャッシュライン ping-pong 発生 |
| タスク境界外のコスト | フラグ `0` により slow path (`call`) 一切不発 | 予算カウンタが 0 になる度に無意味に発火 |
| プリエンプション精度 | タスク実行中 (`with-synapse-task-boundary` / `budgeted-task-execute!`) または `task-handle-termination!` 時にフラグ非 0 で slow path へ分岐し即座に強制停止・予算減算 | 同等（ただしランタイム外でも減算コスト発生） |
| アーキテクチャメモリモデル | x86-64 は TSO により `mfence` 不要。AArch64 は `ldarb` (Load-Acquire) + `cbz` により `dmb ish` 不要で CWE-662 を満たす | 原子減算 (`lock dec` / `ldaxr`+`stlxr`) が必須となり数十サイクル消費 |

---

## 2. トレーサビリティとセキュリティ分析 / Traceability & Security Analysis

- **関連資料・関連 Issue**:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](../945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（Lua 5.4.7 ビルドプロファイル・計測基盤）
  - [Issue #808](808-add-hardware-safepoint-preemption-tests-and-clean-makefile-disables.md)（safepoint 自動注入の動的プリエンプション実機テスト Group 11）
  - [Issue #809](809-fix-safepoint-poll-lir-code-emission-and-add-aarch64-stub.md)（`%synapse-safepoint-poll!` の weak スタブ機構）
  - [Issue #951](951-disable-safepoint-injection-in-single-threaded-compiler-modules.md)（前提：単一スレッドコンパイラモジュールの safepoint 無効化と冗長 `%rax` 課題の移管元）
  - [Issue #955](955-fuse-overflow-branch-to-jo-and-fold-constant-tag-checks.md)（現行 `main` `b0fbb568d` ベースライン）

- **セキュリティ・健全性要件 (CWE 対策)**:
  - **CWE-662 (メモリ可視性 / 同期不備)**: Issue #809 では `mfence` / `dmb ish` で可視性を確保していた。x86-64 は Total Store Order (TSO) によりストア後の他スレッドからのフラグ観測に `mfence` を要しない（ロード自体は最新可視値を取得し、他コアから書換えた側は TSO / atomic store 後に順序保証）。AArch64 では `ldarb` (Load-Acquire Byte) を用いて Acquire セマンティクスを保証し、リオーダリングによる終了通知取りこぼしを防ぐ。
  - **CWE-400 (CPU 枯渇 / 強制停止)**: `with-synapse-task-boundary`・`budgeted-task-execute!` 実行中および `task-handle-termination!` 発火時に `ulisp_safepoint_flag` を非 0 化することで、自動注入ループが確実に slow path (`ulisp_fn__pctsynapse_safepoint_poll_excl`) へ分岐し、ピア終了・予算枯渇による即時脱出を保証する。
  - **CWE-703 (未リンク時耐性)**: `ulisp_safepoint_flag` および `ulisp_fn__pctsynapse_safepoint_poll_excl` を `.weak` シンボルで定義し、並行ランタイム未リンク時はフラグが常に `0`（かつ weak 関数が `#f` (47) を返却）となり未定義参照や不正分岐を防ぐ。

---

## 3. 影響範囲と対象ファイル / Scope and Affected Files

### 変更対象ファイル
- [primitives.scm](../../../ulisp/compiler/primitives.scm): `zero-arg-prim?` / `lir-primitive?` へ `%get-safepoint-flag-ptr` を追加
- [scope.scm](../../../ulisp/compiler/scope.scm): プリミティブスコープへ `%get-safepoint-flag-ptr` を追加
- [080_annotator.scm](../../../ulisp/frontend/080_annotator.scm) & [nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm): `%get-safepoint-flag-ptr` の fixnum 型注釈追加と `%safepoint-poll` の副作用宣言追加
- [110_closure_convert.scm](../../../ulisp/frontend/110_closure_convert.scm): 演算子位置の `(lir-primitive? op)` を `*top-level-fns*` 登録時でもプリミティブ呼び出しのまま維持し、`test_preemption.s` の 274 箇所の不要クロージャ生成を解消
- [lir_lang.scm](../../../ulisp/lir/lir_lang.scm) & [lir_verifier.scm](../../../ulisp/lir/lir_verifier.scm): `L_LIR` / `L_LIR_Low` 言語仕様・検証器へ `(%safepoint-poll)` を低レベル LIR 命令として追加
- [126_lir_control.scm](../../../ulisp/lir/126_lir_control.scm): `lir-compile-begin` / `lir-compile-let` 等で非末尾（文位置）の `(%synapse-safepoint-poll!)` / `(%safepoint-poll!)` に対して `(track-lir-si! si)` 付きで `(%safepoint-poll)` のみを出力し、`(%mov %rax ...)` を抑止
- [129_lir_primitives.scm](../../../ulisp/lir/129_lir_primitives.scm): `%get-safepoint-flag-ptr`（`(%code-ref '%rax "ulisp_safepoint_flag")`）実装、および safepoint プリミティブを `(%safepoint-poll)` + `(%mov %rax 111)` へ低下
- [131_lower_managed_dialect.scm](../../../ulisp/lir/131_lower_managed_dialect.scm): `(%managed-safepoint-poll)` / `(%safepoint-poll)` を `(%memory-fence)` ではなく `(%safepoint-poll)` へ低下
- [140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm): `%safepoint-poll` の `cmp byte ptr [rip + ulisp_safepoint_flag], 0` + `je .L_sp_done_*` + slow path (`sub rsp, shift; call ulisp_safepoint_slow_trampoline; add rsp, shift`) 展開、共有レジスタ退避トランポリン `ulisp_safepoint_slow_trampoline`（`xor eax, eax; xor r10d, r10d; call ulisp_fn__pctsynapse_safepoint_poll_excl`）、および `.weak ulisp_safepoint_flag` (`.quad 0`, `.align 8`) 出力
- [150_backend_aarch64.scm](../../../ulisp/backend/150_backend_aarch64.scm): `%safepoint-poll` の `adrp`/`add` + `ldarb w9, [x9]` + `cbz w9, .L_sp_done_*` + frame-safe/caller-save 退避付き slow path `bl ulisp_fn__pctsynapse_safepoint_poll_excl` 展開、および `.weak ulisp_safepoint_flag` (`.xword 0`) 出力
- [160_backend_c.scm](../../../ulisp/backend/160_backend_c.scm) & [lir_interpreter.scm](../../../ulisp/vm/lir_interpreter.scm): `%safepoint-poll` 命令サポート
- [channel.scm](../../../ulisp/runtime/concurrency/channel.scm): `*worker-current-task-tls*` アクティブ状態 (`%any-synapse-task-active?`) に応じて `%set-current-synapse-task!` 内で `%get-safepoint-flag-ptr` 経由により `ulisp_safepoint_flag` を `1` / `0` に連動更新
- テストファイル:
  - [test_preemption.scm](../../../tests/concurrency/test_preemption.scm): 実測検証および高速化ベンチ
  - [test_backend_aarch64.scm](../../../ulisp/tests/test_backend_aarch64.scm): `ldarb` + `ulisp_safepoint_flag` 検証へ更新
  - [test_lir_dialect_separation.scm](../../../ulisp/tests/test_lir_dialect_separation.scm): `3.7 %managed-safepoint-poll` 期待値を `((%safepoint-poll))` へ更新

---

## 4. 実装方針 / Implementation Plan

Target Branch: `perf/956-real-safepoint-flag-poll`

1. **LIR 方言とプリミティブ定義の拡張 (`lir_lang.scm`, `lir_verifier.scm`, `primitives.scm`, `scope.scm`)**
   - `L_lir_core` / `L_lir_canonical` および `lir_verifier.scm` に `(%safepoint-poll)` と `(%safepoint-poll frame_shift safepoint_lbl)` を追加する。
   - `primitives.scm` (`zero-arg-prim?`, `pure-prim?` 外), `scope.scm` に `%get-safepoint-flag-ptr` を追加し、ランタイムコードから C/ASM 側の `ulisp_safepoint_flag` アドレスを `%raw-load`/`%raw-store!` 経由で操作可能にする（Gauche/インタプリタ実行時は 0 を返す互換シムを用意、またはコンカレンシーテスト側で分岐）。

2. **Closure Conversion と文位置最適化 (`110_closure_convert.scm`, `126_lir_control.scm`, `129_lir_primitives.scm`, `131_lower_managed_dialect.scm`)**
   - `110_closure_convert.scm` L211 付近で `(lir-primitive? op)` が `#t` でも `(not (assq op var-map))` のとき直接 LIR プリミティブ呼び出し（`*top-level-fns*` 上で再定義される `%synapse-safepoint-poll!` 等も含め `(zero-arg-prim? op)` は LIR プリミティブ展開）を維持し、不要な `%make-closure-env` 生成を排除する。
   - `126_lir_control.scm` (`lir-compile-begin`) にて、最終式以外の位置に現れる `(%synapse-safepoint-poll!)` / `(%safepoint-poll!)` には専用ヘルパー（またはフラグ引数）で `(%mov %rax ...)` を出さないようにし、最終式（値位置）でのみ `(%mov %rax 111)` 互換値を設定する。
   - `129_lir_primitives.scm` は `(record-safepoint! safepoint-lbl frame-shift bitmap)` とともに `(%safepoint-poll frame-shift safepoint-lbl)` を出力する。`131_lower_managed_dialect.scm` は `((%managed-safepoint-poll %safepoint-poll) (list '(%safepoint-poll)))` へ変更する。

3. **x86-64 / AArch64 / C / VM バックエンド展開 (`140`, `150`, `160`, `lir_interpreter.scm`)**
   - **`140_backend_x86_64.scm`**:
     - `%safepoint-poll` 展開：
       ```asm
           cmp byte ptr [rip + ulisp_safepoint_flag], 0
           je .L_sp_done_N
           ; frame-shift 調整・r10=0・call ulisp_fn__pctsynapse_safepoint_poll_excl・safepoint_lbl:
       .L_sp_done_N:
       ```
       （※ `%synapse-safepoint-poll!` の呼出先で GC・継続脱出が走っても正確な stackmap を保てるよう `%direct-call` と同じスタックフレーム整合を適用）
     - `.data` / `.bss` 付近（`ulisp_gc_stress_mode` と同形式）に `.globl ulisp_safepoint_flag`, `.weak ulisp_safepoint_flag`（`.byte 0`, `.align 8`）を出力する。
   - **`150_backend_aarch64.scm`**:
     - `adrp x9, ulisp_safepoint_flag` / `add x9, x9, :lo12:ulisp_safepoint_flag` / `ldarb w9, [x9]` / `cbz w9, .L_sp_done_N` + slow path `bl ulisp_fn__pctsynapse_safepoint_poll_excl` を出力し、`.weak ulisp_safepoint_flag` を配置する。
   - **`160_backend_c.scm` & `lir_interpreter.scm`**: `%safepoint-poll` の C コード展開と VM インタプリタ実行（no-op またはカウンターカウント）を追加する。

4. **並行ランタイム側フラグ連動 (`channel.scm`, `links.scm`, `preempt.scm`)**
   - `channel.scm` / `panic.scm` の `with-synapse-task-boundary` 入出時（アクティブ境界参照カウント > 0 で 1、0 で 0）や `links.scm` (`task-handle-termination!`) / `preempt.scm` (`check-safepoint!`, `budgeted-task-execute!`) にて `%get-safepoint-flag-ptr` 経由で `ulisp_safepoint_flag` を更新し、コンパイラ自動注入 safepoint からの slow path 突入と強制終了が実機で発火することを保証する。

5. **テスト・再ブートストラップ・ベンチマーク検証**
   - `test_preemption`, `test_pass_inject_safepoints`, `test_lir_dialect_separation`, `test_backend_aarch64`, 全 20 並行性テストを実行し全 PASS を確認。
   - `make bootstrap_verify_modular` で 3 段階不動点収束を確認し、safepoint 有効ビルド（`test_preemption` 等）における命令数・`.text` サイズ・スループットを計測して Section 6 に記録する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/backend/140_backend_x86_64.scm` および `ulisp/backend/150_backend_aarch64.scm` が `%safepoint-poll` を実フラグ poll（x86-64: `cmp byte ptr [rip + ulisp_safepoint_flag], 0` + `je` + slow call、AArch64: `ldarb` + `cbz` + slow call）へ展開し、不要な `mfence` / `dmb ish` を出力しない。
- [x] `110_closure_convert.scm` と `126_lir_control.scm` / `129_lir_primitives.scm` の改修により、`build/test_preemption.s` の safepoint クロージャ確保（ベースライン 274 箇所）および非末尾位置の冗長 `mov rax, 63` が解消されている。
- [x] `make -C ulisp test_preemption`（#808 Group 11 含む 102 アサーション）および全並行性テスト・`test_lir_dialect_separation`・`test_backend_aarch64` で実際にタスク切替・強制終了が発生し、全件 PASS する。
- [x] safepoint 有効ビルドのベンチマーク（`build/test_preemption.s`）で実装前の 274 箇所クロージャ確保・`mfence` poll 版より大幅に命令数・コードサイズ・高速パスコストが削減されている（`test_preemption.s` `-10,810` 行 / `-6.01%`、`0m0.011s` 実行）。
- [x] `make -C ulisp bootstrap_verify_modular` で 3 段階自己コンパイル不動点 (`stage2_*.s == stage3_*.s`) を維持し、`make check_format` / `make static_analysis` / `make py_compile` が全 PASS する。
- [x] 施策前後の計測（ELF/`.text` サイズ、`mfence`/safepoint クロージャ/命令数、実行時間）を Section 6 に記録し、全リンクが相対パスのみ（絶対パス 0 件）である。

---

## 6. 計測・検証結果 / Measurements & Verification

### ベースライン (`main` @ `b0fbb568d`, #955 完了後 / 2026-11-25 実測)
| 計測対象 / 項目 | ベースライン値 | 備考 |
|---|---:|---|
| `ulisp/bin/ulisp-boot` 総サイズ / `.text` | `9,629,616 B` / `8,048,309 B` | safepoint 無効のコンパイラ本体 |
| `ulisp/bin/ulisp-cc` 総サイズ / `.text` | `11,971,368 B` / `9,934,981 B` | — |
| `build/test_preemption.s` 行数 | `179,769` 行 | safepoint 有効並行テスト |
| `build/test_preemption.s` `mfence` 出現数 | `45` 箇所 | ランタイム `atomic.scm` / `%memory-fence` 等 |
| `build/test_preemption.s` safepoint クロージャ確保 (`lea ..., [rip + ulisp_fn__pctsynapse_safepoint_poll_excl]`) | `274` 箇所 | `110_closure_convert.scm` 起因の過剰ヒープ確保 |

### 実装後実績 (After #956 / `perf/956-real-safepoint-flag-poll`)
| 計測対象 / 項目 | 実績値 | 変化・結果 |
|---|---:|---|
| `ulisp/bin/ulisp-boot` 総サイズ / `.text` | `9,644,016 B` / `8,056,597 B` | `+8,288 B` `.text`（`ulisp_safepoint_slow_trampoline` / TLS 連動反映; 3段階不動点収束 PASS） |
| `ulisp/bin/ulisp-cc` 総サイズ / `.text` | `11,985,768 B` / `9,943,909 B` | `+8,928 B` `.text`（`.weak ulisp_safepoint_flag` + slow トランポリン含む） |
| `build/test_preemption.s` 行数 | `168,959` 行 | **`-10,810` 行 (`-6.01%`)** |
| `build/test_preemption.s` `cmp byte ptr [rip + ulisp_safepoint_flag], 0` poll 数 | `275` 箇所 | 全 safepoint が実フラグ poll + `call ulisp_safepoint_slow_trampoline` へ統一（safepoint 起因の `mfence` = `0`） |
| `build/test_preemption.s` safepoint クロージャ確保 (`lea ..., [rip + ulisp_fn__pctsynapse_safepoint_poll_excl]`) | **`0` 箇所** | **`-274` 箇所 (`-100%` 解消)** |
| `build/test_preemption.s` safepoint 直後の冗長 `mov eax, 63` | **`0` 箇所** | 文位置 `begin` の冗長代入完全削減 |
| `make -C ulisp test_preemption` (Groups 1–11) | `102/102` PASS (`0m0.011s`) | Link Cascade / Budgeted Preemption / #808 自動注入脱出 全合格 |
| `make -C ulisp test_concurrency` | 全スイート 100% PASS | `multithread_scheduler` 80/80, `let_it_crash` 113/113, `supervisor` 203/203, `scheduler` 397/397, `links_monitors` 100/100, `task_mailbox` 83/83, `osal` 92/92, `concurrency_harness` 13,600/13,600 (100反復) |
| 単体テスト (`test_aarch64`, `test_lir_dialect_separation`, `test_lir_interpreter`, `test_pass_inject_safepoints`, `test_passes`) | 全 PASS | `test_aarch64` 38/38, 1:1 Nanopass 878/878, Per-Pass 160/160 |
| `make -C ulisp bootstrap_verify_modular` | 全 5 モジュール収束 PASS | `stage2_*.s == stage3_*.s` 完全一致 |

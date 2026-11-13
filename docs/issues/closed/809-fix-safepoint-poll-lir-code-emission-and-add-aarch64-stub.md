---
ID: 809
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] %synapse-safepoint-poll! の LIR コード未生成の修正および aarch64 向けスタブの提供 (ID: 809)

## 1. 概要 / Summary

Issue #799 において `%synapse-safepoint-poll!`, `%safepoint-poll!`, `synapse-safepoint-poll!` が「引数なしプリミティブ一覧」(`compiler/primitives.scm:7` `zero-arg-prim?`) に追加された。
しかし、これに伴う低レベルコード生成機構とマルチアーキテクチャ対応において、以下の課題が存在している：

1. **LIR 命令選択とプリミティブ意味論の精緻化**:
   - Issue #802 にて `ulisp/lir/129_lir_primitives.scm` の `lir-compile-zero-arg` に `((%synapse-safepoint-poll! %safepoint-poll! synapse-safepoint-poll!) (emit-lir! '(%memory-fence)) (emit-lir! '(%mov %rax 111)))` が導入され、自立型・非並行コンパイル単位でのインライン展開（メモリフェンスおよび `#t` 即値ロード）が行われるようになった。
   - 一方で、分割コンパイルや動的外部シンボル解決下において、モジュール間でマングル関数シンボル `ulisp_fn__pctsynapse_safepoint_poll_excl` および大域変数 `ulisp_gvar__pctsynapse_safepoint_poll_excl` を参照した場合の挙動について、アーキテクチャ間で非対称性が生じている。
2. **AArch64 バックエンドにおけるセーフポイントポーリング weak スタブの欠落**:
   - x86-64 バックエンド (`ulisp/backend/140_backend_x86_64.scm:1924-1939`) では、並行ランタイム (`runtime/concurrency/preempt.scm`) が静的リンクされていないモジュールや自立バイナリに対して、弱結合シンボル (weak symbol) として `ulisp_fn__pctsynapse_safepoint_poll_excl` (戻り値 `#f` 即値 47) および `ulisp_gvar__pctsynapse_safepoint_poll_excl` を自動出力するフォールバック機構が完備されている。
   - しかし、AArch64 バックエンド (`ulisp/backend/150_backend_aarch64.scm`) にはこの weak スタブ生成ルーチンが完全に欠落しており、ARM64（Apple Silicon, Linux ARM64, QEMU aarch64）環境で並行ランタイムをリンクしない分割コンパイル構成を実行した場合に、未定義シンボルエラー (`undefined reference to ulisp_fn__pctsynapse_safepoint_poll_excl`) によるリンク破綻が発生する。

本 Issue では、`ulisp/backend/150_backend_aarch64.scm` に x86-64 と完全に対称な weak スタブ生成を実装し、LIR 命令選択の整合性を検証するとともに、マルチアーキテクチャ（x86-64 / AArch64）双方で自立モジュールおよび分割リンクが安全に完了することを保証する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [DSN-37 Synapse Concurrency Architecture Specification Section 7.2 & 14.4](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
  - [DSN-33 Nanopass Architecture Section 6](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連 Issue**:
  - [Issue #796 (セーフポイント注入パスの本番コンパイラ PASSES パイプライン正式統合)](796-integrate-pass-inject-safepoints-into-compiler-passes-pipeline.md)
  - [Issue #799 (クロスワーカー環境テスト拡充および Linux 実機 CI 検証環境の確立)](799-add-cross-worker-coroutine-yield-exception-and-linux-ci-stress-tests.md)
  - [Issue #802 (セーフポイント注入時における末尾呼び出し最適化 (TCO) の保護)](802-preserve-tail-call-optimization-in-safepoint-injection.md)
  - [Issue #807 (x86-64 バックエンドにおけるセーフポイントポーリング stub 重複定義の解消)](807-eliminate-duplicate-safepoint-poll-stub-in-x86-64-backend.md)
  - [Issue #808 (safepoint 有効化状態でのプリエンプション実機統合テストの追加と Makefile 除外設定の整理)](808-add-hardware-safepoint-preemption-tests-and-clean-makefile-disables.md)
  - [Issue #810 (safepoint 挿入除外判定の名前プレフィックス廃止と declare no-safepoints 構文の導入)](../810-deprecate-name-prefix-safepoint-exclusion-and-introduce-declare-no-safepoints.md)
  - [Issue #811 (型推論不能な変数のチャネル境界通過時における静的コンパイル警告の導入)](../811-warn-on-untyped-variable-crossing-channel-boundary.md)

---

## 3. 多角的多重エージェント審議レビュー / Multi-Agent Architectural Review

1. **Project Manager (PM) (Chair)**:
   - x86-64 と AArch64 のプラットフォームパリティ（機能等価性）の確立は、次期マルチプラットフォーム CI 配備における最重要前提条件である。本スタブ完備により ARM64 環境でのビルド破綻リスクを恒久的に排除する。
2. **Systems Architect (SA)**:
   - DSN-33 および DSN-37 の ABI 仕様に基づき、AArch64 における関数戻り値レジスタ `x0` に対する即値ロード (`mov x0, #47` / `#f`) および `.xword` ポインタディレクティブを用いたグローバルシンボル出力を規定する。
3. **Information Security Specialist (ISS)**:
   - **CWE-703 (例外条件処理の不備)**: 外部シンボル未解決によるリンカフォールトを回避し、ランタイム非リンク環境下でも未定義メモリへの分岐を起こさない安全なノーオペレーションセーフティを担保。
   - **CWE-843 (アーキテクチャ間型・ABI 混乱の防止)**: x86-64 (`rax`) と AArch64 (`x0`) で同一の真偽値タグ体系（`#f` = 47, `#t` = 111）を厳密に保持。
4. **Software Quality Assurance (SQA)**:
   - `ulisp/tests/test_backend_aarch64.scm` に Step 12 としてセーフポイント weak スタブ出力テストを追加。AArch64 バックエンド単体テスト（28項目 → 29項目以上）のオールグリーンを検証する。
5. **IT Specialist (Programming Languages & Compilers / PLC)**:
   - `150_backend_aarch64.scm` のエピローグにおいて、`*top-level-fns*` および `*top-level-vars*` に `%synapse-safepoint-poll!` が定義されていない場合のみ weak スタブを出力する条件分岐を導入。
   - `ulisp/compiler.scm` の再構築 (`cat $(PASSES) > compiler.scm`) を行い、構文リンター (`lint_sexpr.py`) の 100% PASS を維持する。
6. **Embedded Systems Specialist**:
   - Raspberry Pi / Apple Silicon 等の組込み・エッジ環境で動作する AArch64 バイナリにおいて、並行性ランタイムを含まない軽量自立バイナリが安全にビルド可能となることを歓迎。
7. **Software Development (SWD)**:
   - コード重複やシンボル衝突を防止し、ビルド速度・バイナリサイズへの影響を最小限（数十バイト）に留める。
8. **Systems Auditor**:
   - 生成アセンブリコードのトレーサビリティを監査し、ライセンス整合性および Makefile の全ゲート検証を保証。

---

## 4. セキュリティ・アーキテクチャ分析 / Security & Integrity Analysis

| 脅威 / リスク | CWE 分類 | 潜在的影響 | 本 Issue での対策・検証 |
| :--- | :--- | :--- | :--- |
| **ARM64 リンク時未定義シンボル例外** | CWE-703 | 並行ランタイム非リンク時に `ulisp_fn__pctsynapse_safepoint_poll_excl` 未解決でビルド失敗 | `150_backend_aarch64.scm` に weak 関数・変数スタブを配置し、リンカ解決を保証 |
| **アーキテクチャ間 ABI 不整合** | CWE-843 | x86-64 と AArch64 でスタブ戻り値やタグが異なり不正分岐 | 双方で即値 47 (`#f`) を返し、呼出元規約（`x0` / `rax`）に厳密準拠 |
| **マルチスレッドメモリ可視性違反** | CWE-662 | セーフポイント通過時にメモリバリアが欠落し他スレッドの停止シグナル検知遅延 | LIR 命令選択において `(%memory-fence)` (`dmb ish` / `mfence`) が確実に emit されることを検証 |
| **シンボル多重定義衝突** | CWE-703 | 並行ランタイムリンク時にスタブと本定義が重複しリンカエラー | `.weak` ディレクティブにより本定義 (`runtime/concurrency/preempt.scm`) による上書きを許可 |

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [ulisp/compiler/primitives.scm](../../../ulisp/compiler/primitives.scm): `zero-arg-prim?` におけるシンボル定義確認
- [ulisp/lir/129_lir_primitives.scm](../../../ulisp/lir/129_lir_primitives.scm): LIR 命令選択ハンドラ確認
- [ulisp/backend/140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm): x86-64 側 weak スタブ実装の参照元
- [ulisp/backend/150_backend_aarch64.scm](../../../ulisp/backend/150_backend_aarch64.scm): AArch64 側 weak スタブ実装対象
- [ulisp/compiler.scm](../../../ulisp/compiler.scm): 統合コンパイラソース（`make -C ulisp compiler` で再生成）
- [ulisp/tests/test_backend_aarch64.scm](../../../ulisp/tests/test_backend_aarch64.scm): AArch64 バックエンド単体テスト拡張
- [ulisp/Makefile](../../../ulisp/Makefile): 依存関係およびビルド検証ターゲット

---

## 6. 実装方針 (フェーズ別計画) / Phased Implementation Plan

Target Branch: `fix/809-safepoint-poll-lir-code-emission-and-add-aarch64-stub`

### Phase 1: 現状監査と LIR 命令選択の整合性確認
1. `ulisp/compiler/primitives.scm` および `ulisp/lir/129_lir_primitives.scm` の実装を監査。
2. `(%synapse-safepoint-poll!)` が自立型コンパイル時に `(%memory-fence)` および `(%mov %rax 111)` へ正しく命令選択されることを確認。

### Phase 2: AArch64 バックエンドへの weak スタブ実装
1. `ulisp/backend/150_backend_aarch64.scm` の末尾データセクション出力前に、x86-64 バックエンドと同等の条件分岐を追加：
   ```scheme
   ;; Default Weak Stubs for Synapse Safepoint Poll (No-op when concurrency runtime is unlinked)
   (if (and (not (assq '%synapse-safepoint-poll! (car *top-level-fns*)))
            (not (memq '%synapse-safepoint-poll! (car *top-level-vars*))))
       (begin
         (emit "    .globl ulisp_fn__pctsynapse_safepoint_poll_excl")
         (emit "    .weak ulisp_fn__pctsynapse_safepoint_poll_excl")
         (emit "    .type ulisp_fn__pctsynapse_safepoint_poll_excl, %function")
         (emit "ulisp_fn__pctsynapse_safepoint_poll_excl:")
         (emit "    mov x0, #47")
         (emit "    ret")
         (emit "")
         (emit "    .align 3")
         (emit "    .globl ulisp_gvar__pctsynapse_safepoint_poll_excl")
         (emit "    .weak ulisp_gvar__pctsynapse_safepoint_poll_excl")
         (emit "ulisp_gvar__pctsynapse_safepoint_poll_excl:")
         (emit "    .xword ulisp_fn__pctsynapse_safepoint_poll_excl")
         (emit "")))
   ```
2. AArch64 の呼び出し規約 (`x0` 返却レジスタ、`.xword` 64ビットポインタ、`%function` ディレクティブ) に厳密適合させる。

### Phase 3: コンパイラ再生成と S 式構文検証
1. `make -C ulisp compiler` を実行し、`ulisp/compiler.scm` を再生成。
2. `make -C ulisp lint_sexpr` を実行し、括弧整合性および構文ルールを検証。

### Phase 4: AArch64 バックエンド単体テストの拡充
1. `ulisp/tests/test_backend_aarch64.scm` に Step 12 を追加：
   - `%synapse-safepoint-poll!` を未定義のままコンパイルした出力アセンブリ内に、`ulisp_fn__pctsynapse_safepoint_poll_excl` および `ulisp_gvar__pctsynapse_safepoint_poll_excl` が出力されていることをアサート。
   - `ulisp/runtime/concurrency/preempt.scm` を定義した場合にスタブが出力抑止されること、または上書き可能な弱結合であることを検証。
2. `make -C ulisp test_aarch64` を実行し、全項目 PASS を確認。

### Phase 5: 全品質ゲートと回帰テストの実行
1. `make -C ulisp test_lir_suite`
2. `make -C ulisp test_concurrency`
3. `make py_compile && make static_analysis`

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/backend/150_backend_aarch64.scm` に `ulisp_fn__pctsynapse_safepoint_poll_excl` および `ulisp_gvar__pctsynapse_safepoint_poll_excl` の weak スタブ生成が実装されていること。
- [x] 並行ランタイム非リンク時の AArch64 ターゲット出力アセンブリに weak スタブが含まれ、`mov x0, #47; ret` が正しく emit されること。
- [x] `ulisp/compiler.scm` が最新の pass 群と同期して再構築されていること。
- [x] `make -C ulisp lint_sexpr` がエラー 0 件で通過すること。
- [x] `ulisp/tests/test_backend_aarch64.scm` に検証テストが追加され、`make -C ulisp test_aarch64` が全件 PASS すること。
- [x] `make -C ulisp test_lir_suite`, `make -C ulisp test_backend` および `make -C ulisp test_concurrency` に回帰がないこと。
- [x] `make py_compile && make static_analysis` が 100% PASS すること。
- [x] ドキュメント内の全リンクが相対パス（`../../` 等）で統一されていること。

---

## 8. 実装結果・検証記録 / Implementation Results

### 変更ファイル
- [ulisp/backend/150_backend_aarch64.scm](../../../ulisp/backend/150_backend_aarch64.scm): `ulisp_flush` 直後に weak スタブ生成を追加（`*top-level-fns*` / `*top-level-vars*` に `%synapse-safepoint-poll!` が無い場合のみ）。関数は `.text` に `mov x0, #47; ret`、変数は `.data` に `.xword` ポインタとして配置。
- [ulisp/compiler.scm](../../../ulisp/compiler.scm): `make -C ulisp compiler` で再生成。
- [ulisp/tests/test_backend_aarch64.scm](../../../ulisp/tests/test_backend_aarch64.scm): Step 12（9 アサーション）を追加。LIR 命令選択（`%memory-fence` / `#t`）、`dmb ish` 出力、weak 関数・変数スタブが各 1 回だけ出力されること、ランタイム定義時はスタブが抑止されることを検証。

### Phase 1 の結論（LIR 命令選択）
`lir-compile-zero-arg` には既に Issue #802 でハンドラが入っており、「サイレント NOP」は解消済み（x86-64: `mfence; mov rax, 111`、AArch64: `dmb ish; mov x0, #111`）。ランタイムがトップレベルで `%synapse-safepoint-poll!` を定義した場合は通常の関数ラベル（`ulisp_fn__pctsynapse_safepoint_poll_excl`）として出力される。未解決だった欠陥は、手続きを**値として**参照したとき（`ulisp_gvar__pctsynapse_safepoint_poll_excl` への参照）の AArch64 側リンク失敗だった。

### 再現と修正の確認（AArch64 クロスツールチェーン + QEMU）
| ケース | 修正前 (`main`) | 修正後 |
| :--- | :--- | :--- |
| `(define g %synapse-safepoint-poll!)` を含みランタイム非リンクのプログラム | `aarch64-linux-gnu-ld`: `undefined reference to ulisp_gvar__pctsynapse_safepoint_poll_excl` | リンク成功、`qemu-aarch64` で正常終了 (rc=0) |
| ランタイム非リンク時のシンボル | 存在せず | `nm`: `W ulisp_fn_…`, `W ulisp_gvar_…`（weak） |
| ランタイムが `%synapse-safepoint-poll!` を定義 | — | スタブ非出力、本定義のみ（重複なし） |

### 品質ゲート
| ゲート | 結果 |
| :--- | :--- |
| `make -C ulisp lint_sexpr` | PASS |
| `make -C ulisp test_aarch64` | 37/37 PASS（28 → 37） |
| `make -C ulisp test_lir_suite` | PASS |
| `make -C ulisp test_backend` | PASS |
| `make -C ulisp test_concurrency` | PASS（失敗 0 件） |
| `make py_compile && make static_analysis` | PASS（mypy --strict: 617 ファイルで指摘 0 件） |

> [!NOTE]
> `make -C ulisp test_aarch64_qemu`（stdlib の include パス解決エラー）と `test_context_switch_aarch64`（QEMU 上で SIGSEGV）は、変更前の `main` でも同じ結果になる既存不具合のため、本 Issue の範囲外として [Issue #812](../812-fix-aarch64-qemu-regression-stdlib-include-path-and-context-switch-segfault.md) に起票した。

---
ID: 961
種別: Feature
優先度: High
ステータス: Closed (Completed 2026-11-28)
---

# [FEAT/ENH] Scheme 経路の LIR への linear scan レジスタ割り付け導入（スタック退避中心コード生成の解消） (ID: 961)

## 1. 概要 / Summary

Scheme コンパイル経路（[130_lir.scm](../../../ulisp/lir/130_lir.scm) 以降）は現在、継続化（Contification）対象の一部の葉ループ（[125_lir_continuation.scm](../../../ulisp/lir/125_lir_continuation.scm) の `%rbx`/`%r13`/`%r14`）を除き、ほぼすべての引数・`let` 束縛・一時評価値をスタックスロット `[rsp - N]` に書き戻しては再ロードするコード生成を行っている。C99 経路で効果を発揮している Braun SSA `mem2reg`（[132_lir_braun_ssa.scm](../../../ulisp/lir/132_lir_braun_ssa.scm)）およびマルチブロック DSE（[133_lir_peephole.scm](../../../ulisp/lir/133_lir_peephole.scm)）は管理ランタイム命令を含む Scheme 関数に適用されていない。

### 1.1 計測ベースラインの推移と #960 時点の実測値 (`ulisp/build/stage3-modular`)

| 時点 | `.text` サイズ | `size` `text` 列 | `objdump -d` 総命令数 | 5回自己コンパイル中央値 | 備考 |
| --- | ---: | ---: | ---: | ---: | --- |
| 初回監査基準 (`2026-11-25`, `main`) | 8.86 MB | ~10.0 MB | — | — | `[rsp]` mov 書込 253,768 / 読出 262,656 |
| #957 完了後 (`share-arithmetic-stubs`) | 7,956,245 B (7.59 MB) | 9,150,033 B | — | — | 算術 slow path 共有化 |
| #959 完了後 (`static-quoted-constants`) | 6,753,237 B (6.44 MB) | 8,186,245 B | 1,612,197 | 5.052 s | `quote` 静的 `.rodata` 化 |
| **#960 完了後（#961 着手前ベースライン）** | **5,230,601 B (4.99 MB)** | **5,667,993 B (5.41 MB)** | **1,069,424** | **4.725 s** | `--gc-sections` + 未参照関数除去後 |

#960 完了時点の `ulisp/build/stage3-modular` に対する `objdump -d -M intel` 解析結果（全関数逆アセンブル命令数 `1,069,424` 件）:

- **`mov*` 命令総数**: **`605,472`**（全命令の **56.62%**）
- **`[rsp ...]` メモリアクセス命令総数**: **`348,851`**（全命令の **32.62%**）
  - **`[rsp ...]` ロード (`loads`)**: **`173,987`**（全命令の **16.27%**）
    - 主な内訳: `mov rax, [rsp - N]` = `88,008`、`mov rdx, [rsp - N]` = `51,954`、`mov rdi, [rsp - N]` = `18,323`、`mov rsi, [rsp - N]` = `6,812`、`mov rcx, [rsp - N]` = `3,492`、`or rdx, [rsp - N]` = `1,468`、`add rcx, [rsp - N]` = `1,448`
  - **`[rsp ...]` ストア (`stores`)**: **`174,864`**（全命令の **16.35%**）
    - 主な内訳: `mov [rsp - N], rax` = `149,302`、`cmp [rsp - N], rax` = `11,530`、`mov [rsp - N], rdx` = `9,901`、`mov [rsp - N], rdi` = `2,169`、`mov [rsp - N], rsi` = `1,068`

### 1.2 `[rsp - N]` トラフィックを生む 4 つの構造的根本原因

1. **ANF 単一使用・短命 `let` 束縛の無条件スピル ([070_anf.scm](../../../ulisp/frontend/070_anf.scm) + [126_lir_control.scm](../../../ulisp/lir/126_lir_control.scm))**:
   - `lir-compile-let`（`126_lir_control.scm:168`）は、同一基本ブロック内や呼び出しを跨がない短命一時変数 `%t0..%t63` を含むすべての `let` 束縛に対して無条件に `(%store %rsp curr-si %rax)` を発行し、参照時に毎回 `(%load %rax %rsp slot)` を発行する。
2. **関数入口のパラメータ無条件スピル ([130_lir.scm](../../../ulisp/lir/130_lir.scm))**:
   - `lir-compile-function`（`130_lir.scm:508-512`）は関数先頭で毎回 `%rdi`, `%rsi`, `%rdx`, `%rcx`, `%r8`, `%r9` を `[rsp - 24 - 8*i]` へ退避し、葉関数や最初の呼び出し前の参照であっても毎回 `[rsp - N]` から `%rax` へ再ロードしている。
3. **二項演算・比較・引数評価の一時スピル ([129_lir_primitives.scm](../../../ulisp/lir/129_lir_primitives.scm), [128_lir_branch_fusion.scm](../../../ulisp/lir/128_lir_branch_fusion.scm), [124_lir_call_abi.scm](../../../ulisp/lir/124_lir_call_abi.scm))**:
   - オペランドがローカル変数や即値である場合、または空きスクラッチ/callee-saved レジスタが利用可能な場合でも、左辺評価結果を `[rsp - N]` に退避してから右辺を評価し、再度 `[rsp - N]` からロード・比較している。
4. **LIR `mem2reg` と DSE の Scheme 関数適用外 ([132_lir_braun_ssa.scm](../../../ulisp/lir/132_lir_braun_ssa.scm), [133_lir_peephole.scm](../../../ulisp/lir/133_lir_peephole.scm))**:
   - `132_lir_braun_ssa.scm` の `%c99-m2r-managed-or-unsafe-body?`（L816）が `%block`・`%call-closure`・`(%stack off)` を含む関数を全面拒否するため Scheme 関数がほぼ対象外となっている。また `133_lir_peephole.scm` の `lir-eliminate-dead-stack-stores`（L544）はラベル・分岐・呼び出し毎に生存集合を `(all-except)` にリセットするためブロック跨ぎの不要ストアを除去できない。

---

## 2. トレーサビリティ & 16専門エージェント多角的レビュー / Traceability & Multi-Agent Review

- 関連資料:
  - [Issue #945](945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（計測・ベンチマーク基盤）
  - [Issue #934](934-implement-temporary-stack-spill-dead-store-elimination-and-expr-register-forwarding.md)（C-TU モードでの一時スピル DSE / レジスタ転送）
  - [Issue #951](951-disable-safepoint-injection-in-single-threaded-compiler-modules.md) 〜 [Issue #960](960-eliminate-unreferenced-functions-via-reachability-or-gc-sections.md)（前段のサイズ・速度最適化群）
  - [Issue #966](../966-separate-mir-ssa-and-machine-lir-for-unified-middle-end.md)（`L_mir_ssa` / `L_lir_mach` 分離構想）
  - [Issue #981](../981-unify-lir-core-fixpoint-optimization-for-scheme-and-c99.md)（`L_lir_core` 不動点最適化共通化）
- 16専門エージェントレビュー観点（主要指摘事項）:
  - **PM (Project Manager)**: 全バックエンド（x86-64 / AArch64 / Portable C / LIR Reference VM）互換性と stage2→stage3 ブートストラップ不動点の維持を最優先ゲートに設定。
  - **PLC (Compiler)**: `L_lir_core` 上の CFG・生存区間解析と Poletto & Sarkar (1999) 型 Linear-Scan アルゴリズムを採用し、O(N log N) の高速コンパイル（自己コンパイル時間の純増回避）を保証する。
  - **SWD (Core Engine)**: `125_lir_continuation.scm` の既存 callee-saved レジスタ割当（`%rbx`/`%r13`/`%r14`）および `124_lir_call_abi.scm` の引数レジスタ規約と干渉しない統一干渉/空きレジスタ判定を設計する。
  - **SA (Systems Architect)**: 物理レジスタ直結の即時最適化（`[rsp - N]` の空きレジスタ昇格 + CFG 跨ぎ DSE/フォワーディング）を先導し、将来の `L_mir_ssa`（#966）へ無理なく接続できる構造とする。
  - **ISS (Information Security & GC Safety)**: Copying GC（[141_backend_x86_gc.scm](../../../ulisp/backend/141_backend_x86_gc.scm)）および Hybrid/Generational GC との整合性を厳密化（後述 Phase 1 不変条件）。未初期化スロットや古いポインタの誤スキャンを絶対防止する。
  - **SQA (Quality Assurance)**: A/B 比較用フラグ（`*enable-lir-linear-scan*` / `--no-linear-scan`）によりデバッグ・バイセクト容易性を確保し、`test_gc_stress` / `test_gc_hybrid` / `test_lir_suite` / 3-stage bootstrap で回帰ゼロを検証する。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [130_lir.scm](../../../ulisp/lir/130_lir.scm)（`*enable-lir-linear-scan*` フラグ・有効判定 API 追加）
- [x] [124_lir_call_abi.scm](../../../ulisp/lir/124_lir_call_abi.scm)（単一使用引数・TCO 転送との整合検証済み）
- [x] [125_lir_continuation.scm](../../../ulisp/lir/125_lir_continuation.scm)（継続化ループの callee-saved レジスタ利用との競合回避確認）
- [x] [126_lir_control.scm](../../../ulisp/lir/126_lir_control.scm)（`let` 束縛・単一使用フォワーディング最適化）
- [x] [128_lir_branch_fusion.scm](../../../ulisp/lir/128_lir_branch_fusion.scm)（比較・タグ検査時の imm32 ゼロスピル分岐融合）
- [x] [129_lir_primitives.scm](../../../ulisp/lir/129_lir_primitives.scm)（二項演算の imm32 ゼロスピル選択・単一使用レジスタ直結）
- [x] [131_lir_safepoint.scm](../../../ulisp/lir/131_lir_safepoint.scm)（Exact GC スタックマップ・ランタイムバリア互換検証）
- [x] [132_lir_braun_ssa.scm](../../../ulisp/lir/132_lir_braun_ssa.scm)（`lir-mem2reg` 境界と Scheme LIR の棲み分け確認）
- [x] [133_lir_peephole.scm](../../../ulisp/lir/133_lir_peephole.scm)（CFG 後方生存 DSE・多段スロット転送・Linear-Scan Allocator 実装）
- [x] [pass_manager.scm](../../../ulisp/compiler/pass_manager.scm)（並列ビルドおよび `--no-linear-scan` / `--linear-scan` を [driver.scm](../../../ulisp/compiler/driver.scm) 経由統合）
- [x] [140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm)（`%load` 暗黙 `%rcx` 破壊の [nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm) 整合・スタックフレーム調整検証）
- [x] [143_backend_x86_peephole.scm](../../../ulisp/backend/143_backend_x86_peephole.scm)（`rule-x86-lea-optimize` RFLAGS 生存・disp32 ガード修正）
- [x] [141_backend_x86_gc.scm](../../../ulisp/backend/141_backend_x86_gc.scm)（GC スタックマップ・ストレス検査 PASS）
- [x] [150_backend_aarch64.scm](../../../ulisp/backend/150_backend_aarch64.scm)（AArch64 レジスタ干渉ガード・Unit Test PASS）
- [x] [160_backend_c.scm](../../../ulisp/backend/160_backend_c.scm)（Portable C バックエンド Unit Test / `test_c` PASS）
- [x] [lir_interpreter.scm](../../../ulisp/vm/lir_interpreter.scm)（LIR Reference VM 実行パリティ検証）

---

## 4. アーキテクチャ設計と段階的実装計画 / Implementation Plan

Target Branch: `perf/961-linear-scan-register-allocation`

### Phase 1: Exact/Hybrid GC スタックマップとレジスタクラス不変条件の確定

全 4 ターゲット（`x86-64` / `AArch64` / `Portable C` / `LIR Reference VM`）で意味論と GC 安全性を完全に一致させるため、レジスタ分類と GC ルート規約を明確化する。

1. **レジスタクラス定義**:
   - **固定ランタイム専用レジスタ**: `%rsp`（スタックポインタ）、`%r12`（ヒープ/ナーサリ・バンプポインタ、`AArch64` では `x19` と `%rbx` の競合に留意）
   - **スクラッチ / ABI 一時レジスタ（Caller-Saved）**: `%rax`, `%rcx`, `%rdx`, `%rdi`, `%rsi`, `%r8`, `%r9`, `%r10`, `%r11`（注: `%r10` はクロージャ呼出の self ポインタや一部のプリミティブ、`%rdx`/`%rcx`/`%r11` はプリミティブ一時値でも使用されるため命令毎の `def/use` を精密追跡する）
   - **割当可能 Callee-Saved レジスタ**: `%rbx`, `%r13`, `%r14`, `%r15`（および未使用時の `%rbp`）
2. **GC ルート安全性不変条件（[141_backend_x86_gc.scm](../../../ulisp/backend/141_backend_x86_gc.scm) / [131_lir_safepoint.scm](../../../ulisp/lir/131_lir_safepoint.scm)）**:
   - `ulisp_gc_collect` は `__ulisp_stackmap_table` の `(ret_addr, frame_size, 60-bit bitmap)` に従って `[rsp .. stack_base]` のスタックスロットを走査し、ヒープポインタをコピー先アドレスへ **インプレース書き換え（Relocate）** する。汎用レジスタ自体の値は `ulisp_alloc_slow_trampoline` に保存された caller-saved 領域のみスキャン・更新され、callee-saved レジスタ内のヒープポインタは呼出先内で退避・復元されない限り直接更新されない。
   - **規則 A（呼出・GC 非跨ぎ区間）**: 生存区間 `[start, end]` が GC を誘発し得る命令（`%call-closure`, `%direct-call`, `%c-call`, `%call-foreign`, `ulisp_alloc_slow_trampoline` / `%alloc` / `%managed-alloc` / `cons` 等）を一切跨がない変数は、ホームスタックスロットへの書き戻しすら不要で、Caller-Saved（または使用済みの空き Callee-Saved）レジスタ上に完全に常駐できる。
   - **規則 B（呼出・GC 跨ぎヒープ値の保護）**: 非末尾呼出やヒープ確保を跨ぐ可能性のあるボックス化/ポインタ値は、(i) ホームスタックスロット `[rsp - N]` に書き戻してスタックマップ 60-bit ビットマップへ登録し、呼出後はスロットから再ロードして GC リロケーション後の最新ポインタを必ず取得するか、(ii) キャッシュレジスタを使う場合も呼出前にホームスロットへストアし、呼出直後にキャッシュを無効化する。
   - **規則 C（非ヒープ・Unboxed 値の Callee-Saved 常駐）**: 即値/Fixnum/Symbol/Char/Bool のみを取り得る値や `%raw-vars` は Copying GC によるアドレス書き換え対象外であるため、呼出先境界を跨いでも Callee-Saved レジスタ（`%rbx`, `%r13`, `%r14`, `%r15`）に安全に常駐できる（呼出元のプロローグ/エピローグでフレームへ退避・復元し、未初期化ゴミを残さない）。

### Phase 2: LIR レベル Linear-Scan レジスタ割り付け & スタックスロット昇格パス

1. **CFG 構築と後方生存区間（Liveness）解析 (`L_lir_core`)**:
   - フラットな `%label` と `%block` 双方に対応した O(N) の基本ブロック分割・前後関係（Preds/Succs）構築および反復ビットベクタ/ソートリスト生存解析を実装する。
   - 命令毎の物理レジスタ `def` / `use`（暗黙の `%rax`, `%rdx`, `%rcx`, `%r10`, `%r12`, `%rsp` および呼び出し命令の Caller-Saved 破壊集合）を正確にモデル化する。
2. **エスケープしない負オフセット `[rsp - N]` の抽出**:
   - `%alloc-stack`, `%managed-alloc-stack`, `%capture-cc`, `%push-handler`, `%store-values-buf`, `%inline-asm` 等でアドレスが外部エスケープしない `-N` スロットを候補として収集する。
   - 各候補スロット `slot` について、定義・参照命令位置から生存区間 `[start, end]`、呼出・GC 跨ぎ有無、参照頻度（ループ深度重み）を算出する。
3. **Poletto & Sarkar (1999) 型 Linear-Scan 割り付け**:
   - 開始位置順に候補区間を走査し、干渉するレジスタ `def/use`・`%cont-fun` 割当済みレジスタと衝突しない物理レジスタを割り当てる。
   - 呼出・GC を跨がない区間は Caller-Saved プール（`%r8`, `%r9`, `%rsi`, `%rdi`, `%rcx` 等の未使用レジスタ）を優先使用し、プロローグ/エピローグ退避コストをゼロに抑える。
   - 呼出を跨がない高頻度ループ区間や非ポインタ（Unboxed / Fixnum 定数・整数演算）の跨ぎ区間には空き Callee-Saved レジスタ（`%rbx`, `%r13`, `%r14`, `%r15`）を割り当て、関数入口（各 `%return` / 末尾ジャンプ前）にのみ退避・復元を自動挿入する（AArch64 `x19` と `%r12`/`%rbx` エイリアシング回避のためバックエンド間の安全な割当集合制約を遵守する）。

### Phase 3: Scheme ANF / LIR 生成の改善および CFG 跨ぎ不要ストア・ロード除去

1. **生成段階での冗長スピル抑制**:
   - [126_lir_control.scm](../../../ulisp/lir/126_lir_control.scm) (`lir-compile-let`): 単一使用かつ直後または呼出無しで消費される一時束縛のストア/リロード削減を拡充する。
   - [130_lir.scm](../../../ulisp/lir/130_lir.scm) (`lir-compile-function`): 葉関数（`%call-closure`/`%direct-call`/`%c-call`/`%alloc` を含まない関数）のパラメータ `[rsp - 24 - 8*i]` 初期ストアを省略可能にし、必要時のみ参照される遅延/レジスタ直結へ移行する。
   - [129_lir_primitives.scm](../../../ulisp/lir/129_lir_primitives.scm) & [128_lir_branch_fusion.scm](../../../ulisp/lir/128_lir_branch_fusion.scm): オペランドがローカル変数/即値・レジスタ変数である場合の直接演算/比較（`(%stack off)` または物理レジスタ直接指定）パスを拡充し、一時スロット経由 `mov [rsp - N], rax` → `mov rdx, [rsp - N]` を削減する。
   - [124_lir_call_abi.scm](../../../ulisp/lir/124_lir_call_abi.scm): 引数評価時の単一引数/葉引数レジスタ直接転送範囲を拡大する。
2. **CFG 跨ぎ DSE・フォワーディング強化 ([132_lir_braun_ssa.scm](../../../ulisp/lir/132_lir_braun_ssa.scm), [133_lir_peephole.scm](../../../ulisp/lir/133_lir_peephole.scm))**:
   - `lir-eliminate-dead-stack-stores` を拡張し、基本ブロック終端後も後続 CFG 全経路の参照集合（Backward Dataflow）を用いて不要ストアを除去できるようにする（レジスタ昇格後に残った死んだプロローグスピル・`let` ストアを一括消去する）。
   - `c99-lir-mem2reg-function-body` 相当の基本ブロック内フォワーディング・定数伝播の安全サブセット（非 GC 跨ぎ区間）を `%block` / `(%stack off)` を含む Scheme 関数にも適用可能にする。

### Phase 4: フラグ制御・多ターゲット整合・段階検証

1. **トグルフラグの実装**:
   - `*enable-lir-linear-scan*`（デフォルト `#t`）および CLI オプション `--no-linear-scan` を設け、ベンチマーク A/B 計測およびデバッグ時の切替を容易にする。
2. **段階導入戦略**:
   - **Step 1**: 葉関数および基本ブロック内（呼出・GC 非跨ぎ区間）からの完全スタックレス昇格 + CFG 跨ぎ DSE。
   - **Step 2**: 呼出を跨ぐ Unboxed/Raw 変数への Callee-Saved レジスタ割当とプロローグ/エピローグ自動保存・復元。
   - **Step 3**: 呼出を跨ぐボックス化変数のブロック内キャッシュ＋呼出前ライトバック（GC セーフポイント完全保証）。
   - **Step 4**: 全バックエンド（`x86-64` / `AArch64` / `Portable C` / `LIR VM`）回帰テストおよび 3-Stage ブートストラップ不動点確認。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/build/stage3-modular` の `[rsp ...]` メモリアクセス命令数（#960 時点 `348,851` = load `173,987` + store `174,864`）が **50% 以上削減**（`174,400` 以下）されていること -> **実測 `162,339`（-53.46%）達成**
- [x] 自己コンパイル時間（5 回測定中央値、#960 時点 `4.725 s`）が **20% 以上改善**（`3.78 s` 以下）されていること -> **実測 `3.7486 s`（-20.66%）達成**
- [x] `test_gc_stress`, `test_gc_hybrid`, `test_lir_suite`, `test_passes`, `test_pass_manager`, `test_backend`, `test_c`, `test_pure_bootstrap`, `test_differential_elf` 等 `ulisp` の全テストスイートが PASS すること -> **全スイート PASS（`test_bignum` `161/161`, `test_passes` 全 Pass + Pass 1-7 `157/157`, `test_pass_manager` `138/138`, `test_ieee754` `44/44`, `pytest` 関連 `30 passed`）**
- [x] `make check_format` / `make static_analysis` / `make -C ulisp lint_sexpr` がエラー 0 件で PASS すること
- [x] `make -C ulisp bootstrap` で stage2 → stage3 モジュラーおよび自己コンパイル不動点（SHA-256 一致）を維持すること
- [x] 施策前後の実測比較表（5 回自己コンパイル時間中央値・ELF/`.text` サイズ・`size`・`objdump` 総命令数・`[rsp]` load/store 数・`mov` 比率）を本 Issue に記録すること
- [x] `verify-quality-gates` 全 PASS（相対リンクのみ・絶対パス 0 件）

---

## 6. 施策前後の実測比較表・実装サマリー (Completed 2026-11-28)

### 6.1 実装内容サマリー

1. **ランタイムフラグ・CLI 制御 ([130_lir.scm](../../../ulisp/lir/130_lir.scm), [driver.scm](../../../ulisp/compiler/driver.scm))**:
   - `*enable-lir-linear-scan*`、`lir-linear-scan-enabled?`、`set-lir-linear-scan-enabled!`、および `--linear-scan` / `--no-linear-scan` フラグ／ディレクティブを追加。
2. **ローカル／即値ゼロスピル選択・単一使用フォワーディング ([126_lir_control.scm](../../../ulisp/lir/126_lir_control.scm), [128_lir_branch_fusion.scm](../../../ulisp/lir/128_lir_branch_fusion.scm), [129_lir_primitives.scm](../../../ulisp/lir/129_lir_primitives.scm))**:
   - `let` 単一使用引数の直接評価転送、`eq?`/`eqv?`/`char=?`/`cons`/`set-car!`/`set-cdr!`/`vector-ref`/`string-ref`/`bytevector-u8-ref` のゼロスピル経路、および `imm32` 定数 (`+ - = < <= > >=`) に対するオーバーフロー検査付きゼロスピル選択を導入。
3. **x86-64 Peephole RFLAGS ガード修正 ([143_backend_x86_peephole.scm](../../../ulisp/backend/143_backend_x86_peephole.scm))**:
   - `rule-x86-lea-optimize` に `(not (x86-asm-reads-flags? (car rest)))` および `x86-disp32-int?` ガードを追加し、`add rcx, 4` + `jo .bin_imm_slow` がフラグ非更新の `lea` に誤変換されるバグ（`test_bignum` Group 10 の `fx-max + 1` 昇格）を防止。
4. **LIR CFG 後方生存 DSE・多段スロットフォワーディング・Linear-Scan Allocator ([133_lir_peephole.scm](../../../ulisp/lir/133_lir_peephole.scm), [nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm))**:
   - `lir-inst-defines-reg?` の `(%load _ _ -1/7)` 暗黙 `%rcx` 破壊報告修正、`lir-sp-label-hash` のバケット幅是正、ランタイム／例外ハンドラバリア保護、`O(1)` ダーティ管理、`lir-post-window-optimize-program`（CFG 後方生存 DSE ＋ Linear-Scan レジスタ割り付け＋冗長 `mov` 除去＋並列ビルドエクスポート更新）を実装。
   - Gauche ホスト互換のため `(cond-expand (gauche (define bitwise-ior logior) (define bitwise-and logand)) (else))` を追加。

### 6.2 `ulisp/build/stage3-modular` 計測比較（vs Issue #960 ベースライン）

ベンチマーク条件: `env ULISP_GC_PROFILE=compiler ./ulisp/build/stage3-modular < ./ulisp/build/compiler_base_in.scm > /tmp/test_bench_961.s`（ファイルリダイレクト 5 回計測、`stage3-modular` バイナリ解析）

| 指標 | Issue #960 ベースライン | Issue #961 適用後 | 変化率 / 差分 | DoD 目標 |
| --- | ---: | ---: | ---: | --- |
| **5 回自己コンパイル時間中央値** | `4.725 s` | **`3.7486 s`** (`[3.9553, 3.6957, 3.7486, 3.7555, 3.7137]`) | **`-20.66%` (`-0.976 s`)** | <= `3.78 s` (-20%) |
| **ELF バイナリサイズ** | `7,575,064 B` | **`6,743,672 B`** | **`-10.98%` (`-831,392 B`)** | — |
| **`.text` セクション (`size -A`)** | `5,230,601 B` | **`4,322,196 B`** | **`-17.37%` (`-908,405 B`)** | — |
| **`.rodata` セクション** | — | `364,760 B` | — | — |
| **`size -A` Total (`.bss` 含む)** | — | `105,667,684 B` | — | — |
| **`objdump` 総命令数** | `1,069,424` | **`1,062,454`** | `-0.65%` (`-6,970`) | — |
| **`[rsp ...]` 総アクセス数** | `348,851` | **`162,339`** | **`-53.46%` (`-186,512`)** | <= `174,400` (-50%) |
| └─ `[rsp ...]` load 命令数 | `173,987` | **`99,375`** | **`-42.88%` (`-74,612`)** | — |
| └─ `[rsp ...]` store 命令数 | `174,864` | **`62,964`** | **`-63.99%` (`-111,900`)** | — |
| **`mov*` 命令数 / 全体比率** | `605,472` (`56.62%`) | **`510,572` (`48.06%`)** | **`-15.67%` (`-8.56 pp`)** | — |

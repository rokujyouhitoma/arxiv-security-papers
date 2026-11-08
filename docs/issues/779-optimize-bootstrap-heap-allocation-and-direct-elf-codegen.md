---
ID: 779
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] コンパイラ初期アリーナヒープ一括確保およびダイレクト ELF 出力によるブートストラップ I/O 高速化 (ID: 779)

## 1. 概要 / Summary

ULisp のブートストラップおよび AOT コンパイル実行時において、コンパイラプロセスは数十万から数百万個の AST ノードや中間命令列を短時間のバッチ処理でアロケーションする。
現在、以下の 2 点がプロセスレベルでの実行速度および I/O 効率を低下させている：
1. **メモリ断片化と動的ヒープ伸長（`brk` / `mremap`）オーバーヘッド**:
   - 初期世代別ヒープ（`backend/140_backend_x86_64.scm` の Generational Collector 初期化部）において `MAP_NORESERVE` が未指定（`mov r10, 34`）であり、また `ULISP_GC_PROFILE=compiler` 時にヒープサイズを環境変数（`ULISP_COMPILER_ARENA_MB`）から柔軟に事前拡張する機構がないため、大規模コンパイル時に成熟世代のリサイズやページフォルトのオーバーヘッドが発生し得る。
2. **ダイレクト ELF 出力における 1 バイト単位 I/O と外部ツールチェーン起動オーバーヘッド**:
   - `backend/144_backend_x86_elf.scm` の [`write-elf64-bytevector`](../../ulisp/backend/144_backend_x86_elf.scm#L18-L24) が `write-char` ループで 1 バイトずつ出力しており、また `bootstrap.sh` のスモークテストや単体バイナリ生成で外部の `as`（GNU Assembler）および `ld`（GNU Linker）を毎回サブプロセス起動している。

本 Issue では、コンパイラ内部のメモリ管理および Direct-to-ELF 出力パイプラインを最適化する：
1. **コンパイラプロファイル時の初期アリーナヒープ一括確保（Huge Arena Reservation）**:
   - [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm#L1335-L1445) の世代別 GC 初期化における `sys_mmap` に `MAP_NORESERVE`（`0x4022 = 16418`）および 16GB（`17179869184`）の仮想アドレス空間予約を適用し、`ULISP_COMPILER_ARENA_MB` 環境変数による初期アリーナサイズ指定（デフォルト Nursery 2GB / Mature 2GB〜4GB）をサポートする。
2. **ダイレクト ELF バックエンド（`backend/144_backend_x86_elf.scm`）の一括出力高速化と `bootstrap.sh` 統合**:
   - [`write-elf64-bytevector`](../../ulisp/backend/144_backend_x86_elf.scm#L18-L24) を `write-bytevector` によるバルク出力へ高速化する。
   - `compiler/driver.scm` で `--target elf` / `-b elf` / `--target-elf` を完全統一し、`bootstrap.sh` に `--emit-elf` Fast-Path オプションおよび Makefile の `test_differential_elf` ターゲットを統合する。
   - なお、分割コンパイル・モジュラービルドにおける `.o`（ELF64 `ET_REL`）出力用の GNU `as` 互換コマンドオプション（`--as` / `-c`）については [Issue #783](783-support-builtin-as-assembler-cli-option-and-elf64-relocatable-object-emission.md)、複数 `.o` オブジェクトの静的リンク用 GNU `ld` 互換コマンドオプション（`--ld`）については [Issue #784](784-support-builtin-ld-static-linker-cli-option-for-elf64-objects.md) にてそれぞれ段階的に実装・連携する。

これにより、コンパイラ単体のヒープ管理およびバイナリ生成 I/O オーバーヘッドを 30〜50% 削減する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 4 章「バックエンド・コード生成およびゼロ libc ELF ビルダー」
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 5 章「3段階セルフホスティングブートストラップ連鎖と不動点検証」
- 依存・関連 Issue:
  - [Issue #616](closed/616-implement-zero-libc-direct-elf-emitter-and-assembler.md): ゼロ libc ネイティブ 2-pass アセンブラおよび ELF64 スタティックバイナリビルダーの実装
  - [Issue #617](617-establish-self-contained-bootstrap-chain-free-from-external-toolchains.md): 外部ツール完全非依存な自給自足 3-Stage セルフホスティングブートストラップの確立
  - [Issue #777](closed/777-bootstrap-compiler-alone-with-precompiled-stdlib-static-linking.md): 事前コンパイル済み標準ライブラリ静的リンクによるコンパイラ単体ブートストラップ
  - [Issue #778](closed/778-implement-modular-parallel-incremental-bootstrap.md): モジュール分割増分コンパイルと make -j 並列実行
  - [Issue #782](closed/782-fix-bootstrap-symbol-corruption-and-optimize-memory-consumption.md): ブートストラップ時のシンボル破壊・未定義参照の解消およびメモリ消費の最適化
  - [Issue #783](783-support-builtin-as-assembler-cli-option-and-elf64-relocatable-object-emission.md): ULisp における GNU as 互換コマンドラインオプション (--as / -c) と ELF64 再配置可能オブジェクト (.o) 出力の実装
  - [Issue #784](784-support-builtin-ld-static-linker-cli-option-for-elf64-objects.md): ULisp における GNU ld 互換コマンドラインオプション (--ld) と複数 ELF64 オブジェクト (.o) 静的リンカの実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (世代別 GC ヒープ初期化 `MAP_NORESERVE` 化および `ULISP_COMPILER_ARENA_MB` 環境変数スキャン)
- [ ] [ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm) (`write-elf64-bytevector` バルク書き込み最適化および直接 ELF 生成パス)
- [ ] [ulisp/backend/elf64_builder.scm](../../ulisp/backend/elf64_builder.scm) (ELF64 セグメントアライメント・W^X 検証)
- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (CLI オプション `--target elf` / `--target-elf` ヘルプ表記・パーサ連携)
- [ ] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (`--emit-elf` オプションの統合)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_differential_elf` ターゲット定義およびベンチマーク連携)
- [ ] [docs/issues/README.md](README.md) (Issue 台帳)

---

## 4. セキュリティ・信頼性脅威分析 / Threat Model & Boundary Analysis

| 脅威 / リスク | 分類 | 影響度 | 発生要因 | 緩和策 / 防御メカニズム |
| :--- | :---: | :---: | :--- | :--- |
| **仮想メモリ過剰予約による OOM キル** | CWE-400 | 高 | 8GB〜16GB のアドレス空間を事前確保する際、スワップ領域予約が強制されると `mmap` が `ENOMEM` で失敗するか OOM Killer が発動する | `sys_mmap` のフラグに `MAP_NORESERVE`（`0x4000` $\to$ `MAP_PRIVATE\|MAP_ANONYMOUS\|MAP_NORESERVE = 16418`）を指定し、実物理ページが必要になるまでオンデマンドページングさせる |
| **環境変数入力値の整数オーバーフロー・不正値** | CWE-20 / CWE-190 | 中 | `ULISP_COMPILER_ARENA_MB` に極端に小さい値（0 や負数）や上限超過値が指定された場合にヒープ領域計算が破綻する | アセンブリ数値パースルーチンにおいて下限（64MB）および上限（4096MB）へのクランプ境界チェックを強制し、不正文字列時は安全なデフォルト（2048MB）へフォールバックする |
| **ELF セグメント境界・W^X 違反** | CWE-440 | 高 | ダイレクト出力された ELF64 バイナリの `PT_LOAD` セグメントが 4KB（`0x1000`）ページ境界にアライメントされていない場合、カーネルの `sys_execve` が `ENOEXEC` を返す。また RWE（書き込み可能かつ実行可能）セグメントが存在すると W^X 原則に違反する | `elf64_builder.scm` における `PT_LOAD` セグメントの `p_align = 4096`、コードセグメント `PF_R\|PF_X`（`5`）、データセグメント `PF_R\|PF_W`（`6`）の完全分離を維持し、`tests/test_differential_elf.sh` の `readelf -l` チェックで RWE セグメント 0 件を自動検証する |
| **インメモリ機械語バッファの境界超過** | CWE-787 | 中 | パス 144a のアセンブル処理や `write-elf64-bytevector` 出力時に bytevector 境界を超えたアクセスが発生する | `write-bytevector` による境界検査付き一括出力を使用し、アセンブラセクション構築時の正確なサイズ計算を担保する |

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/779-optimize-bootstrap-heap-allocation-and-direct-elf-codegen`

### Step 1: 世代別 GC 初期アリーナ `MAP_NORESERVE` 化と `ULISP_COMPILER_ARENA_MB` 環境変数対応 (`ulisp/backend/140_backend_x86_64.scm`)
1. [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm#L1335-L1347) の Generational Collector 初期化ルーチンにおいて：
   - `sys_mmap` の予約サイズ `rsi` を `17179869184`（16GB 仮想アドレス空間）へ拡張し、フラグ `r10` を `16418`（`MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE = 0x4022`）に変更する。
2. `.L_profile_compiler`（1428行目付近）において：
   - 環境変数 `ULISP_COMPILER_ARENA_MB=` をスキャンするルーチンを追加し、十進数文字列が指定されている場合は MB 単位（64MB〜4096MB の範囲にクランプ）をバイト数（`<< 20`）へ変換して Nursery / Mature サイズ（`r12`, `r13`）に設定する（未設定時はデフォルト 2048MB = `2147483648`）。
   - リファレンス文字列 `.L_str_env_arena_mb:` (`.ascii "ULISP_COMPILER_ARENA_MB="`) を `.rodata` セクション（1645行目付近）に追加する。

### Step 2: ダイレクト ELF バックエンドのバルク I/O 最適化と CLI 整備 (`ulisp/backend/144_backend_x86_elf.scm`, `ulisp/compiler/driver.scm`)
1. [ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm#L18-L24) の [`write-elf64-bytevector`](../../ulisp/backend/144_backend_x86_elf.scm#L18-L24) において：
   - 従来の 1 バイトごとの `write-char` ループを廃止し、標準ライブラリの `(write-bytevector bv)` + `(flush-output-port)` による一括バッファ書き込みへ置換することで、ELF 出力時のシステムコール・関数呼び出し回数を削減する。
2. [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm#L401) の [`print-compiler-help`](../../ulisp/compiler/driver.scm#L394-L413) において：
   - `-b, --target <tgt>` の対応ターゲット一覧に `elf`（`x86_64, elf, c, aarch64, lir`）および `--target-elf` オプションを明記する。

### Step 3: `ulisp/bootstrap.sh` への `--emit-elf` Fast-Path の統合と `ulisp/Makefile` ターゲット整備
1. [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) に `BOOTSTRAP_EMIT_ELF="${BOOTSTRAP_EMIT_ELF:-0}"` および `--emit-elf` オプションを追加する：
   - `--emit-elf` 指定時、`verify_and_promote` 内のスモークテスト（`42` のコンパイルと実行）において `as` および `ld` を起動せず、`"$final_compiler" --target-elf -o "$BUILD_DIR/smoke_test"` によって直接実行可能 ELF64 バイナリを生成・実行して出力 `42` を検証する。
   - また `--monolithic --emit-elf` 組み合わせ時には、`run_stage` で `--target-elf` を用いて直接次ステージの実行可能 ELF を出力可能にする。
2. [ulisp/Makefile](../../ulisp/Makefile) に `test_differential_elf` ターゲットを追加（または `.PHONY` に登録）し、`bash tests/test_differential_elf.sh` を `make -C ulisp test_differential_elf` で単体実行できるようにする。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `ulisp/backend/140_backend_x86_64.scm` の Generational GC 初期化で `MAP_NORESERVE`（`16418`）が適用され、`ULISP_GC_PROFILE=compiler` および `ULISP_COMPILER_ARENA_MB=2048` 指定時に安定した高速実行が確認できること。
- [ ] `ulisp/backend/144_backend_x86_elf.scm` の `write-elf64-bytevector` が `write-bytevector` による一括出力に最適化されていること。
- [ ] `--target-elf` / `-b elf` による直接 ELF バイナリ出力が、`make -C ulisp test_differential_elf`（`tests/test_differential_elf.sh` 全 12 ケース + W^X 検査）および `./bootstrap.sh --quick --emit-elf` のスモークテスト（`42`）を 100% PASS すること。
- [ ] 3-Stage ブートストラップ（`make -C ulisp bootstrap` および `make -C ulisp bootstrap_modular`）がビット完全一致（`0 bytes diff`）を維持すること。
- [ ] ルート品質ゲート（`make check_format static_analysis py_compile`）がエラー 0 件で通過すること。

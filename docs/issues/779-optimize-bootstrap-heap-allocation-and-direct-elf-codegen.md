---
ID: 779
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] コンパイラ初期アリーナヒープ一括確保およびダイレクト ELF 出力によるブートストラップ I/O 高速化 (ID: 779)

## 1. 概要 / Summary

ULisp のブートストラップ実行時において、コンパイラプロセスは数十万から数百万個の AST ノードや中間命令列を短時間のバッチ処理でアロケーションする。
現在、以下の 2 点がプロセスレベルでの実行速度を低下させている：
1. **メモリ断片化と動的ヒープ伸長（`brk` / `mremap`）オーバーヘッド**:
   - 初期ヒープや動的リサイズにおいてメモリ伸長システムコールが介入し、ページフォールトおよびカーネル空間遷移によるオーバーヘッドを招いている。
2. **巨大アセンブリテキスト（12MB〜15MB）のディスク I/O と外部ツールチェーン起動**:
   - コンパイラがアセンブリ文字列をディスクへ書き出し、外部の `as`（GNU Assembler）がそれを再パースして機械語へ変換、さらに `ld` がリンクするという 3 重のプロセス起動とテキストシリアライズ/デシリアライズが発生している。

本 Issue では、コンパイラ内部のメモリ管理および出力パイプラインを最適化する：
1. **コンパイラプロファイル時の初期アリーナヒープ一括確保（Huge Arena Reservation）**:
   - `ULISP_GC_PROFILE=compiler` 時、起動時に 4GB〜8GB の仮想アドレス空間を一括で事前マッピング（`mmap` / `MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE`）し、コンパイル中のヒープ伸長・断片化・システムコールオーバーヘッドをゼロ化する。
2. **ダイレクト ELF バックエンド（`backend/144_backend_x86_elf.scm`）の活用と拡張**:
   - 既存のネイティブ ELF ビルダー（[tests/test_differential_elf.sh](../../ulisp/tests/test_differential_elf.sh) で 100% 差分等価性検証済み）を活用し、アセンブリテキストを介さずメモリ内で直接 ELF オブジェクト（`.o`）または実行可能バイナリを出力する Fast-Path をブートストラップおよびビルドターゲットに統合する。

これにより、コンパイラ単体の実行時間およびツールチェーンオーバーヘッドを 30〜50% 削減する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 4 章「バックエンド・コード生成およびゼロ libc ELF ビルダー」
- 依存・関連 Issue:
  - [Issue #616](closed/616-implement-zero-libc-direct-elf-emitter-and-assembler.md): ゼロ libc ネイティブ 2-pass アセンブラおよび ELF64 スタティックバイナリビルダーの実装
  - [Issue #617](617-establish-self-contained-bootstrap-chain-free-from-external-toolchains.md): 外部ツール完全非依存な自給自足 3-Stage セルフホスティングブートストラップの確立
  - [Issue #777](777-bootstrap-compiler-alone-with-precompiled-stdlib-static-linking.md): 事前コンパイル済み標準ライブラリ静的リンクによるコンパイラ単体ブートストラップ
  - [Issue #778](778-implement-modular-parallel-incremental-bootstrap.md): モジュール分割増分コンパイルと make -j 並列実行

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (ヒープ初期化および mmap 設定)
- [x] [ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm) (直接 ELF 生成パス)
- [x] [ulisp/backend/elf64_builder.scm](../../ulisp/backend/elf64_builder.scm) (ELF64 バイナリビルダー)
- [x] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (CLI オプション `--target elf` 連携)
- [x] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (ELF 直接出力オプションの統合)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (ベンチマークおよびターゲット追加)
- [x] [docs/issues/README.md](README.md) (Issue 台帳)

---

## 4. セキュリティ・信頼性脅威分析 / Threat Model & Boundary Analysis

1. **メモリ過剰確保による OOM キル（Virtual Memory Overcommit & OOM Killer）**:
   - *脅威*: 4GB〜8GB のアドレス空間を事前確保する際、物理メモリのコミットが急増するとホストマシンの OOM Killer が発動しビルドが強制終了する。
   - *対策*: `MAP_NORESERVE`（Linux フラグ 0x4000）を適用し、実ページが必要になるまで物理 RAM のアロケーションを遅延（オンデマンド・デマンドページング）させる。
2. **ELF セグメント境界およびアライメント違反（System V ABI Compliance）**:
   - *脅威*: ダイレクト出力された ELF バイナリが 4KB ページ境界に正しくアライメントされていない場合、カーネルの `sys_execve` が `ENOEXEC`（Exec format error）を返して起動に失敗する。
   - *対策*: `elf64_builder.scm` における PT_LOAD セグメントの `p_align`（4096バイト）および `p_vaddr` 計算を厳格化し、Differential ELF テスト（`test_differential_elf.sh`）で全バイナリの実行整合性を検証する。
3. **インメモリ機械語バッファのオーバーフロー**:
   - *脅威*: 巨大プログラムの直接アセンブル時に、テキストセクションやリロケーションテーブルの bytevector が上限に達してクラッシュする。
   - *対策*: Pass 144a アセンブラバッファの動的伸張（Geometric Reallocation）を保証し、境界外書き込みを完全に防止する。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/779-optimize-bootstrap-heap-allocation-and-direct-elf-codegen`

### Step 1: コンパイラ初期アリーナヒープサイズ環境変数（`ULISP_COMPILER_ARENA_MB`）の導入
- `backend/140_backend_x86_64.scm` の `.L_profile_compiler` において、環境変数 `ULISP_COMPILER_ARENA_MB` のスキャンを追加（未設定時は 4GB デフォルト）。
- システムコール `sys_mmap` に `MAP_NORESERVE` を指定し、安全なオンデマンド巨大アリーナを確立。

### Step 2: ダイレクト ELF バックエンド（`--target elf`）の安定化と拡張
- `compiler/driver.scm` における `--target elf` の出力パイプラインを点検。
- `144_backend_x86_elf.scm` において、`as` / `ld` を起動せずメモリ内から直接 ELF バイナリをファイルへストリーミング出力する性能を計測。

### Step 3: `bootstrap.sh` への `--emit-elf` Fast-Path の統合
- `bootstrap.sh` に `--emit-elf` オプションを追加し、各ステージバイナリをアセンブリテキストを介さずダイレクトに生成可能にする。
- 不動点検証においては ELF バイナリの `.text` セクションのハッシュ一致、または `-b x86` との相互互換性を保証。

### Step 4: ベンチマークとプロファイリング
- ディスク I/O 削減量（数十MB のテキストファイル書き出し・読み込み削減）とビルド時間の短縮率（20〜40% 高速化）を定量測定。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `ULISP_GC_PROFILE=compiler` 実行時に余計なメモリリサイズシステムコールが抑制され、安定した高速実行が確認できること。
- [ ] `--target elf` による直接 ELF バイナリ出力が、`tests/test_differential_elf.sh` 全ケースおよびスモークテスト（`42`）を 100% PASS すること。
- [ ] `as` および `ld` のプロセス起動オーバーヘッドが排除され、コンパイル・ビルドパイプラインの高速化が達成されること。
- [ ] `make check_format static_analysis py_compile` がエラー 0 件で通過すること。

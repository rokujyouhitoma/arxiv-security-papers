---
ID: 616
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Scheme ネイティブ x86-64 マシン語エンコーダおよび ELF64 実行可能バイナリ直接出力バックエンドの実装 (ID: 616)

## 1. 概要 / Summary
現在 ULisp は LIR（Low-level Intermediate Representation）からテキスト形式の GNU アセンブリコード（`.s`）を出力し、外部のアセンブラ・リンカにバイナリ変換を委ねている。外部ツールチェイン（GNU binutils）への依存を完全に解消し、コンパイル速度を極限まで引き上げるため、Scheme のバイト列（`bytevector`）を用いて x86-64 マシン語を直接エンコードし、スタンドアロンな ELF64 実行可能バイナリ（`ET_EXEC`）を直接生成する「Direct-to-ELF バックエンド」を新設する。

本機能により、ULisp は外部のアセンブラ（`as`）やリンカ（`ld`）を一切起動することなく、ソースコード（`.scm`）から直接実行可能ファイルを出力できる単一自己完結型（Self-contained）コンパイラへと進化する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 2 章、第 7 章)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/spec_pipeline.md)
  - System V ABI AMD64 Architecture Processor Supplement (ELF64 仕様)
- **関連 Issue**:
  - Issue 596: Backend層: define-language L_asm 導入による命令選択とコード生成の2段階分離
  - Issue 607: 外部シンボル（extern）参照解決と標準ライブラリ・コンパイラの2分割 .o 静的リンク基盤の導入
  - Issue 608: Nanopass・モジュール単位の完全分割コンパイル（.o）および増分ビルド基盤の実装
  - Issue 615: ビルドパイプラインからの GCC 呼出し排除と GNU as / ld 直接駆動への移行
  - Issue 617: 外部ツール完全非依存な自給自足 3-Stage セルフホスティングブートストラップの確立

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm) (新規: x86-64 マシン語エンコーダおよび ELF64 ビルダ)
- [ ] [ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm) (Pass 144 の登録およびターゲットディスパッチ)
- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (`--target-elf` または直接実行バイナリ出力 CLI オプションの追加)
- [ ] [ulisp/backend/backend_lang.scm](../../ulisp/backend/backend_lang.scm) (マシン語バイトコード表現の型定義)
- [ ] [ulisp/tests/passes/test_144_backend_x86_elf.scm](../../ulisp/tests/passes/test_144_backend_x86_elf.scm) (新規: 直接生成 ELF の構文・実行検証テスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (Direct-to-ELF 検証ターゲットの追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/616-implement-native-x86-machine-code-encoder-and-direct-elf-generator`

1. **x86-64 マシン語エンコーダ（Pass 144a）の実装**:
   - `L_asm_x86` の命令（`mov`, `add`, `sub`, `cmp`, `jmp`, `je`, `call`, `ret`, `syscall`, `lea` 等）を x86-64 バイト列へ変換する関数群を実装。
   - REX プレフィックス（64ビット演算・R8〜R15 レジスタ指定）、ModR/M バイト、SIB バイト、ディスプレースメント、イミディエイト値の決定論的バイナリエンコード。
2. **ラベルおよび前方参照（Relocation）解決**:
   - 2 パスアセンブル方式:
     - Pass 1: 各基本ブロックおよび命令の相対オフセットを計算し、ラベルアドレステーブルを構築。
     - Pass 2: 相対ジャンプ（`rel32`）および RIP 相対メモリアクセスのアドレス差分をパッチ。
3. **ELF64 ヘッダおよびセグメント構築（Pass 144b）**:
   - `ELF Header` (64-bit, Little Endian, x86-64, Entry Point `_start`)。
   - `Program Header`:
     - テキストセグメント (`PT_LOAD`, Flags: `PF_R | PF_X`)
     - データ/定数セグメント (`PT_LOAD`, Flags: `PF_R | PF_W`)
   - 静的実行可能ファイル（`ET_EXEC`）としてメモリマップ可能な ELF 構造を `bytevector` 上に構築し、ファイルへ書き出す。
4. **Freestanding ランタイムのバイナリインライン化**:
   - [142_backend_x86_freestanding.scm](../../ulisp/backend/142_backend_x86_freestanding.scm) の I/O および GC プリミティブをテキストではなくマシン語エンコード関数群として組込み。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] テキストアセンブラ（`as`）を介さず、Scheme から直接スタンドアロン ELF64 実行バイナリを出力できること。
- [ ] 生成された ELF バイナリが Linux x86-64 上で直接 `./output_bin` として実行でき、期待通りの計算結果・I/O 出力を得られること。
- [ ] `readelf -l` および `objdump -d` で生成バイナリのセグメント配置および逆アセンブル結果が正常であること。
- [ ] `make test_144` 単体テストが 100% PASS すること。

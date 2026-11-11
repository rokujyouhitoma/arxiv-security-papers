---
ID: 617
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] 外部ツール完全非依存な自給自足 3-Stage セルフホスティングブートストラップの確立 (ID: 617)

## 1. 概要 / Summary

現在 ULisp は、Linux システムコールを直接発行する Freestanding ランタイム（Pass 142）、バイトコード/マシン語直接生成バックエンド（Pass 144: [Issue #616](closed/616-implement-native-x86-machine-code-encoder-and-direct-elf-generator.md)）、内蔵 x86-64 アセンブラ（`ulisp --as` / `-c`: [Issue #783](closed/783-support-builtin-as-assembler-cli-option-and-elf64-relocatable-object-emission.md)）、および内蔵 ELF64 静的リンカ（`ulisp --ld`: [Issue #784](closed/784-support-builtin-ld-static-linker-cli-option-for-elf64-objects.md)）を備えており、理論上は外部の GNU binutils（`as`, `ld`）や C コンパイラ（`gcc`, `clang`）なしに単体で実行可能バイナリを生成する完全な能力を Scheme 内部に保有している。

しかしながら、現行の 3-Stage ブートストラップドライバ（[ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) および [ulisp/Makefile](../../ulisp/Makefile)）は依然としてホスト環境の GNU `as` および `ld` を無条件にサブプロセス呼び出ししており、以下の深刻な課題と制約を抱えている：

1. **最小環境・隔離コンテナにおけるビルド不全**:
   - GNU binutils や Python 等の開発ツールがインストールされていない軽量環境（Alpine Linux、minimal scratch コンテナ、セキュリティ監査用隔離 CI 環境）において、ULisp のブートストラップ検証を実行できない。
2. **外部プロセス起動・中間ファイル I/O オーバーヘッド**:
   - Stage 1〜3 の各世代において、数万行規模のアセンブリ（`.s`）をディスクに書き出し、外部の `as` および `ld` を繰り返し fork/exec することで、大幅なファイル I/O とプロセス生成コストが発生している。
3. **自己完結（Self-contained）性・自給自足性の未達**:
   - プログラミング言語処理系としての究極の目標である「シードバイナリ 1 つと Scheme ソースコードのみから、一切の外部ツールを借りずに自己を再構築する完全セルフホスティング」がパイプラインとして未整備であった。

本 Issue では、Pass 144（Direct-to-ELF バックエンド）および内蔵アセンブラ/リンカ（`--as` / `--ld`）の成果を統合し、ホスト環境の `gcc`, `clang`, `as`, `ld`, `python` 等の外部ツールに一切依存しない**完全自給自足（Pure Self-Hosting）ブートストラップ連鎖**を確立する。

本機能では以下の 2 つの完全自立ブートストラップ経路を提供する：
- **Direct-to-ELF モード（`--pure-elf`）**: 中間 `.s` / `.o` ファイルの生成を完全にスキップし、S 式から直接 ELF64 実行バイナリをインメモリ出力する最速の自己完結連鎖。
- **内蔵ツールチェインモード（`--pure-tools` / `--pure`）**: 中間アセンブリ・分割コンパイル（Split-Link）を維持しつつ、外部 `as` / `ld` の代わりに ULisp 自身（シードバイナリおよび各 Stage の生成バイナリ）の `--as` / `--ld` を駆動する連鎖。

リポジトリ内のコミット済みシードバイナリ（`ulisp/bin/ulisp-boot`）を出発点として `stage1` を生成し、`stage1` が `stage2` を、`stage2` が `stage3` を生成して、`stage2` と `stage3` のビット単位完全一致（Fixed-Point: 不動点）を達成する。

---

## 2. トレーサビリティ / Traceability

- **正典仕様書**:
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
    - 第 4 章「バックエンド・コード生成およびゼロ libc ELF ビルダー」
    - 第 5 章「3段階セルフホスティングブートストラップ連鎖と不動点検証」
    - 第 7 章「バックエンド・W^X セキュリティ」
  - [[DSN-36] Zero-libc Pure Scheme Bare Metal Runtime](../designs/DSN-36-zero_libc_pure_scheme_bare_metal_runtime.md)
  - [ULisp ポータブルビルドガイド](../../ulisp/docs/guide_portable_build.md)
  - [ULisp パイプライン仕様書](../../ulisp/docs/spec_pipeline.md)
- **依存・関連 Issue**:
  - [Issue #541](closed/541-implement-fast-bootstrap-seed-and-subsecond-build-pipeline.md): ブートストラップシード導入による高速ビルドパイプラインの構築
  - [Issue #579](closed/579-establish-3-stage-bootstrap-fixed-point-verification-protocol.md): 3-Stage Bootstrap の固定点（Fixed-Point）自動検証プロトコルの確立
  - [Issue #605](closed/605-enhance-bootstrap-diagnostics-and-fallback-trace.md): bootstrap.sh におけるコンパイル失敗時の自動診断機能の導入
  - [Issue #615](closed/615-decouple-gcc-driver-and-migrate-to-direct-as-ld-invocation.md): ビルドパイプラインからの GCC 呼出し排除と GNU as / ld 直接駆動への移行
  - [Issue #616](closed/616-implement-native-x86-machine-code-encoder-and-direct-elf-generator.md): Scheme ネイティブ x86-64 マシン語エンコーダおよび ELF64 実行可能バイナリ直接出力バックエンドの実装
  - [Issue #777](closed/777-bootstrap-compiler-alone-with-precompiled-stdlib-static-linking.md): 事前コンパイル済み標準ライブラリ静的リンクによるコンパイラ単体ブートストラップ
  - [Issue #778](closed/778-implement-modular-parallel-incremental-bootstrap.md): モジュール分割増分コンパイルと make -j 並列実行
  - [Issue #779](closed/779-optimize-bootstrap-heap-allocation-and-direct-elf-codegen.md): コンパイラ初期アリーナヒープ一括確保およびダイレクト ELF 出力によるブートストラップ I/O 高速化
  - [Issue #783](closed/783-support-builtin-as-assembler-cli-option-and-elf64-relocatable-object-emission.md): ULisp における GNU as 互換コマンドラインオプション (--as / -c) と ELF64 再配置可能オブジェクト (.o) 出力の実装
  - [Issue #784](closed/784-support-builtin-ld-static-linker-cli-option-for-elf64-objects.md): ULisp における GNU ld 互換コマンドラインオプション (--ld) と複数 ELF64 オブジェクト (.o) 静的リンカの実装
  - [Issue #786](closed/786-support-one-step-executable-compilation-with-automatic-stdlib-linking.md): ULisp ドライバにおける 1 ステップ実行バイナリ生成と標準ライブラリ (ulisp_stdlib.o) 自動リンクパイプラインの実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh)
  - 外部ツール非依存オプション `--pure` (`--pure-self-host`), `--pure-elf`, `--pure-tools` の新設
  - ツールチェインルーティング抽象化（外部 `as`/`ld` と内蔵 `--as`/`--ld` の自動切り替え）
  - Direct-to-ELF モードにおける `.s` / `.o` 不要の 1 ステップ連鎖実行
  - 外部ツール（`as`, `ld`, `python`, `gosh`）非存在時の安全な自己完結フォールバック
- [ ] [ulisp/Makefile](../../ulisp/Makefile)
  - `bootstrap_pure` ターゲットの新設（`./bootstrap.sh --pure`）
  - `bootstrap_pure_elf` ターゲットの新設（`./bootstrap.sh --pure-elf`）
  - `test_pure_bootstrap` ターゲットの新設（外部ツール遮断環境下での検証）
  - `USE_BUILTIN_TOOLS ?= 0` フラグによる Makefile レベルの as/ld 内蔵ツール置換対応
- [ ] [ulisp/tests/test_pure_bootstrap.sh](../../ulisp/tests/test_pure_bootstrap.sh) (新規テストスイート)
  - 隔離テスト環境の構築（`PATH` の先頭にダミーの失敗スタブ `gcc`, `clang`, `as`, `ld`, `python`, `python3`, `gosh` を配置）
  - 外部ツールが一切利用できない状況下での 3-Stage ブートストラップ完遂および Fixed-Point 一致検証
  - 生成された `scheme-stage2` による標準スモークテストおよび自己再構築テストのパス確認
- [ ] [ulisp/docs/spec_pipeline.md](../../ulisp/docs/spec_pipeline.md)
  - 第 8 章「完全自給自足（Pure Self-Hosting）ブートストラップ仕様」の追記
  - Direct-to-ELF 連鎖および内蔵ツールチェイン連鎖のアーキテクチャ記述
- [ ] [ulisp/docs/guide_portable_build.md](../../ulisp/docs/guide_portable_build.md)
  - ゼロ外部依存ビルド（Zero-External-Dependency Build）の手順と前提条件の更新
- [ ] [docs/issues/README.md](README.md)
  - Issue 617 ステータス更新（New -> In Progress）

---

## 4. セキュリティ・信頼性脅威分析 / Threat Model & Boundary Analysis

本機能はブートストラップ連鎖およびコンパイラバイナリの自己再生成に関わるため、以下のセキュリティリスクと緩和策を厳格に適用する：

| 脅威 / リスク | 分類 | 影響度 | 発生要因 | 緩和策 / 防御メカニズム |
| :--- | :---: | :---: | :--- | :--- |
| **Trusting Trust / シードバイナリ汚染 (Ken Thompson Hack)** | CWE-506 | 重大 | リポジトリに保持するシードバイナリ（`bin/ulisp-boot`）が悪意あるコードを含んでいた場合、自己再コンパイル後もバックドアが継承される | (1) Diverse Double-Compiling (DDC) 原則に基づき、リファレンス Scheme 処理系（Gauche / ILisp）から生成したバイナリとシードバイナリ出力のセマンティクス等価性を検証可能にする。<br>(2) Stage 2 と Stage 3 の bit-for-bit 不動点一致（Fixed Point）を強制し、世代をまたぐ非決定論的コード挿入を検知する。 |
| **PATH 改ざん・外部ツールハイジャック脆弱性** | CWE-426 | 高 | ホスト環境の `PATH` に悪意ある `as` や `ld`、`gcc` ラッパーが配置されている場合に、ブートストラップ中に不正コードが実行される | `--pure-self-host` モードではホストの `PATH` を探索せず、明示的な絶対・相対パス（`$ULISP_DIR/bin/ulisp-boot`, `$BUILD_DIR/scheme-stage1`）で指定された ULisp 内蔵バイナリのみを実行する。 |
| **Direct-to-ELF における不正セグメント配置・バッファ破壊** | CWE-119 / CWE-787 | 高 | Pass 144 のバイナリ合成処理において、セグメントのオフセット計算や仮想アドレス配置に不整合が生じ、バイナリロード時にセグフォやメモリ破壊が発生する | ELF ヘッダ（`Elf64_Ehdr`）およびプログラムヘッダ（`Elf64_Phdr`）のサイズ・4KB ページアライメント（`0x1000`）を静的アサーション検証し、生成直後に `readelf -l` / `readelf -S` による構造整合性検証を自動実行する。 |
| **非実行可能スタック（Non-W^X Stack）の欠落** | CWE-250 / CWE-732 | 中 | 直接出力された ELF バイナリに `PT_GNU_STACK` が含まれていない場合、Linux カーネルが互換モードとしてスタックを実行可能（NX 無効）にしてしまう | 内蔵リンカおよび Direct-to-ELF ビルダーにおいて、常に `p_type = PT_GNU_STACK`（`0x6474e551`）、`p_flags = 6 (PF_R | PF_W)` を注入し、厳格な W^X スタック規約を強制する。 |
| **自己コンパイル時の無限再帰・メモリ枯渇 (Compiler DoS)** | CWE-400 | 中 | コンパイラの大規模なマクロ展開や末尾再帰最適化の不全により、自己コンパイル中にメモリが肥大化し OOM やハングアップが発生する | 各 Stage の実行に `BOOTSTRAP_STAGE_TIMEOUT`（デフォルト 600 秒）を設定し、`ULISP_GC_PROFILE=compiler` による初期アリーナヒープの一括確保と GC 閾値チューニングを適用する。 |

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/617-establish-self-contained-bootstrap-chain-free-from-external-toolchains`

### 5.1 アーキテクチャ概要

```mermaid
flowchart TD
    subgraph TraditionalChain ["従来のブートストラップ連鎖 (GNU binutils 依存)"]
        Seed0["bin/ulisp-boot"] -->|出力: .s| S1_S["stage1.s"]
        S1_S -->|外部 as| S1_O["stage1.o"]
        S1_O -->|外部 ld (+stdlib.o)| Stage1_Bin["build/scheme-stage1"]
        Stage1_Bin -->|出力: .s| S2_S["stage2.s"]
        S2_S -->|外部 as| S2_O["stage2.o"]
        S2_O -->|外部 ld (+stdlib.o)| Stage2_Bin["build/scheme-stage2"]
        Stage2_Bin -->|出力: .s| S3_S["stage3.s"]
        S3_S -->|外部 as| S3_O["stage3.o"]
        S3_O -->|外部 ld (+stdlib.o)| Stage3_Bin["build/scheme-stage3"]
        Stage2_Bin -.->|cmp -s stage2.s stage3.s| FixedPoint1{"アセンブリ不動点検証"}
    end

    subgraph PureElfChain ["完全自給自足連鎖: Direct-to-ELF モード (--pure-elf)"]
        PSeed["bin/ulisp-boot\n(Direct-to-ELF)"] -->|"--target-elf -o stage1"| PS1["build/scheme-stage1\n(直接 ELF64 実行バイナリ)"]
        PS1 -->|"--target-elf -o stage2"| PS2["build/scheme-stage2\n(直接 ELF64 実行バイナリ)"]
        PS2 -->|"--target-elf -o stage3"| PS3["build/scheme-stage3\n(直接 ELF64 実行バイナリ)"]
        PS2 -.->|cmp -s scheme-stage2 scheme-stage3| PureFixedPoint{"バイナリ不動点検証\n(100% bit-for-bit 一致)"}
        PS3 -.-> PureFixedPoint
        PureFixedPoint -->|PASS| PromoteSeed["bin/ulisp-boot へ昇格"]
    end

    subgraph PureToolsChain ["完全自給自足連鎖: 内蔵ツールチェインモード (--pure-tools)"]
        TSeed["bin/ulisp-boot"] -->|コンパイル| TS1_S["stage1.s"]
        TS1_S -->|"bin/ulisp-boot --as"| TS1_O["stage1.o"]
        TS1_O -->|"bin/ulisp-boot --ld (+stdlib.o)"| TS1["build/scheme-stage1"]
        TS1 -->|コンパイル| TS2_S["stage2.s"]
        TS2_S -->|"scheme-stage1 --as"| TS2_O["stage2.o"]
        TS2_O -->|"scheme-stage1 --ld (+stdlib.o)"| TS2["build/scheme-stage2"]
        TS2 -->|コンパイル| TS3_S["stage3.s"]
        TS3_S -->|"scheme-stage2 --as"| TS3_O["stage3.o"]
        TS3_O -->|"scheme-stage2 --ld (+stdlib.o)"| TS3["build/scheme-stage3"]
        TS2 -.->|cmp -s stage2.s stage3.s| ToolsFixedPoint{"アセンブリ不動点検証"}
        TS3 -.-> ToolsFixedPoint
    end
```

### 5.2 詳細実装ステップ

#### Step 1: `ulisp/bootstrap.sh` の CLI オプション拡張と構成フラグ整理
- 新設フラグ:
  - `--pure`: 完全自立ブートストラップ（環境に応じて最適な自立モードを選択）
  - `--pure-elf`: Pass 144 Direct-to-ELF による単一プロセス直結バイナリ連鎖
  - `--pure-tools`: ULisp 内蔵 `--as` および `--ld` を用いた分割リンク/モジュラー自立連鎖
- 環境変数対応:
  - `BOOTSTRAP_PURE=${BOOTSTRAP_PURE:-0}`
  - `BOOTSTRAP_PURE_MODE=${BOOTSTRAP_PURE_MODE:-auto}` (`elf` | `tools` | `auto`)

#### Step 2: ツールチェイン呼び出し抽象レイヤの実装
- `bootstrap.sh` 内の `compile_asm` を改修し、モードに応じたルーティング関数を実装：
  ```bash
  assemble_file() {
      local stage_compiler="$1"
      local asm_in="$2"
      local obj_out="$3"
      if [ "$BOOTSTRAP_PURE_TOOLS" = "1" ]; then
          "$stage_compiler" --as --64 "$asm_in" -o "$obj_out"
      else
          as --64 "$asm_in" -o "$obj_out"
      fi
  }

  link_objects() {
      local stage_compiler="$1"
      local bin_out="$2"
      shift 2
      if [ "$BOOTSTRAP_PURE_TOOLS" = "1" ]; then
          "$stage_compiler" --ld "$@" -o "$bin_out"
      else
          ld -m elf_x86_64 -static "$@" -o "$bin_out"
      fi
  }
  ```
- Direct-to-ELF モード向けルーチン `run_stage_direct_elf`:
  ```bash
  run_stage_direct_elf() {
      local stage_name="$1"
      local stage_compiler="$2"
      local bin_out="$3"
      local scm_in="$4"
      "$stage_compiler" --target-elf -o "$bin_out" "$scm_in"
      chmod +x "$bin_out"
  }
  ```

#### Step 3: 決定論的バイナリ出力と不動点検証（Fixed-Point Verification）
- Direct-to-ELF 出力における決定論（Determinism）の担保:
  - 未使用セクションパディングのゼロ埋め徹底（既存 `elf64_builder.scm` 検証済み）。
  - 自動生成シンボル・ラベル番号の決定論的走査（同一の AST・Pass 順序であれば同一のラベル番号が割り当てられる）。
  - Stage 2 でコンパイルされた `scheme-stage2` が `ulisp_core.scm` をコンパイルして出力した `scheme-stage3` と、`scheme-stage2` そのものの ELF バイト列を `cmp -s` で比較。
  - 一致した場合は「Bit-for-Bit Deterministic Fixed Point Verified」を宣言して正常終了。

#### Step 4: `ulisp/Makefile` へのターゲット統合
- 新規ターゲット:
  - `bootstrap_pure`: `./bootstrap.sh --pure` を実行
  - `bootstrap_pure_elf`: `./bootstrap.sh --pure-elf` を実行
  - `test_pure_bootstrap`: `bash tests/test_pure_bootstrap.sh` を実行
- Makefile 内のツール変数抽象化:
  - `USE_BUILTIN_TOOLS ?= 0` が設定された場合、`AS` を `$(ULISP_BOOT) --as`、`LD` を `$(ULISP_BOOT) --ld` に設定するルールを導入。

#### Step 5: 隔離環境・外部ツール遮断テストスイートの整備 (`ulisp/tests/test_pure_bootstrap.sh`)
- テストスクリプトの流れ:
  1. 一時ディレクトリ `$BUILD_DIR/isolated_bin` を作成。
  2. ダミーのフェイルスクリプト（`#!/bin/sh; echo "EXTERNAL TOOL BLOCKED: $0" >&2; exit 99`）を `gcc`, `clang`, `as`, `ld`, `python`, `python3`, `gosh` という名前で作成し、実行権限を付与。
  3. `env PATH="$BUILD_DIR/isolated_bin:/usr/bin:/bin" ./bootstrap.sh --pure` を実行。
  4. 外部ツールが一度も呼ばれずにブートストラップが完遂し、終了コード 0 であることを検証。
  5. 生成された `build/scheme-stage2` を用いて、スモークテストおよび小規模プログラムのコンパイル・実行が正常に行えることを検証。

#### Step 6: 仕様書・ドキュメントの同期
- `ulisp/docs/spec_pipeline.md`: 「完全自給自足セルフホスティングブートストラップ」の章を追加し、モード選択と検証プロトコルを明記。
- `ulisp/docs/guide_portable_build.md`: 外部 binutils 不要のビルド手順を追記。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `ulisp/bootstrap.sh` に `--pure` (`--pure-self-host`), `--pure-elf`, `--pure-tools` コマンドライン引数が実装され、`--help` に明記されていること。
- [ ] Direct-to-ELF モード（`--pure-elf`）において、中間 `.s` および `.o` ファイルを介さず、S 式から直接 ELF 実行可能バイナリを生成する 3-Stage 連鎖が完遂すること。
- [ ] 内蔵ツールチェインモード（`--pure-tools`）において、ホストの `as` および `ld` を一切使用せず、ULisp 内蔵の `--as` と `--ld` のみで Stage 1〜3 のビルドが完遂すること。
- [ ] `stage2` と `stage3` の生成バイナリ（Direct-to-ELF）またはアセンブリ出力がビット単位（bit-for-bit identical）で 100% 一致し、不動点（Fixed Point）が検証されること。
- [ ] 隔離テストスイート `ulisp/tests/test_pure_bootstrap.sh` が作成され、ホストの `gcc`, `clang`, `as`, `ld`, `python`, `gosh` を完全に遮断（シャドウイング）した環境下で `make test_pure_bootstrap` が正常に成功（PASS）すること。
- [ ] 生成された自己ホストバイナリ（`scheme-stage2` または `scheme-stage3`）が、既存のテストスイート（`make test`）を問題なく通過すること。
- [ ] `ulisp/docs/spec_pipeline.md` および `ulisp/docs/guide_portable_build.md` に完全自給自足ブートストラップ仕様と実行手順が正確に反映されていること。
- [ ] プロジェクト全体の品質ゲート（`make verify_quality` / `verify-quality-gates`、Python 構文エラー 0 件、絶対パス完全排斥 0 件）を 100% パスすること。

---

## 7. 検証プロトコル / Verification Protocol

### 7.1 ローカル単体検証コマンド

```bash
# 1. Direct-to-ELF による自立ブートストラップ検証
cd ulisp
./bootstrap.sh --pure-elf

# 2. 内蔵ツールチェイン (--as / --ld) による自立ブートストラップ検証
./bootstrap.sh --pure-tools

# 3. 外部ツール遮断・隔離環境テストスイートの実行
bash tests/test_pure_bootstrap.sh

# 4. Makefile 経由での純粋ブートストラップターゲット検証
make bootstrap_pure
make test_pure_bootstrap

# 5. 生成バイナリによるリグレッションテスト
./build/scheme-stage2 -e '(display (+ 19 23)) (newline)' -o /tmp/test_42 && /tmp/test_42
# => 42

# 6. リポジトリ全体の品質ゲート一括検証
cd ..
make verify_quality
```

### 7.2 期待される出力結果
- `Fixed-point bootstrap verified successfully` または `Stage 2 and Stage 3 outputs are bit-for-bit IDENTICAL!` が出力されること。
- `test_pure_bootstrap.sh` において `EXTERNAL TOOL BLOCKED` 警告/エラーが一度もトリガーされず、`ALL PURE BOOTSTRAP CHECKS PASSED` が出力されること。

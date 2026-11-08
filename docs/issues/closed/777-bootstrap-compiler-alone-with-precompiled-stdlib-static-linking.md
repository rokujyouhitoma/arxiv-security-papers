---
ID: 777
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-11-08
---

# [FEAT/ENH] 事前コンパイル済み標準ライブラリ (ulisp_stdlib.o) 静的リンクによるコンパイラ単体ブートストラップの導入 (ID: 777)

## 1. 概要 / Summary

現在、[ulisp/bootstrap.sh](../../../ulisp/bootstrap.sh) は `entry_core.scm` 経由で標準ライブラリ（`lib/*.scm` 全 28 モジュール）とランタイム（`runtime/*.scm` 全 4 モジュール）をコンパイラ本体と一緒に全結合した巨大ファイル `ulisp_core.scm`（約 25,000 行 / アセンブリ約 65 万行・15MB）を、Stage 1 / Stage 2 / Stage 3 で毎回フルコンパイルしている。
しかし、標準ライブラリおよびランタイムはコンパイラのメタサーキュラーな自己変換ロジックを含んでおらず、本来セルフホスティングの不動点（Fixed Point）証明の対象とする必要はない。

先行する [Issue #772](772-unify-ulisp-test-targets-with-precompiled-stdlib-static-linking.md) では、標準ライブラリを 1 回だけ事前コンパイルしたオブジェクト（`build/ulisp_stdlib.o`）を静的リンクする方式により、テストスイートのコンパイル時間を 50〜100 倍（0.1s）に短縮した実績がある。

本 Issue では、この分割静的リンク基盤をブートストラップパイプラインへ適用する：
1. **ブートストラップ対象の極小化**:
   - `ulisp_core.scm` の全結合コンパイルを廃止し、ブートストラップ対象を **`compiler_entry.scm`（コンパイラ本体）のみ** に絞る（入力行数 25,000 行 $\to$ 9,800 行、アセンブリ 65 万行 $\to$ 22 万行）。
2. **事前コンパイル済み標準ライブラリとの静的結合**:
   - 事前ビルドされた `build/ulisp_stdlib.o` と生成された `stage_compiler.o` を `ld` で静的リンクして各ステージの実行可能バイナリ（`scheme-stage1`, `scheme-stage2`, `scheme-stage3`）を生成する。
3. **シンボルテーブル同期と ABI 整合性保証**:
   - コンパイラ単体ビルド時、コンパイラ固有シンボル（`L_cst`, `include`, `list`, `vector->list` 等）がランタイム側で `?` (`ulisp_fn__p` 等) へ名前破壊（Name Mangling Corruption）されないよう、`*known-compiler-symbols*` および `*known-runtime-symbols*` を完全同期。
4. **コンパイラ単体での不動点検証（Fixed Point Protocol）**:
   - 不動点検証を `stage2_compiler.s` と `stage3_compiler.s` の完全ビット一致（`cmp -s`）判定へ移行する。

これにより、各ステージの入力 S 式規模および出力アセンブリが半減し、各ステージのコンパイル時間が **6 分 $\to$ 約 11〜12 秒**、3-Stage 全体でも **約 35〜60 秒（従来比 18〜30 倍高速化）** へ劇的に短縮された。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 5 章「3段階セルフホスティングブートストラップ連鎖と不動点検証」
  - [[DSN-33] ULISP 包括設計仕様書](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 4 章「バックエンド・コード生成およびゼロ libc ELF ビルダー」
- 依存・関連 Issue:
  - [Issue #607](607-support-extern-symbols-and-split-stdlib-compiler-linking.md): 外部シンボル（extern）参照解決と標準ライブラリ・コンパイラの2分割 .o 静的リンク基盤の導入
  - [Issue #772](772-unify-ulisp-test-targets-with-precompiled-stdlib-static-linking.md): ULisp 標準ライブラリの事前コンパイル済みオブジェクト化と分割静的リンクへの統一
  - [Issue #776](776-introduce-quick-bootstrap-mode-and-opt-in-post-tests.md): Quick Bootstrap モード導入
  - [Issue #778](../778-implement-modular-parallel-incremental-bootstrap.md): モジュール分割増分コンパイルと make -j 並列実行
  - [Issue #779](../779-optimize-bootstrap-heap-allocation-and-direct-elf-codegen.md): コンパイラ初期アリーナヒープ一括確保およびダイレクト ELF 出力によるブートストラップ I/O 高速化
  - [Issue #780](780-optimize-symbol-to-string-with-direct-cache-and-bucket-lookup.md): symbol->string の直接キャッシュとバケット探索による O(N^2) 爆発の解消
  - [Issue #781](781-implement-record-based-symbols-with-direct-string-pointer.md): レコード指向シンボル表現による O(1) 文字列ポインタ直結とシンボルテーブル完全排除
  - [Issue #782](782-fix-bootstrap-symbol-corruption-and-optimize-memory-consumption.md): ブートストラップ時のシンボル破壊・未定義参照の解消およびメモリ消費の最適化

---

## 3. 脅威モデルと境界分析 / Threat Model & Boundary Analysis

| 脅威 / リスク | 影響度 | 発生要因 | 緩和策 / 防御メカニズム |
| :--- | :---: | :--- | :--- |
| **シンボルマングリング破壊 (CWE-704)** | 高 | コンパイラ単体コンパイル時にランタイム未登録シンボルが `"?"` (`ulisp_fn__p`) にフォールバックし、リンカ未定義参照または不正呼び出しを引き起こす | `*known-compiler-symbols*` および `*known-runtime-symbols*` に全 686 個以上のコア/構文シンボルを一括登録し、`symbol->raw-name` で既知シンボルを優先解決 |
| **ABI 不整合・未解決外部参照 (CWE-440)** | 高 | `build/ulisp_stdlib.o` と `stage_compiler.o` の間で関数呼び出し規約やクロージャレイアウト（タグ `0x2F` 等）が不整合を起こす | `compiler/module_header.scm` にて標準ライブラリとのインターフェースマクロおよび外部識別子宣言を一元管理し、リンク時静的検証を実施 |
| **ヒープ領域枯渇による OOM DoS (CWE-400)** | 高 | `(!gc none)` 指定時に 22 万行のコンパイラ自身をコンパイルする過程で 12GB の初期仮想アドレス空間を消費し尽くし `SIGSEGV` クラッシュに至る | 起動時仮想メモリ予約を `MAP_NORESERVE`（`0x4022 = 16418`）付きの 32GB（`34359738368`）に拡張し、仮想アドレス空間のみを安全にリザーブしてメモリ枯渇を防止 |
| **ブートストラップ非決定論 (CWE-697)** | 中 | マクロ展開順序やハッシュテーブル順序の揺らぎにより `stage2_compiler.s` と `stage3_compiler.s` に差分が生じる | ソート済みシンボルテーブル、決定論的カウンタ (`*symbol-counter*`, `*label-counter*`) の適用により 100% 再現可能な不動点一致を担保 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/bootstrap.sh](../../../ulisp/bootstrap.sh) : ブートストラップスクリプトの分割リンク対応（`--split-link` デフォルト化・`--monolithic` フォールバック対応）
- [x] [ulisp/Makefile](../../../ulisp/Makefile) : `build/ulisp_stdlib.o` 依存接続、`stage1_compiler.s`〜`stage3_compiler.s`、および `build/ulisp-fast` / `test_split_link` ターゲット定義
- [x] [ulisp/compiler_entry.scm](../../../ulisp/compiler_entry.scm) : コンパイラ単体エントリポイント
- [x] [ulisp/compiler/helpers.scm](../../../ulisp/compiler/helpers.scm) : `*known-compiler-symbols*`, `intern-symbol`, `symbol->raw-name`
- [x] [ulisp/lib/string.scm](../../../ulisp/lib/string.scm) : `*known-runtime-symbols*` 同期
- [x] [ulisp/backend/140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm) : `(!gc none)` 時の巨大仮想メモリ予約（`MAP_NORESERVE` 32GB: `34359738368`）
- [x] [docs/issues/README.md](../README.md) : Issue 管理台帳

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/777-bootstrap-compiler-alone-with-precompiled-stdlib-static-linking`

### Phase 1: シンボルテーブルとランタイム相互運用の完全同期
1. `ulisp/compiler/helpers.scm` および `ulisp/lib/string.scm`:
   - 全 686 個以上のコンパイラ・ランタイム共有シンボル（`include`, `include-ci`, `L_cst`, `vector->list`, `list`, `lambda`, `syntax-rules`, `make-vector-fill` 等）を `*known-compiler-symbols*` および `*known-runtime-symbols*` に完全同期。
   - `intern-symbol` において `symbol->raw-name` を呼び出し、未解決シンボルが `"?"` にフォールバックする現象を恒久遮断。
   - `symbol->raw-name` において O(1) シンボルキャッシュおよび `*known-compiler-symbols*` を優先ルックアップ。

### Phase 2: メモリ空間とアリーナの拡張
1. `ulisp/backend/140_backend_x86_64.scm`:
   - `(!gc none)`（GC なしモード）でのブートストラップコンパイル時、`mmap` 仮想アドレス予約サイズを従来の 12GB（`12884901888`）から **32GB（`34359738368`）** へ拡張し、フラグに `MAP_NORESERVE`（`0x4000` $\to$ `0x4022 = 16418`）を付与。
   - 物理メモリを消費せず Linux カーネルの仮想アドレス空間のみを安全にリザーブし、巨大 AST 変換時のヒープバンプポインタ `r12` の上限衝突を排除。

### Phase 3: Makefile ビルドパイプラインの整備
1. `ulisp/Makefile`:
   - `build/ulisp_stdlib.o`: `stdlib_entry.scm` から生成。
   - `build/ulisp_compiler.o`: `compiler_entry.scm` から生成。
   - `build/ulisp-fast`: `build/ulisp_stdlib.o` + `build/ulisp_compiler.o` を静的リンク。
   - `test_split_link`: 2 分割リンクバイナリの動作検証ターゲットを整備（`build/ulisp_stdlib.o` との高速静的リンク検証）。

### Phase 4: `ulisp/bootstrap.sh` の分割リンク移行と不動点検証
1. `ulisp/bootstrap.sh`:
   - デフォルト動作を `--split-link` モードへ変更。
   - Stage 1: `build/ulisp_stdlib.o` を作成（未生成時）。`bin/ulisp-boot` で `compiler_entry.scm` をコンパイル $\to$ `stage1_compiler.s` $\to$ `stage1_compiler.o` $\to$ `ulisp_stdlib.o` とリンクして `scheme-stage1` を生成。
   - Stage 2: `scheme-stage1` で `compiler_entry.scm` をコンパイル $\to$ `stage2_compiler.s` $\to$ `stage2_compiler.o` $\to$ `ulisp_stdlib.o` とリンクして `scheme-stage2` を生成。
   - Stage 3: `scheme-stage2` で `compiler_entry.scm` をコンパイル $\to$ `stage3_compiler.s` $\to$ `stage3_compiler.o` $\to$ `ulisp_stdlib.o` とリンクして `scheme-stage3` を生成。
   - 不動点判定: `cmp -s stage2_compiler.s stage3_compiler.s`（完全ビット一致）。
   - `--monolithic` オプション指定時は従来の `ulisp_core.scm` 全結合ビルドへフォールバック可能。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `build/ulisp_stdlib.o` と静的リンクしたコンパイラバイナリ（`build/ulisp-fast`）が正常に動作し、`make -C ulisp test_split_link` が 100% PASS すること（`Output: Hello from split-linked ULisp!579`）。
- [x] `stage2_compiler.s` と `stage3_compiler.s` がビット単位で 100% 完全一致（Fixed Point Verified: `0 bytes diff`）すること。
- [x] 3-Stage ブートストラップが約 3 分前後（実測：`ulisp_stdlib.o` ビルド込みで **1分01秒**、キャッシュ済み時 **約35秒**）で完走すること。
- [x] `--quick` オプション指定時、約 1 分前後（実測：**11.9秒**）で Stage 1 開発ビルドが完了すること。
- [x] ルート品質ゲート（`make check_format static_analysis py_compile`）が 0 件エラーで通過すること。

---
ID: 607
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 外部シンボル（extern）参照解決と標準ライブラリ・コンパイラの2分割 .o 静的リンク基盤の導入 (ID: 607)

## 1. 概要 / Summary
現在、ULisp コンパイラ（`130_lir.scm`）はローカル環境 `env` に存在しないシンボルに遭遇した場合、即座に未束縛変数例外（`Unbound variable in LIR`）を発生させてコンパイルを中断する。このため、別ファイルで定義された関数を呼び出すコードを単体でコンパイルすることが原理的に不可能であり、すべてのソースを 1 つのファイルに同居させる「モノリシック・単一翻訳単位」を強制されていた。

本 Issue では、LIR およびネイティブバックエンドにおいて、未束縛のグローバル関数・変数を外部シンボル参照（`extern`）として許容し、アセンブリレベルで `.globl` へのシンボル参照（`call <symbol>` 等）を出力してネイティブリンカ（`gcc -nostdlib` または `ld`）にアドレス解決を委ねる仕組みを導入する。
この基盤により、まずは「標準ライブラリ＋ランタイム（`ulisp_stdlib.o`）」と「コンパイラ本体（`ulisp_compiler.o`）」の 2 つの独立した ELF オブジェクトに分割コンパイル・静的リンクするビルドパイプラインを確立する。これにより、コンパイラ開発時に巨大な標準ライブラリ群を毎回再コンパイルする必要がなくなり、ビルドサイクルが飛躍的に高速化される。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [LIR 命令セット仕様書](../../ulisp/docs/spec_lir.md)
- **関連 Issue**:
  - Issue 502: 低レベルIR (LIR) の導入とバックエンド分離
  - Issue 529: トップレベル定義の独立コンパイル構造化および自由変数解析集合演算の高速化
  - Issue 596: Backend層: define-language L_asm 導入による命令選択とコード生成の2段階分離
  - Issue 606: ビルド時 cat 結合の廃止と R7RS include 構文によるソース位置追跡基盤の導入

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lir/130_lir.scm](../../ulisp/lir/130_lir.scm) (`lir-compile-variable` における未解決グローバルシンボルの `extern` 降格)
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (外部シンボル用 `.globl` 参照および再配置可能コード生成)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`ulisp_stdlib.o` および `ulisp_compiler.o` の分割ルールと静的リンク)
- [ ] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (2分割オブジェクトリンクによるブートストラップのサポート)
- [ ] [ulisp/tests/passes/test_130_lir.scm](../../ulisp/tests/passes/test_130_lir.scm) (外部シンボル生成テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/607-support-extern-symbols-and-split-stdlib-compiler-linking`

1. **LIR における外部参照（`%extern-ref` / `%extern-call`）の導入**:
   - `lir-compile-variable` において、`env` に見つからないシンボルでも `--allow-extern`（または分割コンパイルモード）時は即時 `error` とせず、外部グローバル参照命令を発行。
2. **x86-64 バックエンドでの再配置可能シンボル出力**:
   - 外部参照されたシンボル名を記録し、アセンブリ出力時に `.globl <symbol>` 参照として出力。
   - トップレベル定義関数は自動的に `.globl` エクスポートラベルとして宣言。
3. **2分割ビルドパイプラインの構築**:
   - `make build/ulisp_stdlib.o`: 標準ライブラリとランタイムのみをコンパイル。
   - `make build/ulisp_compiler.o`: コンパイラ本体のみをコンパイル。
   - `gcc -nostdlib -static build/ulisp_stdlib.o build/ulisp_compiler.o -o build/ulisp-fast`: リンカによる結合。
4. **ブートストラップ検証**:
   - `bootstrap.sh` において 2 分割ビルドの固定点検証を実施。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 外部シンボルを含む Scheme ファイルがコンパイルエラーにならず、正しく再配置可能アセンブリ（.s / .o）として出力されること。
- [ ] `ulisp_stdlib.o` と `ulisp_compiler.o` が独立して生成され、リンカによって単一の実行可能バイナリに結合できること。
- [ ] 分割リンクによって生成されたバイナリが自己ホストテストおよびスモークテストに合格すること。
- [ ] `make test_unit` および `bash ulisp/test.sh` が 100% PASS すること。

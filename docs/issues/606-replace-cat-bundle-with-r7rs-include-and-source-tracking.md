---
ID: 606
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] ビルド時 cat 結合の廃止と R7RS include 構文によるソース位置（ファイル名・行番号）追跡基盤の導入 (ID: 606)

## 1. 概要 / Summary
現在、ULisp のブートストラップ（`bootstrap.sh`）およびコンパイラビルド（`Makefile`）では、多数の Scheme ソースファイル（`lib/*.scm`、`runtime/*.scm`、`compiler/*.scm`）をシェルの `cat` コマンドで物理的に結合し、15,000 行超の単一巨大ファイル（`ulisp_core.scm` や `compiler.scm`）を生成している。
この方式により、コンパイラ内部でエラー（例: `Unbound variable in LIR`）や構文エラーが発生した際、エラーの発生行が結合後の一時ファイルの行番号となり、元のどのソースファイルの何行目に起因するのかが完全に喪失している。

本 Issue では、シェルの `cat` 結合を廃止し、R7RS 準拠の `(include "path/to/file.scm")` 構文に基づく単一エントリーポイント構成へ移行する。さらに、リーダー（`reader.scm`）が `include` 展開時に「ソースファイル名」および「ファイル内行番号」を構文注釈（Source Location Annotation）として AST に保持する仕組みを導入し、エラー発生時に正確なファイル名と行番号を出力できるようにする。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [R7RS 仕様準拠ドキュメント](../../ulisp/docs/r7rs_specification_compliance.md)
- **関連 Issue**:
  - Issue 548: R7RS ライブラリ構文 (define-library / import) の静的脱糖・フラット名前空間インクルード機構の実装
  - Issue 562: R7RS 標準 16 ライブラリ定義 (*.sld) の物理配置および export/include/import 機構の統合
  - Issue 602: コンパイラ実行時における現在Nanopass・処理中トップレベル式・ソース位置のコンテキスト追跡とエラー診断ダンプの導入

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/reader.scm](../../ulisp/lib/reader.scm) (ソース位置アノテーション付き読み込み `read-with-source-info`)
- [ ] [ulisp/frontend/010_library.scm](../../ulisp/frontend/010_library.scm) (`include` 展開処理とファイル名スタック追跡)
- [ ] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (`cat` 結合処理の廃止と単一エントリーファイルへの移行)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`compiler.scm` および `build/compiler_passes.scm` の `cat` 依存解消)
- [ ] [ulisp/tests/passes/test_010_library.scm](../../ulisp/tests/passes/test_010_library.scm) (`include` ソース位置保持テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/606-replace-cat-bundle-with-r7rs-include-and-source-tracking`

1. **エントリーファイル（`entry_core.scm`）の作成**:
   - `bootstrap.sh` の `cat` 結合リストを、Scheme の `(include ...)` 列を並べた単一エントリーファイルへ置き換え：
     ```scheme
     (!gc none)
     (include "lib/posix.scm")
     (include "lib/list.scm")
     ...
     (include "compiler.scm")
     ```
2. **`include` 処理時のソースファイル名・行番号のメタデータ保持**:
   - `include` 展開時に現在のカレントファイルパスを更新し、読み込まれた S 式ノードに `(source-loc "lib/list.scm" 45 2)` などの注釈属性を付与。
3. **`bootstrap.sh` と `Makefile` の簡素化**:
   - シェルによる一時ファイル結合を排除し、直接 `entry_core.scm` をコンパイラに渡すフローへ移行。
4. **エラーレポーターとの連携**:
   - Issue 602 の診断機構と結合し、例外発生時に `[Source Location: lib/list.scm:45]` を確実に表示。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `ulisp/bootstrap.sh` 内の `cat` 結合コマンドが排除され、`include` 経由で全ステージがビルド・検証できること。
- [ ] コンパイラエラー発生時に、結合後の一時ファイル行ではなく元のファイル名と行番号が出力されること。
- [ ] `make test_unit` および `bash ulisp/bootstrap.sh` が 100% PASS すること。

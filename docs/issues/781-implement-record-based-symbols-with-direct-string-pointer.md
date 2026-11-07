---
ID: 781
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] シンボルのヒープレコード化による symbol->string 完全 O(1) ダイレクトポインタ参照の実現 (ID: 781)

## 1. 概要 / Summary

現在、ULisp においてシンボル（`symbol`）は下位 6 ビットに即値タグ（`2`）を埋め込んだ即値整数（Tagged Immediate: `imm << 6 | 2`）として表現されている。
このため、シンボル自身はその名称（文字列）への参照を物理的に保持しておらず、`symbol->string` を実行するたびに外部のハッシュテーブルや連想リストを探索（テーブル引き）する必要がある。
この設計は小規模なスクリプトでは成立するが、大規模なコンパイラパイプライン（Nanopass）のように何百万回も AST のシンボル名を参照・整形するワークロードにおいては、ハッシュ計算やバケット走査のオーバーヘッドが無視できない負荷となる。

現代の Scheme/Lisp 処理系（Chez Scheme、Racket、SBCL 等）では、シンボルは **ヒープ上の 16 バイト固定レコード（Boxed Structure）** として表現されており、オブジェクト内部に名称文字列（`string`）への直接ポインタを保持している。
これにより、`symbol->string` はテーブル探索を完全にバイパスし、アセンブリ 1 命令（`mov rax, [rsi + 8]`）の **完全な $O(1)$** で完了する。

本 Issue では、ULisp のシンボル内部表現を Chez Scheme 方式のヒープレコード型へ刷新し、シンボル文字列アクセスの理論限界（1 命令）を達成する：
1. **シンボルデータ構造の再定義**:
   - 16 バイト固定アロケーション（ヘッダタグ + ハッシュ値 / 文字列オブジェクトポインタ）。
2. **`symbol->string` の 1 命令インライン展開**:
   - LIR およびネイティブバックエンドにおいて、`symbol->string` をオフセットロード命令（`%load-field`）へインライン化。
3. **`string->symbol`（インターン）のみハッシュテーブルを利用**:
   - 文字列から一意のシンボルをルックアップ/アロケーションするインターン処理でのみハッシュテーブルを保守。
   - シンボルの同一性比較（`eq?`）は従来通りポインタ一致比較（`cmp rax, rdx`）の 1 命令を維持。

これにより、シンボル $\to$ 文字列変換の計算時間およびハッシュ探索オーバーヘッドを物理的にゼロ（0 秒）にする。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 2 章「データ型タグ付けとヒープオブジェクト表現」
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
- 依存・関連 Issue:
  - [Issue #780](780-optimize-symbol-to-string-with-direct-cache-and-bucket-lookup.md): シンボルテーブル探索の O(N^2) 爆発解消
  - [Issue #518](closed/518-implement-ulisp-s-rtyper-unboxing-and-typed-lir.md): ULisp S-RTyper 型付けと低水準 LIR 最適化

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/runtime/gc.scm](../../ulisp/runtime/gc.scm) (シンボルヒープオブジェクトのタグ定義と GC 走査)
- [ ] [ulisp/lib/string.scm](../../ulisp/lib/string.scm) (シンボル生成・インターンテーブルの更新)
- [ ] [ulisp/lir/129_lir_primitives.scm](../../ulisp/lir/129_lir_primitives.scm) (`symbol->string`, `symbol?` の LIR 命令生成)
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (アセンブリコード生成)
- [ ] [docs/issues/README.md](README.md)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/781-implement-record-based-symbols-with-direct-string-pointer`

1. **ヒープタグ規約とメモリレイアウトの策定**:
   - プライマリタグ `0b001`（ペア以外のヒープポインタ）または専用サブタグを割り当て。
   - レイアウト: `[8-byte: TAG_SYMBOL | HASH] [8-byte: STRING_PTR]`。
2. **GC (Garbage Collector) の対応**:
   - `runtime/gc.scm` の Mark/Sweep およびコピー GC において、シンボルオブジェクトの参照先 `STRING_PTR` をルート走査対象として追跡。
3. **`string->symbol` および `symbol->string` の改修**:
   - `string->symbol`: ハッシュテーブルで既存のシンボルレコードを検索。存在しない場合はヒープに 16 バイト確保して文字列ポインタを格納しテーブルに登録。
   - `symbol->string`: レコードのオフセット 8 から `STRING_PTR` をロードするだけの即値プリミティブへ置換。
4. **ブートストラップ固定点検証**:
   - 新規シンボル表現を導入した状態での 3-Stage セルフホスティングブートストラップの動作確認。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `symbol->string` がハッシュ探索を一切行わず、オフセットロード 1 命令（完全 $O(1)$）で完了すること。
- [ ] シンボルの同一性比較（`eq?`）がポインタ比較として 100% 互換性を保ち、正常に動作すること。
- [ ] GC 実行時にもシンボルおよびその名称文字列が回収されず健全に維持されること。
- [ ] 全テストスイート（`make -C ulisp test`）および 3-Stage ブートストラップが 100% PASS すること。
- [ ] `make check` / `make verify_quality` がエラー 0 件で通過すること。

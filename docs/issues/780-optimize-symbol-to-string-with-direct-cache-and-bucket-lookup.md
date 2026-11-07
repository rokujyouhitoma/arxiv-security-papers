---
ID: 780
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] シンボルテーブル探索の O(N^2) 爆発解消：重複走査撤去・バケット拡大および Direct-Mapped キャッシュ導入 (ID: 780)

## 1. 概要 / Summary

現在、[ulisp/lib/string.scm](../../ulisp/lib/string.scm) における `symbol->string` の実装は、以下の要因によってシンボル数が増加した際に計算量が $O(N^2)$ に爆発し、大規模なプログラム（標準ライブラリ全結合など）をコンパイルする際に CPU 100% かつメモリ数 GB を消費して何十分もスタックする重大な性能障害を引き起こしている：

1. **動的シンボルに対する三重走査**:
   - `symbol->string` の先頭、`%symbol-find-string` の先頭、およびフォールバック走査の先頭で、動的シンボルには存在しない静的リスト `*known-runtime-symbols*`（約200要素）を毎回二重・三重に線形走査している。
2. **フォールバック時の全シンボルフラットリスト線形走査**:
   - ハッシュバケットで見つからなかった場合、全シンボルが登録された単一線形リスト `*symbol-registry*`（数万件）を $O(N)$ で末尾まで走査している。
3. **固定小バケット（1024スロット）による衝突チェーンの肥大化**:
   - 1024 スロット固定でリハッシュがないため、衝突チェーンが長くなり探索コストが増大している。

本 Issue では、即効性のあるアルゴリズム・キャッシュ改善を実施し、$O(N^2)$ 探索を解消する：
1. **重複走査の撤去とバケット探索の完結化**:
   - `*known-runtime-symbols*` の重複呼び出しを排除。
   - `string->symbol` で必ずバケットに双方向登録されていることを保証し、`*symbol-registry*` への $O(N)$ 線形フォールバックを撤去。
2. **バケットサイズの拡大とビットマスク化**:
   - スロット数を 1024 $\to$ **16,384** または **65,536**（$2^{16}$）に拡大し、`modulo`（剰余算除算命令）を `bitwise-and`（ビット論理積）へ高速化。
3. **Direct-Mapped シンボル変換キャッシュの導入**:
   - サイズ 2048〜4096 のダイレクトマップキャッシュ配列を新設し、直近に参照されたシンボル $\to$ 文字列のペアを保持。
   - Nanopass パイプラインにおける反復的な同一シンボル参照（`lambda`, `if`, 変数名等）の 95% 以上を **$O(1)$（配列参照 1 回）** で短絡（Fast-Path）させる。

これにより、大量のシンボルを含む入力に対するコンパイル時間を数十〜数百倍高速化する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 3 章「Scheme 標準ライブラリとランタイムデータ表現」
- 依存・関連 Issue:
  - [Issue #772](closed/772-unify-ulisp-test-targets-with-precompiled-stdlib-static-linking.md): ULisp 標準ライブラリの事前コンパイル済みオブジェクト化と分割静的リンクへの統一
  - [Issue #777](777-bootstrap-compiler-alone-with-precompiled-stdlib-static-linking.md): 事前コンパイル済み標準ライブラリ静的リンクによるコンパイラ単体ブートストラップ
  - [Issue #781](781-implement-record-based-symbols-with-direct-string-pointer.md): シンボルのヒープレコード化による symbol->string 完全 O(1) ダイレクトポインタ参照の実現

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/lib/string.scm](../../ulisp/lib/string.scm)
- [ ] [ulisp/Makefile](../../ulisp/Makefile)
- [ ] [docs/issues/README.md](README.md)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/780-optimize-symbol-to-string-with-direct-cache-and-bucket-lookup`

1. **`ulisp/lib/string.scm` における探索ロジックの整理**:
   - `*known-runtime-symbols*` の検索を 1 回のみとし、ヒット時は即座にリターン。
   - バケットサイズを $2^{16} = 65536$（または $2^{14} = 16384$）へ拡張し、インデックス計算を `(bitwise-and (symbol->integer sym) 65535)` に統一。
   - `(%symbol-find-string sym bucket)` が失敗した際に `*symbol-registry*` を線形走査するコードを撤去。
2. **Direct-Mapped キャッシュの実装**:
   - `*symbol-cache-sym*` と `*symbol-cache-str*`（ベクタ長 2048 または 4096）を新設。
   - `symbol->string` の先頭で `(bitwise-and (symbol->integer sym) 2047)` をインデックスとしてキャッシュ一致を判定。
   - キャッシュミス時にのみバケット探索を実行し、結果をキャッシュへ格納。
3. **ベンチマークと性能検証**:
   - 大量のシンボルを生成・変換するマイクロベンチマーク、および大規模 Scheme 入力のコンパイル時間を計測し、スタックが解消することを確認。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `symbol->string` において `*symbol-registry*` の $O(N)$ 線形リスト走査が完全に排除されていること。
- [ ] Direct-Mapped キャッシュにより、同一シンボルの再参照が $O(1)$ で完了すること。
- [ ] 大量シンボルを含むコード（`test_split_link` 等）のコンパイルがハングせず、高速に正常終了すること。
- [ ] 既存の全単体テスト（`make -C ulisp test_stdlib`, `test_string_to_number` 等）が 100% PASS すること。
- [ ] `make py_compile` および `make static_analysis` がエラー 0 件で通過すること。

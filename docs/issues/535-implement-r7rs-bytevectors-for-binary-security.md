---
ID: 535
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 低レベルバイナリ・暗号ハッシュ・生パケット解析向け R7RS バイトベクタ (bytevector) 型の実装 (ID: 535)

## 1. 概要 / Summary
セキュリティ研究および低レベルバイナリ解析において、ELF ヘッダ構造の直接パース、暗号ハッシュ値（SHA-256、MD5）の計算、ネットワークパケットのバッファリング等の処理には、Unicode 文字列ではなく連続した生の 8-bit バイト列（`uint8_t[]`）を扱う機構が不可欠である。
現在の ULisp は文字列型とペア型しか持たず、任意バイナリの走査時に不要なタグ変換オーバーヘッドや文字境界チェックが発生する。
本 Issue では、R7RS Section 6.9（Bytevectors）に準拠したバイトベクタ型 `bytevector` を新設し、`make-bytevector`, `bytevector-u8-ref`, `bytevector-u8-set!`, `bytevector-length`, `bytevector-copy` 等の必須操作プリミティブをベアメタルヒープ上に実装する。

---

## 2. トレーサビリティ / Traceability
- **関連規格**:
  - R7RS Section 6.9 (Bytevectors: `bytevector?`, `make-bytevector`, `bytevector-u8-ref`, `bytevector-u8-set!`)
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第3章 型システムとヒープ表現)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-36: 完全ベアメタル自己完結型 Freestanding 実行基盤](../designs/DSN-36-ulisp_baremetal_freestanding_pure_scheme_runtime.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/07_backend_x86_64.scm](../../ulisp/passes/07_backend_x86_64.scm) (バイトベクタ型ヒープ割当、ポインタタグ付け、インデックスアクセス `[base + 8 + i]`)
- [ ] [ulisp/passes/07_backend_aarch64.scm](../../ulisp/passes/07_backend_aarch64.scm) (AArch64 向け `ldrb` / `strb` による 8-bit バイトアクセスコード生成)
- [ ] [ulisp/lib/bytevector.scm](../../ulisp/lib/bytevector.scm) (新規作成: バイトベクタ高水準操作ユーティリティ)
- [ ] [ulisp/lib/gc.scm](../../ulisp/lib/gc.scm) (GC における生バイト配列のスキャン除外（ポインタ探索スキップ）最適化)
- [ ] [tests/test_bare_metal_ulisp.py](../../tests/test_bare_metal_ulisp.py) (ELF ヘッダマジック走査・バイナリ操作 E2E テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/535-ulisp-r7rs-bytevectors`

1. **バイトベクタのヒープタグ表現**:
   - オブジェクトヘッダ: `[BYTEVECTOR_TAG(3-bit), length(61-bit)]` (8バイト)。
   - ペイロード: `length` バイトの連続したメモリ領域（8バイト境界にアラインメントパディング）。
2. **高速アクセスプリミティブ**:
   - `bytevector-u8-ref bv i`: 境界検査 `0 <= i < length` を行った後、`movzx rax, byte ptr [rsi + 8 + rdi]` で取得し Fixnum タグを付加。
   - `bytevector-u8-set! bv i val`: `mov byte ptr [rsi + 8 + rdi], dl` で格納。
3. **GC 性能の最適化**:
   - バイトベクタ内部には Scheme ポインタが含まれないため、ガベージコレクタのポインタトレース処理でスキャンを即座にスキップ（メモリコピーのみ実行）し、GC 停止時間を短縮。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(let ((bv (make-bytevector 4 0))) (bytevector-u8-set! bv 0 127) (bytevector-u8-ref bv 0))` が `127` を返すこと。
- [ ] `bytevector-length` が正確なバイト長を返すこと。
- [ ] 範囲外アクセス時に安全に例外またはエラー終了すること。
- [ ] セルフホスティング固定点ブートストラップが完全一致でパスすること。

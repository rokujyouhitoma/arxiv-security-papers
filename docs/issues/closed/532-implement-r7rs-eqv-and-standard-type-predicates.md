---
ID: 532
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS 準拠の等価性比較述語 eqv? および標準型述語群の仕様整合化 (ID: 532)

## 1. 概要 / Summary
R7RS 標準仕様において、数値・文字・シンボル・ペア等の等価性判定には `eqv?` の使用が規定されており、数値や文字に対する `eq?` の挙動は未規定（Unspecified）とされている。
現在の ULisp では、整数・文字・ブール値・空リストが 64-bit 即値タグ（Immediate Value Tag）として実装されているため `eq?` で安全に比較できているが、標準 Scheme コードや外部 R7RS ライブラリをインポートする際に `eqv?` の未定義エラーが発生する課題がある。
本 Issue では、R7RS Section 6.1（Equivalence predicates）に準拠した `eqv?` 述語を正式に導入するとともに、`number?`, `integer?`, `real?`, `exact?`, `exact-integer?` 等の標準数値型述語群を整備し、既存のベアメタル性能を一切損なうことなく R7RS 互換性を高めた。

---

## 2. トレーサビリティ / Traceability
- **関連規格**:
  - R7RS Section 6.1 (Equivalence predicates: `eqv?`, `eq?`, `equal?`)
  - R7RS Section 6.2 (Numbers / Numerical type predicates)
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第3章 型システムとタグ付け)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連先行 Issue**:
  - Issue #526: Mytkowicz 測定バイアス排除機構と動的命令数差分テスト基盤の統合

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/equality.scm](../../ulisp/lib/equality.scm) (`eqv?`, `boolean=?`, `symbol=?` の標準ライブラリ実装)
- [x] [ulisp/lib/predicates.scm](../../ulisp/lib/predicates.scm) (`number?`, `integer?`, `exact?`, `exact-integer?`, `inexact?`, `real?`, `rational?`, `complex?`, `list?` の標準型述語群)
- [x] [ulisp/passes/00_helpers.scm](../../ulisp/passes/00_helpers.scm) (`pure-prim?`, `commutative-op?`, `fold-const-op` への新述語追加)
- [x] [ulisp/passes/03b_lvn.scm](../../ulisp/passes/03b_lvn.scm) (`eqv?` のローカル値番号付けと同一変数・値等価性の `#t` 簡約)
- [x] [ulisp/passes/04b_annotator.scm](../../ulisp/passes/04b_annotator.scm) (新述語群の Boolean 戻り値型推論)
- [x] [ulisp/passes/06_lir.scm](../../ulisp/passes/06_lir.scm) (`eqv?` のネイティブ `%cmp` + `%set-boolean` LIR 展開および数値述語のゼロオーバーヘッド展開)
- [x] [ulisp/tests/test_eqv.scm](../../ulisp/tests/test_eqv.scm) (`eqv?` & 標準述語 網羅的単体テストスイート)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/532-ulisp-r7rs-eqv-and-standard-predicates`

1. **`eqv?` 意味論の実装**:
   - `(define (eqv? a b) (eq? a b))` を基本とし、ULisp の即値表現（Fixnum, Char, Bool, Null, Eof）およびヒープ参照（Pair, String, Symbol, Vector）のすべてにおいて R7RS の `eqv?` 要求（同一メモリ位置または同値即値）を満たすよう保証。
2. **コンパイラインライン化と最適化**:
   - バックエンドおよび LVN パスにおいて、両引数が即値型または同一変数であることが推論できる場合は直接 CPU の `cmp rax, rbx` 命令へインライン展開。
3. **標準数値述語の整備**:
   - `(integer? x)` → `(fixnum? x)`
   - `(exact? x)` → `(integer? x)`
   - `(exact-integer? x)` → `(integer? x)`

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `(eqv? 42 42)`, `(eqv? #\a #\a)`, `(eqv? 'foo 'foo)` がすべて `#t` を返すこと。
- [x] `(eqv? 42 43)`, `(eqv? (cons 1 2) (cons 1 2))` が `#f` を返すこと。
- [x] `make -C ulisp diff_test` において `eqv?` を用いたワークロードが 100% 一致で合格すること。
- [x] セルフホスティング固定点ブートストラップが完全に一致すること。

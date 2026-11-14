---
ID: 826
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] 機械型 (i8..i64, f32, f64, ptr) を備えた Typed LIR への移行とボクシング操作の直交分離 (ID: 826)

## 1. 概要 / Summary
低レベル中間表現（LIR）の仮想レジスタおよびオペランドに明示的な機械型（Machine Types: `i8`, `i16`, `i32`, `i64`, `f32`, `f64`, `ptr`, `raw-bits`）注釈を導入し、Typed LIR として再構築する。
Scheme 特有の動的型ボクシング（`%box-fixnum`, `%unbox-fixnum`, `%alloc` 等）を、純粋な機械語メモリアクセス・ビットシフトと GC ランタイム呼出に明確に直交分離する。これにより、Scheme 側での浮動小数点アンボックス最適化（Unboxed Flonum）および C 言語のプリミティブ型・ポインタ型表現を同一の低レベルインフラで統一的に扱えるようにする。

---

## 2. トレーサビリティ / Traceability
- **DSN-38**: §2 (B5: 型付き C の IR, E1: 幅指定ロード/ストア, E4: f64 演算, E9: LIR 意味論)
- **DSN-33**: §2.1 (Tagged Pointer メモリモデル), §3 (低レイヤコード生成仕様)
- **関連 Issue**: #816 (Rtyper Escape Pruning), #828 (Overflow Arithmetic), #831 (C Backend Sync)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/lir.scm](../../ulisp/compiler/lir.scm): 機械型タグ付きオペランド定義および LIR verifier の拡張
- [ ] [ulisp/compiler/120_ast_to_lir.scm](../../ulisp/compiler/120_ast_to_lir.scm): AST から Typed LIR への lowering ロジック
- [ ] [ulisp/backend/140_backend_x86.scm](../../ulisp/backend/140_backend_x86.scm): 機械型に応じた幅指定レジスタ・命令選択
- [ ] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm): C 言語ネイティブ型（`int8_t`〜`int64_t`, `double`）への対応

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/826-typed-machine-lir-orthogonal-boxing`

1. LIR 型システムの定義：
   - レジスタ宣言・中間値に `(:type <machine-type>)` 属性を付与。
   - ロード・ストア命令に幅属性（8/16/32/64bit）および符号属性（sign-extend / zero-extend）を明示化。
2. ボクシング操作の直交化：
   - `%box-fixnum` などの高レベル擬似命令を、`(%shl val 1)`, `(%or val 1)` 等の純粋機械語命令列またはインラインマクロ命令として定義。
   - Scheme の型推論（090_rtyper）で型が確定した数値演算について、アンボックス化されたネイティブ算術命令を直接出力。
3. LIR 検証器（verifier）の更新：
   - 型の不整合（例: `f64` レジスタへの整数演算適用）を静的に検出するアサーションを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Typed LIR 上で `i8`〜`i64` および `f64` のアンボックス演算が正しくモデル化され、verifier を通過すること。
- [ ] Scheme の連続した浮動小数点演算ループにおいて、ヒープアロケーション（ボクシング）を介さない直接 XMM 演算コードが生成されること。
- [ ] 既存の全 Scheme テストスイートが回帰なくパスすること。

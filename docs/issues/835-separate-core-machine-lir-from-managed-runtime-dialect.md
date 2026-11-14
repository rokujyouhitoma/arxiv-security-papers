---
ID: 835
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] Core Machine LIR と Managed Runtime Dialect の完全直交分離 (ID: 835)

## 1. 概要 / Summary
低レベル中間表現（LIR）を「純粋な機械語抽象（Core Machine LIR）」と「GC/ヒープアロケーション/セーフポイント/タグ操作を扱う高水準マクロ命令（Managed Runtime Dialect）」の 2 層に明確に分離する。
Managed Runtime Dialect（`%alloc`, `%safepoint-poll`, `%write-barrier`, `%tag`, `%untag` 等）は、専用の Lowering パス（Pass 131 等）で純粋な生ポインタ操作・条件ジャンプ・ランタイム呼出しからなる Core Machine LIR へ展開する。
これにより、C 言語フロントエンドは Managed Dialect を一切介さず直接 Core Machine LIR へ降りられるようになり、C コードへの GC 命令混入チェックなどの場当たり的な禁止ルールを原理的に不要化する。また Scheme 側でもアリーナ割り当てや一意参照更新（FBIP）等の異なるメモリモデルの導入を局所化できる。

---

## 2. トレーサビリティ / Traceability
- **DSN-38**: §2 (B5: 型付き C の IR, E8: no-safepoint 扱い, E9: LIR 意味論不変条件)
- **DSN-33**: §2.1 (メモリモデル), §3 (低レイヤコード生成仕様)
- **関連 Issue**: #810 (Safepoint Exclusion), #826 (Typed LIR)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/lir.scm](../../ulisp/compiler/lir.scm): Core Machine LIR と Managed Dialect の構文定義・verifier の分離
- [ ] [ulisp/compiler/131_lower_managed_dialect.scm](../../ulisp/compiler/131_lower_managed_dialect.scm): Managed マクロ命令から Core LIR への Lowering パス
- [ ] [ulisp/compiler/120_ast_to_lir.scm](../../ulisp/compiler/120_ast_to_lir.scm): Scheme AST からの Managed Dialect 出力
- [ ] [ulisp/tests/test_lir_dialect_separation.scm](../../ulisp/tests/test_lir_dialect_separation.scm): 方言分離と Lowering 検証テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/835-separate-core-lir-from-managed-dialect`

1. 方言（Dialect）の厳格な階層化：
   - `Core Machine LIR`: レジスタ間演算、幅指定メモリ操作、関数呼出、条件分岐のみを許容。
   - `Managed Dialect`: `%managed-alloc`, `%managed-safepoint`, `%managed-box`, `%managed-unbox` を拡張構文として定義。
2. Pass 131（Lowering パス）の導入：
   - `%managed-alloc` を「バンプポインタ加算 + ヒープ上限比較 + 枯渇時ランタイム関数呼出」の Core LIR 基本ブロック列へ展開。
   - `%managed-safepoint` を「ポーリングページ参照またはアトミックフラグ検査」の Core LIR 命令へ展開。
3. C 言語 Lowering の接続点保証：
   - C フロントエンドは Pass 131 をバイパスして直接 Core Machine LIR を出力するパイプライン構成を確立。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Core Machine LIR の verifier において、Managed 系の命令が 1 つも含まれていないことが静的に検証できること。
- [ ] Scheme プログラムが Managed Dialect の Lowering を経由して完全に Core Machine LIR へ変換され、既存のテストが回帰なくパスすること。
- [ ] 単体テスト `test_lir_dialect_separation.scm` がパスすること。

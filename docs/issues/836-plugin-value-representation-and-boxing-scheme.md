---
ID: 836
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] `define-value-repr` による値表現・ボクシング方式のプラグイン化 (ID: 836)

## 1. 概要 / Summary
現在コンパイラ各パス（080/090/130/140）にハードコードされている Scheme の値表現仕様（Fixnum の 1 ビット左シフト + タグ 1、即値リテラルのビットマスク、ヒープオブジェクトヘッダの配置）を、単一の宣言的スペックマクロ（`define-value-repr`）へと集約・プラグイン化する。
これにより、C 言語の「タグ幅 0 の生値表現」を表現スペックの自然な一態様として統一的に扱えるようにする。さらに将来的に、Scheme インタプリタと AOT コンパイラ間での値表現共有によるゼロコスト FFI 連携や、NaN-boxing 等の異なる表現モデルへの柔軟な適応を可能にする。

---

## 2. トレーサビリティ / Traceability
- **DSN-38**: §2 (B5: 型付き C の IR, E1: 幅指定操作), メタコンパイラ値モデル設計
- **DSN-33**: §2.1 (Tagged Pointer メモリモデル)
- **関連 Issue**: #826 (Typed LIR), #835 (Managed Dialect Separation)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/value_repr.scm](../../ulisp/compiler/value_repr.scm): `define-value-repr` DSL およびタグ操作コード生成エンジン
- [ ] [ulisp/compiler/090_rtyper.scm](../../ulisp/compiler/090_rtyper.scm): 型推論器からの値表現参照
- [ ] [ulisp/compiler/120_ast_to_lir.scm](../../ulisp/compiler/120_ast_to_lir.scm): ボクシング/アンボクシング Lowering の動的導出
- [ ] [ulisp/tests/test_value_representation.scm](../../ulisp/tests/test_value_representation.scm): 値表現スペック切り替えテスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/836-plugin-value-representation`

1. `define-value-repr` DSL の策定：
   - 即値タグビット数、シフト量、ポインタアライメント、型ヘッダワード長を宣言的に記述。
   - `box-code-generator` および `unbox-code-generator` を表現スペックから自動合成。
2. 標準表現スペックの定義：
   - `repr:scheme-64bit-tagged`: 現行の Fixnum/ポインタ分離タグ方式。
   - `repr:c-unboxed`: タグなし、機械語ネイティブ値（幅指定バイナリそのまま）。
   - `repr:nan-boxing-64bit`: 将来の Lua / JS 向け NaN ボクシング方式のプロトタイプ定義。
3. Lowering パスとの結合：
   - ターゲット言語（C または Scheme）に応じて、使用する `value-repr` を切り替えられるように設計。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 値表現の定義が `ulisp/compiler/value_repr.scm` の 1 箇所に集約され、ハードコードされたマジックナンバー（ビットマスクやシフト値）が排除されること。
- [ ] `repr:scheme-64bit-tagged` と `repr:c-unboxed` が同一のコードジェネレータ抽象を通じて矛盾なくコード出力されること。
- [ ] 単体テスト `test_value_representation.scm` がパスすること。

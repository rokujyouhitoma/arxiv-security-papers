---
ID: 657
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS §4.3.1 局所マクロ束縛構文 (let-syntax / letrec-syntax) の実装 (ID: 657)

## 1. 概要 / Summary
R7RS-small §4.3.1 (Binding constructs for syntactic keywords) に準拠し、レキシカルスコープ内で局所的なマクロ変換規則を定義する構文 `let-syntax` および `letrec-syntax` を完全実装する。
現在 ULisp はトップレベルの `define-syntax` による大域的マクロ定義（Pass 020: `020_macro_expander.scm`）をサポートしているが、局所マクロ束縛構文が未実装（×）である。
本実装により、モジュール内や関数内での一時的なマクロ定義、局所ヘルパーマクロの封じ込め、外部マクロの安全なレキシカルシャドーイング、および相互再帰的な局所マクロ（`letrec-syntax`）を可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-small §4.3.1: Binding constructs for syntactic keywords (`let-syntax`, `letrec-syntax`)
  - R7RS-small §4.3.2: Pattern language (`syntax-rules`)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.1 式とコア構文
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - クローズド関連 Issue: [Issue #533 (syntax-rules マクロ展開器)](closed/533-implement-hygienic-syntax-rules-macro-expander.md), [Issue #647 (syntax-error 構文)](closed/647-implement-r7rs-syntax-error-syntax.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/frontend/020_macro_expander.scm](../ulisp/frontend/020_macro_expander.scm) (局所マクロ構文解析・レキシカルスコープマクロ環境展開・core-form-or-primitive? 登録)
- [x] [ulisp/frontend/030_desugar.scm](../ulisp/frontend/030_desugar.scm) (未展開構文防止・エラー検証)
- [x] [ulisp/lib/scheme/base.sld](../ulisp/lib/scheme/base.sld) (`let-syntax`, `letrec-syntax` のエクスポート宣言)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../ulisp/docs/ref_r7rs_compliance.md) (R7RS 準拠状況テーブル更新: × から ◎)
- [x] [ulisp/Makefile](../ulisp/Makefile) (`test_let_syntax` テストターゲットの追加)
- [x] [ulisp/tests/test_let_syntax.scm](../ulisp/tests/test_let_syntax.scm) (新規包括的単体テストスイート)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/657-implement-r7rs-let-syntax-and-letrec-syntax`

1. **予約語・プリミティブ保護の追加**:
   - `ulisp/frontend/020_macro_expander.scm` の `core-form-or-primitive?` に `let-syntax` および `letrec-syntax` を追加し、衛生的マクロ展開時の誤った変数リネーム（gensym 化）を防止。

2. **局所マクロ仕様パース関数の新設**:
   - `parse-macro-binding`: `(<keyword> <transformer-spec>)` 形式を検証し、`<transformer-spec>` が `(syntax-rules ...)` の場合に `(syntax-rules-macro <keyword> <literals> <rules>)` 構造体を生成。

3. **`let-syntax` 展開処理の実装**:
   - 構文: `(let-syntax ((<var> <trans>) ...) body1 body2 ...)`
   - `<trans>` 群を外側の `macro-table` を参照して解析。
   - 新たなマクロエントリ群を生成し、`new-macro-table = (append local-entries macro-table)` を構築。
   - 本体式（`body`）を `new-macro-table` のもとで `macro-expand-all` 展開。
   - 複数本体式は `(begin ...)` にラップして単一式へ正規化。

4. **`letrec-syntax` 相互再帰展開処理の実装**:
   - 構文: `(letrec-syntax ((<var> <trans>) ...) body1 body2 ...)`
   - 各 `<trans>` 内のテンプレートや展開結果で同スコープ内の `<var>` を呼び出せるよう、`new-macro-table` を先行生成して適用。
   - 自己再帰および相互再帰マクロが展開ループで正しく解決されることを保証。

5. **ライブラリ公開 & 仕様リファレンス更新**:
   - `ulisp/lib/scheme/base.sld` に `let-syntax`, `letrec-syntax` をエクスポート。
   - `ulisp/docs/ref_r7rs_compliance.md` の §4.3.1 を **◎ 完全サポート** に更新。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `let-syntax` による局所マクロ定義・展開が正常に動作する
- [x] `let-syntax` で定義されたマクロがスコープ外で未定義として扱われ、漏洩しない
- [x] 外側の同名マクロが `let-syntax` / `letrec-syntax` 内で正しくシャドーイングされる
- [x] `letrec-syntax` による自己再帰マクロ展開が正常に動作する
- [x] `letrec-syntax` による複数マクロの相互再帰展開が正常に動作する
- [x] 本体の複数式が `begin` スプライシングとして正しく評価される
- [x] `make -C ulisp test_let_syntax` が作成され、全テスト項目 PASS
- [x] 既存の `make -C ulisp test_syntax_rules` が PASS
- [x] `docs/issues/README.md` および `ref_r7rs_compliance.md` が更新されている

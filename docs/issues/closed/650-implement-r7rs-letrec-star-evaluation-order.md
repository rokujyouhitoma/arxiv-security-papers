---
ID: 650
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS §4.2.2 厳密な左から右への評価順序を保証する letrec* 構文の実装 (ID: 650)

## 1. 概要 / Summary
R7RS-small §4.2.2 で規定されている `(letrec* (<binding> ...) <body>)` 構文を ULisp に完全準拠で実装した。
Nanopass 中間言語（`L_src` / `L_core`）、Pass 020（マクロ展開器）、Pass 028 / 030（脱糖フェーズ）、Pass 090（RTyper）、Pass 110（クロージャ変換）を拡張・改修し、評価セマンティクス（左から右への厳密な順次評価、先行束縛への直接アクセス、後続参照のクロージャキャプチャ、相互再帰手続き群の直接コール）を完全保証した。

---

## 2. 背景と技術的課題 / Background & Technical Challenges
1. **LIR の局所変数の `set!` 非サポートの克服**:
   - ULisp の LIR（中間表現）は SSA 形式で純粋関数型モデルをとっており、局所変数の破壊的代入 `set!` が利用できない。
   - `letrec*` を全変数が同一スコープに登録される `letrec` 形式に正規化し、LIR レベルで順次スタック・環境に積むことで、`set!` を一切使わずに左から右への厳密な順次評価を実現した。
2. **相互再帰と先行参照・型推論の整合**:
   - `110_closure_convert.scm` において、非関数束縛に出現した手続きがオペレータ位置（呼び出し位置）にあってもエスケープ扱いされていた問題を `var-escapes?` の適用により解決。
   - `090_rtyper.scm` において、`letrec` 内の非関数バインディングの型推論時に外部コンテキスト用 `ext-unboxed-fns` を渡すよう修正し、未ボックス化整数関数の戻り値が適切にボックス化されるよう保証した。

---

## 3. トレーサビリティ / Traceability
- **R7RS-small 仕様**: Section 4.2.2 (Binding constructs - `letrec*`)
- **リファレンス**: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.1 (コア構文・評価順序保証)
- **関連 Issue**:
  - Issue #581 (Nanopass DSL Phase 1 & AST Canonicalization)
  - Issue #592 (R7RS 内部定義・相互再帰サポート)
  - Issue #647 (R7RS syntax-error 構文の実装)
  - Issue #649 (R7RS ハッシュテーブル API の実装)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm): `L_src` 構文定義に `letrec*` を追加、`L_core` で脱糖対象 `(- (letrec* ...))` として除外定義。
- [ulisp/frontend/020_macro_expander.scm](../../ulisp/frontend/020_macro_expander.scm): `core-form-or-primitive?` およびテンプレート変数抽出に `letrec*` を追加。
- [ulisp/frontend/028_desugar_bindings.scm](../../ulisp/frontend/028_desugar_bindings.scm): `desugar-letrec*` ヘルパー関数の追加、および `desugar-bindings` パスへの `letrec*` パターンマッチの統合。
- [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm): `desugar-all` パスへの `letrec*` パターンマッチの統合。
- [ulisp/compiler/scope.scm](../../ulisp/compiler/scope.scm): `*scope-runtime-special-forms*` に `letrec*` を追加。
- [ulisp/frontend/090_rtyper.scm](../../ulisp/frontend/090_rtyper.scm): 非関数束縛の外部コンテキストボックス化保証。
- [ulisp/frontend/110_closure_convert.scm](../../ulisp/frontend/110_closure_convert.scm): 束縛呼び出し関数の `%known-fn` 最適化および環境マップシャドウ防止。
- [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md): §4.2.2 `letrec*` の適合度を `◎` へ更新。
- [ulisp/tests/test_letrec_star.scm](../../ulisp/tests/test_letrec_star.scm): 順次評価順序、相互再帰、先行束縛直接参照、クロージャキャプチャ等の網羅的テストスイート新設。
- [ulisp/Makefile](../../ulisp/Makefile): `test_letrec_star` テストターゲットの追加および統合。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `compiler/nanopass.scm`, `frontend/020_macro_expander.scm`, `frontend/028_desugar_bindings.scm`, `frontend/030_desugar.scm`, `compiler/scope.scm` に `letrec*` が正しく統合されていること。
- [x] `tests/test_letrec_star.scm` が新設され、すべてのテストケース（先行参照、順次評価、相互再帰）が 100% PASS すること。
- [x] 既存のすべてのテストスイート（`make test`）に退行がないこと（No regressions）。
- [x] `ref_r7rs_compliance.md` の §4.2.2 `letrec*` が `◎` に更新されていること。
- [x] すべてのファイルリンクが相対パスで記述されていること。

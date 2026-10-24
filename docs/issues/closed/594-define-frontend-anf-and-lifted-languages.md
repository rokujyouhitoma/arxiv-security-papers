---
ID: 594
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] Frontend層: define-language L_anf / L_lifted の導入と不変条件自動検証 (ID: 594)

## 1. 概要 / Summary
現在、Frontend の前半（構文脱糖〜CP0）では `L_src` および `L_core` が Nanopass DSL として定義されているが、後半の Pass 070（ANF 正規化）、Pass 100（Contification）、Pass 110（Closure Conversion）においては中間言語が明示的に定義されておらず、手続き的な再帰走査と部分的な S 式書き換えが行われている。

本 Issue では、Frontend 後半の主要なチェックポイントとなる `define-language L_anf`（3番地コード形式・引数アトミック化）および `define-language L_lifted`（トップレベル `%function` 巻き上げおよび明示的 `%make-closure` 形式）を形式言語として定義する（`ulisp/frontend/frontend_lang.scm`）。
これにより、各パス通過時に「複合引数が残っていないか」「未リフトの無名ラムダが存在しないか」等の AST 不変条件（Invariants）を自動検証（`nanopass-ast-valid?`）可能にし、LIR 層への入力境界契約を宣言的かつ堅牢に確立する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/spec_pipeline.md)
  - [ULisp Nanopass 詳細仕様書](../../ulisp/docs/spec_nanopass.md)
- **関連 Issue**:
  - Issue 587: Pass 015 Nanopass DSL 手続き型展開器
  - Issue 593: LIR層 `L_lir_canonical` の導入（LIR 入力境界の対抗先）
  - 依存 Issue: Issue 593 (完了)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/frontend/frontend_lang.scm](../../ulisp/frontend/frontend_lang.scm) (新規: `L_anf`, `L_lifted` 言語仕様定義)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`FRONTEND_PASSES` への `frontend/frontend_lang.scm` 追加)
- [x] [ulisp/compiler/verifier.scm](../../ulisp/compiler/verifier.scm) (`verify-anf-ast`, `verify-closure-ast` への Nanopass スキーマ検証フック結合)
- [x] [ulisp/frontend/070_anf.scm](../../ulisp/frontend/070_anf.scm) (`L_anf` 適合性検証フック)
- [x] [ulisp/frontend/110_closure_convert.scm](../../ulisp/frontend/110_closure_convert.scm) (`L_lifted` 適合性検証フック)
- [x] [ulisp/tests/passes/test_070_anf.scm](../../ulisp/tests/passes/test_070_anf.scm) (`L_anf?` 述語・スキーマ適合性検証単体テスト)
- [x] [ulisp/tests/passes/test_110_closure_convert.scm](../../ulisp/tests/passes/test_110_closure_convert.scm) (`L_lifted?` 述語・局所ラムダ完全排除検証単体テスト)
- [x] [ulisp/docs/spec_nanopass.md](../../ulisp/docs/spec_nanopass.md) (Frontend 言語仕様のドキュメント反映)

---

## 3.2 脅威分析とセキュリティ要件 / Threat Modeling & Security Requirements

高水準 Scheme の動的表現から低レベル LIR への変換過程において、不完全な正規化や未脱糖・未リフトの式木が通過した場合の脅威を以下の通り特定し、対策を講じる。

| 脅威分類 (STRIDE / CWE) | 脅威シナリオ | 影響度 | 対策要件 (Mitigation) |
| :--- | :--- | :---: | :--- |
| **不正入力検証不備 (CWE-20)** | 非アトミックな複合式が演算子引数に残存した状態で LIR 変換器に渡り、不正なスタックスロット参照やオペコード不整合によるコンパイラクラッシュが発生する。 | High | `define-language L_anf` において `(op a ...)` の引数を `Atom` に制限し、非アトミック引数を即座に拒絶（Fail-Fast）。 |
| **型混乱・不正間接参照 (CWE-843 / CWE-119)** | クロージャ変換を逃れた無名 `(lambda ...)` が LIR 層に漏洩し、関数ポインタやフレーム構造として誤認され不正アドレスジャンプまたは SEGV を誘発する。 | Critical | `define-language L_lifted` において局所 `(lambda ...)` を文法から明示的に除外（`- (lambda (x ...) e)`）し、未リフト手続きの残存を機械的に 100% 遮断する。 |
| **スコープ境界破壊・未定義識別子参照 (CWE-668)** | 自由変数が適切にクロージャ環境にパックされず、実行時スタックや未初期化メモリを不正参照する。 | High | `L_lifted` において変数アクセスを `%closure-ref` / `%global-ref` として明示化し、静的構造を不変条件チェッカーで検証する。 |

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/594-define-frontend-anf-and-lifted-languages`

### 4.1 `L_anf` の文法定義策定 (`ulisp/frontend/frontend_lang.scm`)
`L_core` を継承し、すべての関数呼出・演算子引数および条件分岐テスト式がアトミック（シンボル、即値定数、クォート）であることを形式化する。

1. **Terminals**:
   - `(symbol (x lbl var))`
   - `(constant (c))`
   - `(integer (idx n))`
2. **Nonterminals**:
   - `Atom (a)`:
     - `x`
     - `c`
     - `(quote datum)`
   - `Expr (e)`:
     - `a`
     - `(if a e1 e2)`
     - `(if a e1)`
     - `(begin e ...)`
     - `(let ((x e) ...) e_body)`
     - `(letrec ((x e) ...) e_body)`
     - `(lambda (x ...) e_body)`
     - `(set! x e)`
     - `(%make-closure a_lbl a_env ...)`
     - `(%make-closure-env a_lbl a_env ...)`
     - `(%closure-ref a_self idx)`
     - `(%closure-set! a_self idx a_val)`
     - `(%cont-fun x (x_param ...) e_body e_in)`
     - `(%cont-call x a ...)`
     - `(%with-handler a1 a2)`
     - `(%raw-call/cc a)`
     - `(%call-with-values a1 a2)`
     - `(%values a ...)`
     - `(a0 a ...)`
     - `(%direct-call a_lbl a ...)`
     - `(%global-ref x)`
     - `(%global-set! x e)`
   - `Def (d)`:
     - `(define x e)`
     - `e`
   - `Program (p)`:
     - `(%program (d ...) e)`
     - `e`

### 4.2 `L_lifted` の文法定義策定 (`ulisp/frontend/frontend_lang.scm`)
`L_anf` を継承し、局所ラムダを完全除外。トップレベル `%program` 構造に `%function` のリストを強制する。

1. **Nonterminals**:
   - `Expr (e)`:
     - `(- (lambda (x ...) e_body))`
   - `FunctionDecl (fn)`:
     - `(%function a_lbl (x ...) e_body)`
   - `Program (p)`:
     - `(- (%program (d ...) e))`
     - `(+ (%program (fn ...) e))`

### 4.3 `ulisp/Makefile` の更新
- `FRONTEND_PASSES` の最上位（`frontend/010_library.scm` の直前）に `frontend/frontend_lang.scm` を配置する。
- `build/compiler_passes.scm` および `compiler.scm` のビルド時に自動統合され、全テスト・全パスで `L_anf` / `L_lifted` が即座に使用可能となる。

### 4.4 Verifier および各パス境界との統合
- `compiler/verifier.scm`:
  - `verify-anf-ast`: `(nanopass-ast-valid? 'L_anf ast)` によるスキーマ検証を第一防壁として連動。
  - `verify-closure-ast`: `(nanopass-ast-valid? 'L_lifted ast)` によるスキーマ検証を第一防壁として連動。
- `070_anf.scm` および `110_closure_convert.scm`:
  - 出力結果に対する検証フックを統合。

### 4.5 テストスイート拡充方針
- `ulisp/tests/passes/test_070_anf.scm`:
  - `(L_anf? res)` が `#t` を返すことの検証。
  - 非アトミック引数を含む不正 AST が `L_anf?` で `#f` と判定されることの検証。
- `ulisp/tests/passes/test_110_closure_convert.scm`:
  - `(L_lifted? res)` が `#t` を返すことの検証。
  - 式木内に無名 `(lambda ...)` が残存している不正 AST が `L_lifted?` で `#f` と判定されることの検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/frontend/frontend_lang.scm` が作成され、`define-language L_anf` および `define-language L_lifted` が定義されていること。
- [x] `ulisp/Makefile` の `FRONTEND_PASSES` に `frontend/frontend_lang.scm` が登録され、`compiler.scm` が正常にビルドできること。
- [x] `anf-all` の出力が `L_anf?` 述語テストを 100% パスすること。
- [x] `closure-convert` の出力が `L_lifted?` 述語テストを 100% パスし、局所 `lambda` が 0 件であることが保証されること。
- [x] `compiler/verifier.scm` の `verify-anf-ast` および `verify-closure-ast` が `L_anf?` / `L_lifted?` と協調動作すること。
- [x] `make -C ulisp test_all_passes` および `make -C ulisp test_nanopass` が 100% PASS すること。
- [x] 相対パス規則・プロジェクト品質ゲートに適合していること。

---

## 6. 検証手順 / Verification Procedures
1. **言語定義とコンパイラビルド**:
   ```bash
   make -C ulisp compiler
   make -C ulisp build/compiler_passes.scm
   ```
2. **Nanopass フレームワークテスト実行**:
   ```bash
   make -C ulisp test_nanopass
   ```
3. **1:1 パス単体テスト実行**:
   ```bash
   make -C ulisp test_all_passes
   ```
4. **全体リグレッションテスト実行**:
   ```bash
   bash ulisp/test_lir.sh
   make -C ulisp test
   ```
5. **品質ゲート全検証**:
   ```bash
   make static_analysis
   ```

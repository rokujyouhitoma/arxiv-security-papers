---
ID: 609
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS case-lambda 構文および (scheme case-lambda) ライブラリの実装 (ID: 609)

## 1. 概要 / Summary
R7RS-small §4.2.9 および `(scheme case-lambda)` で規定されている `case-lambda` 構文を実装し、可変個・複数アリティの手続き定義および引数個数ディスパッチを可能にする。
AOT メタコンパイラにおける構文脱糖パス ([Pass 028](../../../ulisp/frontend/028_desugar_bindings.scm)) およびマクロ展開器 ([Pass 020](../../../ulisp/frontend/020_macro_expander.scm)) において、`case-lambda` 節群を動的アリティ判定式 (`%num-args`) と `cond` 分岐へ脱糖し、[Pass 040](../../../ulisp/frontend/040_analysis.scm) の静的アリティ検証と連携させることで、安全かつ高速な多重アリティ呼び出しディスパッチを実現する。

---

## 2. トレーサビリティ / Traceability
- R7RS-small:
  - §4.2.9: Case-lambda (`case-lambda`)
  - §5.6 / §5.1: `(scheme case-lambda)`
- 関連仕様書:
  - [R7RS 仕様準拠状況リファレンス](../../../ulisp/docs/ref_r7rs_compliance.md) §1.1, §1.4
  - [Issue #562: implement R7RS standard library definitions](562-implement-r7rs-standard-library-definitions-sld.md)
  - [Issue #629: static arity check in pass 040](629-implement-static-arity-checker-and-runtime-arity-guard.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] Target Branch: `feat/609-implement-r7rs-case-lambda-syntax`
- [x] [ulisp/frontend/020_macro_expander.scm](../../../ulisp/frontend/020_macro_expander.scm): `core-form-or-primitive?` に `case-lambda` を登録し、衛生的マクロ展開時の意図しないリネームを防止
- [x] [ulisp/frontend/028_desugar_bindings.scm](../../../ulisp/frontend/028_desugar_bindings.scm): `desugar-case-lambda` 脱糖ロジックの実装（各節のパターン解析、最大アリティに基づくパラメータリスト生成、未束縛パラメータの `#f` 安全初期化、`%num-args` に基づく `cond` 分岐生成、レスト引数リスト構築）
- [x] [ulisp/frontend/040_analysis.scm](../../../ulisp/frontend/040_analysis.scm): 動的アリティ (`%num-args`) を含む手続きに対して、固定アリティ検査のバイパスおよび動的アリティ許容の統合
- [x] [ulisp/lib/scheme/case-lambda.sld](../../../ulisp/lib/scheme/case-lambda.sld): `(scheme case-lambda)` ライブラリ定義およびエクスポート検証
- [x] [ulisp/tests/test_case_lambda.scm](../../../ulisp/tests/test_case_lambda.scm): `case-lambda` の包括的単体テストスイート（0引数、固定長多重アリティ、可変長レスト引数、マッチ失敗時のエラー送出、マクロとの組み合わせ）
- [x] [ulisp/Makefile](../../../ulisp/Makefile): `test_case_lambda` ターゲットの追加と総合テスト連動
- [x] [ulisp/docs/ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md): 準拠状況ステータス更新 (0% → 100%)

---

## 4. セキュリティ分析・脅威モデル / Security & Threat Model
- **スタック安全とGCスタックマップの整合性**:
  - `case-lambda` は呼び出し時の引数個数に応じて可変アリティを受け入れる。最大パラメータ数まで仮引数を確保した場合、呼び出し側から渡されなかった未使用スロットに旧スタックフレームのゴミポインタが残留すると、Exact GC のスタックマップ走査で誤解放や無効ポインタのマークが発生するリスクがある。
  - **対策**: プロシージャ先頭で `(let ((p0 (if (< 0 n) p0 #f)) ...))` のように未受領の引数スロットを即座にイミディエイト真偽値 `#f` で上書き初期化し、GC に対する完全な安全性を保証する。
- **アリティ不一致時のフェイルセーフ**:
  - いずれの節にもマッチしない引数個数で呼び出された場合、未定義動作やメモリ破損を起こさず、直ちに `(error "case-lambda: no matching clause for arity" n)` を送出して安全にフォールトする。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/609-implement-r7rs-case-lambda-syntax`

1. **Pass 020 (マクロ展開器)**:
   - `core-form-or-primitive?` に `case-lambda` を追加。
   - `case-lambda` 構文の各節内部のボディが正しくマクロ展開されるように `macro-expand-all` に `case-lambda` 節の走査を追加。

2. **Pass 028 (バインディング脱糖器)**:
   - `desugar-case-lambda` 関数を新設:
     - 各節 `(formals . bodies)` を解析。
     - 固定長引数 `(x1 ... xk)`、レスト引数 `(x1 ... xk . rest)`、単一シンボル引数 `rest` を分類。
     - 必要な最大固定長引数数 $M$ を算出（最小8スロット確保）。
     - 生成パラメータ `(p0 p1 ... p{M-1})` を割当。
     - `(%num-args)` による引数長取得。
     - 各節のディスパッチ条件:
       - 固定長: `(= n k)`
       - レスト引数: `(>= n k)`
       - 全レスト: `#t`
     - 節内部で仮引数名を `p0..pk-1` に束縛。
     - レスト引数変数は `(cond ((= n k) '()) ((= n (+ k 1)) (list pk)) ...)` によりリスト構築。
     - 未マッチ時は `(error "case-lambda: no matching clause for arity" n)` を生成。
   - `desugar-bindings` の Nanopass 式パターンに `((case-lambda . ,clauses) (Expr (desugar-case-lambda clauses)))` を追加。

3. **Pass 040 (静的解析・アリティ検証)**:
   - `ast-contains-num-args?` ヘルパーを定義。
   - `check-arity-expr` の `define` / `let` / `letrec` 登録時、ボディが `%num-args` を含む場合は固定アリティチェックをバイパス（動的アリティとして扱う）。

4. **単体テストスイート & Makefile**:
   - `tests/test_case_lambda.scm` を作成し、0引数〜多重引数、可変レスト引数、エラー送出を検証。
   - `Makefile` に `test_case_lambda` を組み込み。

5. **ドキュメント & 品質ゲート**:
   - `ref_r7rs_compliance.md` の `(scheme case-lambda)` を 100% 準拠に更新。
   - `make py_compile`, `make static_analysis`, `make -C ulisp test`, `verify-quality-gates` をパス。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `(case-lambda ...)` がマクロおよび脱糖パスで正常に処理され、複数の引数パターンで期待通りディスパッチされること。
- [x] `(import (scheme case-lambda))` により `case-lambda` が使用可能であること。
- [x] 不正な引数個数で呼び出された場合に適切にエラーが送出されること。
- [x] `tests/test_case_lambda.scm` が作成され、全テスト項目がパスすること。
- [x] `make -C ulisp test`（単体テスト、Nanopassテスト、LIRテスト、Cバックエンドテスト、3段階ブートストラップ不動点検証）がすべて 100% PASS すること。
- [x] `ref_r7rs_compliance.md` の `(scheme case-lambda)` ステータスが更新され、品質ゲートを通過すること。

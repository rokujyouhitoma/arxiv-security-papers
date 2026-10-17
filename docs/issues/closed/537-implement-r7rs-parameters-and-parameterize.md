---
ID: 537
種別: Feature
優先度: High
ステータス: Closed (Fixed)
担当: PM & IT Specialist (PLC / Compilers) & SWD
ターゲットブランチ: feat/537-ulisp-r7rs-parameters-and-parameterize
---

# [FEAT/ENH] コンパイラコンテキスト動的スコープ制御のための R7RS パラメータ (make-parameter / parameterize) の実装 (ID: 537)

## 1. 概要 / Summary
コンパイラやパイプラインの機能拡張に伴い、「現在のコンパイルターゲット」「GC モード」「最適化レベル」「現在の出力先ポート」等のコンテキスト情報を、深層の下請け関数へ引数として渡し回す（引数のバケツリレー）コードが増加し、保守性の低下を招いている。
本 Issue では、R7RS Section 4.2.6（Dynamic bindings: `make-parameter`, `parameterize`）に準拠した動的束縛パラメータ機構を実装する。
動的環境の安全な巻き戻しを保証し、例外送出時や通常脱出時にも確実に以前の値へ復元されるクリーンなコンテキスト切り替えを可能にする。

---

## 2. ガバナンス & 多角的多専門エージェント審議 (16-Agent Review)

1. **Project Manager (PM)**:
   - 引数バケツリレーの解消によりコンパイラおよびツールチェインの保守性を飛躍的に高める。
   - 3段階セルフホスティング固定点ブートストラップ（bit-for-bit identical）の完全保持を必須要件とする。
2. **Information Security Specialist**:
   - パラメータ巻き戻し漏れによる権限昇格やセキュリティ設定の汚染（Leakage across dynamic extents）を防止。
   - 例外送出時（`raise`）においても旧値への確実な復元（Fail-Safe Restitution）を保証。
3. **Systems Architect**:
   - `dynamic-wind` と例外ハンドラ（`guard` / `%with-handler`）を統合した二重防御（Dual-Guard Unwind Architecture）を採用。
   - クロージャ呼び出し時の動的引数個数検知プリミティブ `(%num-args)` の導入によるゼロオーバーヘッド分岐。
4. **Software Quality Assurance Specialist**:
   - 単一・複数パラメータの動的束縛、ネストされた `parameterize`、動的脱出（`call/cc`）、例外脱出（`raise`）の網羅的テストケースを設計。
5. **Database / Data Infrastructure Specialist**:
   - パラメータ内部セルのアロケーションと GC 追跡の無矛盾性を検証。
6. **Network Specialist**:
   - 将来のソケット・HTTP 接続コンテキストパラメータ化への布石を確認。
7. **IT Specialist (NLP & Info Retrieval)**:
   - ドキュメントおよびエラーメッセージの日本語品質の統一。
8. **IT Strategist**:
   - R7RS 完全準拠に向けた重要な動的スコープ仕様の達成とエコシステム互換性の向上。
9. **IT Service Manager**:
   - バッチコンパイル・実行時のログ追跡とデバッグ容易性の維持。
10. **Embedded Systems Specialist**:
    - ベアメタル環境（ゼロ外部依存・zero-libc）におけるスタックフレーム消費の最小化。
11. **Systems Auditor**:
    - DSN-33 設計仕様書および Git 履歴とのトレーサビリティの確保。
12. **UI/UX & Documentation Designer**:
    - パラメータ利用パターンの明確なコード例と Markdown 文書化。
13. **Education Specialist**:
    - Scheme 初学者にも直感的な `(p)`（取得）と `(p val)`（更新）のインターフェース設計。
14. **Software Development (SWD)**:
    - `06_lir.scm` での呼び出し時 `%rax` への引数個数設定と、関数プロローグでの `[rsp - 16]` への退避機構の実装。
15. **Application Specialist (APS)**:
    - Web / CLI ゲートウェイ層でのリクエストコンテキスト分離への適用検証。
16. **IT Specialist (Programming Languages & Compilers / PLC)**:
    - `01_desugar.scm` での `parameterize` 脱糖マクロ、`ulisp/lib/parameter.scm` での `make-parameter` の標準ライブラリ化。

---

## 3. トレーサビリティ / Traceability
- **関連規格**:
  - R7RS Section 4.2.6 (Dynamic bindings: `make-parameter`, `parameterize`)
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第2章 ナノパスコンパイラアーキテクチャ)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連先行 Issue**:
  - Issue #531: 軽量大域脱出ハンドラスタックに基づく R7RS 例外処理機構の実装
  - Issue #540: スタック退避・復元および動的巻き戻し (dynamic-wind) に基づく完全第一級 call/cc の実装

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/parameter.scm](../../ulisp/lib/parameter.scm) (新規作成: `make-parameter-1`, `make-parameter-2` 手続き)
- [x] [ulisp/passes/00_helpers.scm](../../ulisp/passes/00_helpers.scm) (`%num-args` プリミティブの登録)
- [x] [ulisp/passes/01_desugar.scm](../../ulisp/passes/01_desugar.scm) (`parameterize` および `make-parameter` の脱糖マクロ)
- [x] [ulisp/passes/04b_annotator.scm](../../ulisp/passes/04b_annotator.scm) (`%num-args` 型推論の登録)
- [x] [ulisp/passes/06_lir.scm](../../ulisp/passes/06_lir.scm) (`lir-compile-call` での引数個数 `%rax` 設定、関数エントリでの退避、`%num-args` LIR 生成)
- [x] [ulisp/passes/07_backend_c.scm](../../ulisp/passes/07_backend_c.scm) (`%push-handler` / `%raise` computed goto ラベルアドレス保存)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`lib/parameter.scm` の追加)
- [x] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (`lib/parameter.scm` の追加)
- [x] [ulisp/test.sh](../../ulisp/test.sh) (Step 31: R7RS Parameters テストスイート)
- [x] [ulisp/test_c.sh](../../ulisp/test_c.sh) (Step 11: R7RS Parameters テストスイート)

---

## 5. 実装方針 / Implementation Plan

1. **動的引数個数検知プリミティブ `(%num-args)`**:
   - `06_lir.scm` の `lir-compile-call` において、クロージャ呼び出し直前に `%rax` へ `num-args * 4`（Fixnum）を設定。
   - `lir-compile-function` のエントリにて、`%rax` の値を `[rsp - 16]` に退避し、`callee-si` を `-24` から開始。
   - `(%num-args)` を呼び出した際は `[rsp - 16]` からロード。

2. **パラメータ手続きの表現 (`ulisp/lib/parameter.scm`)**:
   - `(make-parameter init [converter])`:
     内部セル `(cons init '())` を保持するクロージャを生成。
     引数が 0 個の場合（`(= (%num-args) 0)`）は現在値を返却。
     引数が 1 個の場合（`(= (%num-args) 1)`）はコンバータ（指定時）を適用し、内部セルを更新して新値を返却。

3. **`parameterize` の脱糖と安全な復元 (`01_desugar.scm`)**:
   - `(parameterize ((param1 val1) (param2 val2) ...) body ...)` を展開：
     各パラメータと値を1度だけ評価し、可変 cons セル `(cons #f '())` を作成。
     `dynamic-wind` の `before` で現値を `set-car!` 退避し、新値を設定。
     `body` は内側の `guard` で `raise` を捕捉して旧値を復元した上で再送出（Dual-Guard Unwind Architecture）。
     `after` で旧値を復元。
   - これにより、通常脱出、`guard` 例外送出、`call/cc` 継続ジャンプのいずれにおいても旧値への確実な復元を実現。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `(define p (make-parameter 10))` において、`(p)` が `10` を返すこと。
- [x] `(p 42)` を実行した際、返り値が `42` であり、その後の `(p)` が `42` に更新されること。
- [x] `(make-parameter 5 (lambda (x) (* x 2)))` でコンバータが正しく初期値および更新値に適用されること。
- [x] `(parameterize ((p 20)) (p))` が `20` を返し、ブロック脱出後に `(p)` が以前の値に戻ること。
- [x] 複数のパラメータを同時に `parameterize` で束縛し、ブロック内外で整合性が保たれること。
- [x] ネストされた `parameterize` ブロックにおいて、階層的な巻き戻しが正しく機能すること。
- [x] `parameterize` ブロック内で例外が `raise` された場合も、捕捉側で旧値に復元されていること。
- [x] `call/cc` による動的脱出および再突入時にも `dynamic-wind` を通じて値が正しく切り替わること。
- [x] x86-64 ネイティブバックエンド (`test.sh`) および Portable C バックエンド (`test_c.sh`) の両方で 100% PASS すること。
- [x] セルフホスティング固定点ブートストラップ（Stage 2 と Stage 3 の bit-for-bit 完全一致）が PASS すること。

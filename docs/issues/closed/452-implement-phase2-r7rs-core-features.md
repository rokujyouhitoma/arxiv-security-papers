---
ID: 452
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] Phase 2: R7RS 仕様準拠のコア言語機能拡充 (準クォート、ベクタ型、例外機構、多値、脱出継続) (ID: 452)

## 1. 概要 / Summary
[DSN-31](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) および [SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md) のフェーズ 2 仕様に基づき、ILISP (Intelligence LISP) の R7RS-small コア言語機能を本格拡張する。
準クォート (`quasiquote` / `` ` ``, `,`, `,@`)、O(1) ランダムアクセスのベクタ型 (`#(1 2 3)` / `vector`)、R7RS 例外ハンドリング (`guard`, `raise`, `with-exception-handler`)、多値機構 (`values`, `call-with-values`, `let-values`)、および One-shot 脱出継続 (`call/cc`) を実装し、Tree-walk 評価器と Python AST トランスパイラ (Backend A) の双方で完全等価かつ透過的な動作を担保する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `ilisp/reader.py` (マクロ文字 `` ` ``, `,`, `,@` およびベクタリテラル `#( ... )` の読み込み)
- [x] `ilisp/types.py` (`Vector` クラス、`Values` クラス、例外・継続関連型定義)
- [x] `ilisp/env.py` (ベクタ・多値・例外・継続関連の R7RS プリミティブ登録)
- [x] `ilisp/evaluator.py` (`quasiquote` 評価器、`call/cc`、例外捕捉ランタイム)
- [x] `ilisp/stdlib/base.ilisp` (`guard`, `let-values`, `let*-values`, `case` マクロの実装)
- [x] `ilisp/backend/py_codegen/compiler.py` (ベクタ、準クォート等の Python AST コンパイル対応)
- [x] `tests/ilisp/test_phase2.py` (Phase 2 言語機能総合単体テスト)
- [x] `docs/issues/README.md` (Issue 452 登録)

---

## 3. 実装方針 / Implementation Plan
Target Branch: `feat/452-implement-phase2-r7rs-core-features`

1. **Reader 拡張 (Reader Macros & Vector Literals)**:
   - `` `expr `` を `(quasiquote expr)` へ展開。
   - `,expr` を `(unquote expr)` へ展開。
   - `,@expr` を `(unquote-splicing expr)` へ展開。
   - `#(item ...)` を `Vector` オブジェクトまたは `(vector item ...)` 形式へパース。
2. **ベクタ型と R7RS プリミティブ**:
   - `Vector` 型（内部は Python `list`、O(1) インデックスアクセス）: `vector?`, `make-vector`, `vector`, `vector-ref`, `vector-set!`, `vector-length`, `vector->list`, `list->vector`。
3. **準クォート評価器 (`quasiquote`)**:
   - ネストした準クォートに対応。
   - `unquote` 式はその場で評価し、`unquote-splicing` 式は評価結果のリストを親リストへシームレスに展開・結合。
4. **多値機構 (`values`, `call-with-values`, `let-values`)**:
   - `values(*args)` により多値コンテナ `Values` を返却。単一値文脈では先頭要素へ自然退行。
   - `call-with-values producer consumer` により producer の返した値を consumer の引数へアンパック。
   - `let-values`, `let*-values` 構文マクロを `base.ilisp` に追加。
5. **例外処理機構 (`raise`, `guard`, `with-exception-handler`)**:
   - `SchemeException` クラスを定義し、任意の Lisp 値を保持して送出可能にする。
   - `with-exception-handler` および `guard` マクロ（`cond` ライクなパターンマッチ）によるエラー捕捉と継続復帰。
6. **One-shot 脱出継続 (`call/cc`)**:
   - Python の例外機構を基盤とした `Continuation` オブジェクト。一度脱出した後の二重呼出を防ぐガード付き。
7. **包括テストと品質ゲート**:
   - `tests/ilisp/test_phase2.py` による 100% カバレッジ検証。
   - `flake8`, `isort`, `black`, `mypy --strict`, `pytest`。

---

## 4. 完了条件 / Success Criteria (DoD)
- [x] Reader が `` ` ``, `,`, `,@` および `#( ... )` を正確にトークナイズ・パースできること
- [x] `Vector` 型および関連プリミティブが動作し、O(1) アクセスが担保されること
- [x] 準クォートおよびリストスプライシング（`unquote-splicing`）が正しく評価されること
- [x] `values`, `call-with-values`, `let-values` による多値返却と束縛が動作すること
- [x] `raise`, `with-exception-handler`, `guard` による例外送出と捕捉が動作すること
- [x] `call/cc` による脱出継続が正確に機能すること
- [x] Python AST トランスパイラ (Backend A) でもこれらの機能が等価にコンパイル・実行できること
- [x] 新規単体テスト（`tests/ilisp/test_phase2.py`）を含む全テストが PASS すること
- [x] リポジトリの全品質ゲート（`flake8`, `isort`, `black`, `mypy --strict`, `pytest`）が 100% PASS すること

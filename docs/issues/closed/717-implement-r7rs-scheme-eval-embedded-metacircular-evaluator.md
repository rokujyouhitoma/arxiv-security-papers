---
ID: 717
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] R7RS-small (scheme eval) オンデマンド埋め込み型メタ循環評価器 (eval) の実装 (ID: 717)

## 1. 概要 / Summary
AOT バイナリのスタンドアロン独立性を維持したまま R7RS-small §6.12 `(scheme eval)` の動的評価手続き `(eval <expr-or-def> <environment-specifier>)` を完全サポートするため、ULisp ネイティブ手続き・第一級環境・クロージャ・継続 (`call/cc`, `dynamic-wind`)・多値 (`values`)・例外機構 (`guard`, `raise`) とシームレスに統合されたオンデマンド埋め込み型メタ循環評価器を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) (§1.3.12 環境と動的評価 6.12, §1.4 `(scheme eval)`)
  - R7RS-small §6.12 (`eval`)
  - 先行依存: [Issue #716 (Environment Specifiers)](closed/716-implement-r7rs-environment-specifiers-and-library-import-environments.md)
  - 後続依存: [Issue #718 (load, repl, scheme r5rs)](718-implement-r7rs-scheme-load-repl-and-r5rs-full-compliance.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [eval.scm](../../ulisp/lib/eval.scm) (メタ循環評価器 `%eval-core`, `eval` の実装)
- [x] [eval.sld](../../ulisp/lib/scheme/eval.sld) (`eval` エクスポート)
- [x] [string.scm](../../ulisp/lib/string.scm) (`*known-runtime-symbols*` のシンボル補完)
- [x] [Makefile](../../ulisp/Makefile) (`test_eval_load_repl` ターゲット統合)
- [x] [test_eval_load_repl.scm](../../ulisp/tests/test_eval_load_repl.scm) (eval 単体・複合テスト追加)
- [x] [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (§6.12, §1.4 (scheme eval) 100% 準拠記載)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/717-implement-r7rs-scheme-eval-embedded-metacircular-evaluator`

1. **メタ循環コア評価器 (`%eval-core expr lex-env dyn-env`) のアーキテクチャ設計**:
   - `lex-env`: 内部レキシカル環境リスト `((sym . val) ...)`。
   - `dyn-env`: Issue #716 で導入された第一級 `<environment>` オブジェクト。
   - レキシカルスコープの優先探索、存在しない場合は `dyn-env` のバインディングをルックアップ。
   - 自己評価値 (数、真偽値、文字、文字列、ベクタ、バイトベクタ) はそのまま返却。
   - クォート `(quote datum)` は `datum` を返却。
   - 変数参照: レキシカルスコープ -> 動的環境 -> 未束縛例外 `(error "eval: unbound variable" sym)`.
   - 変数代入 `(set! var val)`: レキシカルバインディング書き換え、または動的環境変数の書き換え (`%r7rs-env-set!`)。
   - 定義 `(define var val)`, `(define (f . args) body ...)`: 動的環境への変数束縛登録 (`%r7rs-env-define!`)。
   - 複数値定義 `(define-values (v ...) expr)`: 多値の束縛。
   - 条件分岐: `if`, `cond` (`=>` 構文対応), `case` (`=>` 構文対応), `and`, `or`, `when`, `unless`.
   - 順次実行: `begin` (トップレベル定義のシーケンス展開含む)。
   - 局所束縛: `let` (通常 `let` および名前付き `let` の末尾再帰最適化), `let*`, `letrec`, `letrec*`, `let-values`, `let*-values`.
   - 手続き抽象:
     - `lambda`: メタ循環クロージャ `#(ulisp-closure formals body lex-env)` の生成。固定引数、ドット対レスト引数 `(a . rest)`、単一レスト引数 `args` に完全対応。
     - `case-lambda`: 複数アリティ節のクロージャ生成とアリティ一致ディスパッチ。
   - 反復: `do` ループ構文の動的展開・評価。
   - 準クォート: `quasiquote`, `unquote`, `unquote-splicing` のネスト対応展開。
   - 手続き呼出しディスパッチ:
     - メタ循環クロージャ: パラメータ束縛を拡張したレキシカル環境で本体を順次評価。
     - ホストネイティブ手続き (ULisp 組み込み、第一級ラッパー `%eval-plus`, `cons`, `values`, `call/cc` 等): `(apply proc evaluated-args)` にフォールバックして直接ネイティブ実行。

2. **`(eval expr [env])` エクスポートと R7RS インターフェース**:
   - `case-lambda` による 1 引数 `(eval expr)` (デフォルトは `(interaction-environment)`) および 2 引数 `(eval expr env-spec)`。
   - `env-spec` の `environment?` チェックと不変環境での定義禁止検証。
   - `(scheme eval)` ライブラリからのエクスポート。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 基本式 (定数、クォート、変数参照、代入) が正しく評価されること。
- [x] 条件式 (`if`, `cond`, `case`, `and`, `or`, `when`, `unless`) が正しく動作すること。
- [x] 局所変数 (`let`, `let*`, `letrec`, `letrec*`, 名前付き `let`, `let-values`) が正しく動作すること。
- [x] 第一級クロージャ (`lambda`, `case-lambda`) が引数パターン (固定・可変長・ドット対) で正常に呼出されること。
- [x] 準クォート (`quasiquote`, `unquote`, `unquote-splicing`) がネストを含めて正しく評価されること。
- [x] 多値 (`values`, `call-with-values`) および継続 (`call/cc`) がメタ循環評価器内から正しく協調動作すること。
- [x] 不変環境に対する `define` / `set!` が適切に拒絶され、可変環境 (`interaction-environment`) への動的定義が保持されること。
- [x] 全 60 項目以上の eval 単体および複合テストが `make -C ulisp test_eval_load_repl` で 100% PASS すること。
- [x] `ref_r7rs_compliance.md` の §6.12 および `(scheme eval)` が ◎ (完全準拠) に更新されること。

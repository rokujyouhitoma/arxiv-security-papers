---
ID: 859
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] Yellow Docket 構文拡張マクロ (SRFI 8, 26, 31, 2, 61) の脱糖実装 (ID: 859)

## 1. 概要 / Summary
R7RS 仕様準拠状況リファレンス ([ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.3, §2.5) において「Pass 030 / Pass 020 で完全動作 (◎)」と記載されていた Yellow Docket および基盤構文マクロ群（SRFI 8 `receive`, SRFI 26 `cut`/`cute`, SRFI 31 `rec`, SRFI 2 `and-let*`, SRFI 61 一般化 `cond`）について、現行コンパイラには脱糖規則および対応するライブラリ定義が存在しない。
本 Issue では、これら 5 つの主要構文マクロを Pass 027 (条件分岐脱糖), Pass 028 (束縛脱糖), Pass 029 (動的環境・多値脱糖), Pass 030 (Pass Fusion 脱糖) に正式実装し、対応する SRFI `.sld` モジュールを提供することで、規格への実質的準拠と完全なトレーサビリティを達成する。

---

## 2. トレーサビリティ / Traceability
- **関連標準仕様**:
  - R7RS-large Yellow Docket: [YellowDocket.md](https://github.com/johnwcowan/r7rs-work/blob/master/YellowDocket.md)
  - SRFI 8: Binding to multiple values (`receive`)
  - SRFI 26: Notation for Specializing Parameters without Currying (`cut`, `cute`, `<>`, `<...>`)
  - SRFI 31: A special form rec for recursive evaluation (`rec`)
  - SRFI 2: AND-LET* - an extend AND-expression producing bindings (`and-let*`)
  - SRFI 61: A more general `cond` clause (`<generator> <guard> => <receiver>`)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.3 (Yellow Docket), §2.5 (基盤的 SRFI)
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/frontend/020_macro_expander.scm](../../ulisp/frontend/020_macro_expander.scm) (`core-form-or-primitive?` に `receive`, `rec`, `and-let*`, `cut`, `cute`, `<>`, `<...>` を追加)
- [x] [ulisp/frontend/027_desugar_conditionals.scm](../../ulisp/frontend/027_desugar_conditionals.scm) (SRFI 61 一般化 `cond` 節および SRFI 2 `and-let*` の脱糖実装・Picopass 定義)
- [x] [ulisp/frontend/028_desugar_bindings.scm](../../ulisp/frontend/028_desugar_bindings.scm) (SRFI 31 `rec` および SRFI 26 `cut` / `cute` の脱糖実装・Picopass 定義)
- [x] [ulisp/frontend/029_desugar_dynamic.scm](../../ulisp/frontend/029_desugar_dynamic.scm) (SRFI 8 `receive` の多値脱糖実装・Picopass 定義)
- [x] [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm) (`fuse-rules` に上記 Picopass ルール群を追加)
- [x] [ulisp/lib/srfi/8.sld](../../ulisp/lib/srfi/8.sld) (新規作成: `(srfi 8)` ライブラリ定義)
- [x] [ulisp/lib/srfi/26.sld](../../ulisp/lib/srfi/26.sld) (新規作成: `(srfi 26)` ライブラリ定義)
- [x] [ulisp/lib/srfi/31.sld](../../ulisp/lib/srfi/31.sld) (新規作成: `(srfi 31)` ライブラリ定義)
- [x] [ulisp/lib/srfi/2.sld](../../ulisp/lib/srfi/2.sld) (新規作成: `(srfi 2)` ライブラリ定義)
- [x] [ulisp/lib/srfi/61.sld](../../ulisp/lib/srfi/61.sld) (新規作成: `(srfi 61)` ライブラリ定義)
- [x] [ulisp/tests/test_yellow_docket_macros.scm](../../ulisp/tests/test_yellow_docket_macros.scm) (新規作成: 包括的単体テストスイート)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`test_yellow_docket_macros` ターゲット追加、`lint_sexpr`、`test:` への登録)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (Issue #859 実装完了の反映)
- [x] [docs/issues/README.md](README.md) (Issue 台帳更新)

---

## 4. 仕様定義と脱糖マッピング / Specification & Desugaring Rules

### 4.1 SRFI 8: `receive` (多値束縛構文)
- **構文形式**: `(receive <formals> <expression> <body> ...)`
- **形式引数 `<formals>`**:
  - 固定長リスト: `(a b c)`
  - 可変長ペア: `(a b . rest)`
  - 単一シンボル: `args`
- **脱糖ルール**:
  ```scheme
  (call-with-values
    (lambda () <expression>)
    (lambda <formals> <body> ...))
  ```
- **配置**: `ulisp/frontend/029_desugar_dynamic.scm` (`rule-desugar-receive`)

### 4.2 SRFI 31: `rec` (自己再帰束縛構文)
- **構文形式**:
  1. 関数短縮形式: `(rec (<variable> <formals> ...) <body> ...)`
  2. 値束縛形式: `(rec <variable> <expression>)`
- **脱糖ルール**:
  - 関数短縮形式:
    ```scheme
    (letrec ((<variable> (lambda (<formals> ...) <body> ...)))
      <variable>)
    ```
  - 値束縛形式:
    ```scheme
    (letrec ((<variable> <expression>))
      <variable>)
    ```
- **配置**: `ulisp/frontend/028_desugar_bindings.scm` (`rule-desugar-rec`)

### 4.3 SRFI 2: `and-let*` (条件付き束縛短絡構文)
- **構文形式**: `(and-let* (<claw> ...) <body> ...)`
- **Claw (節) の種類**:
  1. `(<variable> <expression>)`: `<expression>` を評価し、真値なら `<variable>` に束縛。`#f` なら直ちに短絡して `#f` を返す。
  2. `(<expression>)`: `<expression>` を評価し、真値なら次へ進む。`#f` なら直ちに短絡して `#f` を返す。
  3. `<variable>` (シンボル単体): `<variable>` を参照し、真値なら次へ進む。`#f` なら直ちに短絡して `#f` を返す。
- **脱糖ルール** (再帰的短絡展開):
  - `(and-let* () <body> ...)` $\implies$ `(begin <body> ...)` (bodies が空の場合は `#t`)
  - `(and-let* (((<var> <expr>) . <rest>) <body> ...)`:
    ```scheme
    (let ((<var> <expr>))
      (if <var>
          (and-let* (<rest> ...) <body> ...)
          #f))
    ```
  - `(and-let* ((<expr>) . <rest>) <body> ...)`:
    ```scheme
    (if <expr>
        (and-let* (<rest> ...) <body> ...)
        #f)
    ```
  - `(and-let* (<var> . <rest>) <body> ...)`:
    ```scheme
    (if <var>
        (and-let* (<rest> ...) <body> ...)
        #f)
    ```
- **配置**: `ulisp/frontend/027_desugar_conditionals.scm` (`rule-desugar-and-let*`)

### 4.4 SRFI 26: `cut` / `cute` (引数特殊化・部分適用構文)
- **構文形式**:
  - `(cut <proc-or-slot> <slot-or-expr> ...)`
  - `(cute <proc-or-slot> <slot-or-expr> ...)`
- **特殊記号**:
  - `<>`: 単一引数スロット
  - `<...>`: レスト引数スロット (引数リスト末尾にのみ許容)
- **脱糖アルゴリズム**:
  - **`cut`**:
    スロット `<>` の位置にそれぞれ一意な引数シンボル `x1, x2, ...` を割り当て、末尾に `<...>` があればレスト引数シンボル `xs` を割り当てる。
    - `<...>` なし:
      `(lambda (x1 x2 ...) (<proc> <args...>))`
    - `<...>` あり:
      `(lambda (x1 x2 ... . xs) (apply <proc> <args...> xs))`
  - **`cute`**:
    非スロット引数式（`<proc>` および `<slot-or-expr>` のうち `<>` や `<...>` でないもの）を左から右の評価順序で事前評価し、外側の `let` 束縛 `((t1 <expr1>) (t2 <expr2>) ...)` を生成。その上で `cut` と同様のラムダ式本体を構築する。
- **配置**: `ulisp/frontend/028_desugar_bindings.scm` (`rule-desugar-cut`, `rule-desugar-cute`)

### 4.5 SRFI 61: 一般化 `cond` 節 (`<generator> <guard> => <receiver>`)
- **構文形式**:
  `(<generator> <guard> => <receiver>)`
- **セマンティクス**:
  1. `<generator>` を評価（多値を返しうる）。
  2. 得られた多値を引数として `<guard>` 手続きを呼び出す。
  3. `<guard>` の戻り値が真であれば、**同じ多値を引数として** `<receiver>` 手続きを呼び出す。
  4. `<guard>` の戻り値が `#f` であれば、次の `cond` 節へフォールスルーする。
- **脱糖ルール**:
  ```scheme
  (call-with-values (lambda () <generator>)
    (lambda <vals-sym>
      (if (apply <guard> <vals-sym>)
          (apply <receiver> <vals-sym>)
          <desugar-rest-cond-clauses>)))
  ```
- **配置**: `ulisp/frontend/027_desugar_conditionals.scm` (`desugar-cond` の拡張)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/859-implement-yellow-docket-macros-srfi-8-26-31-2-and-61`

1. **Pass 020 予約識別子の保護**:
   - `ulisp/frontend/020_macro_expander.scm` の `core-form-or-primitive?` に `receive`, `rec`, `and-let*`, `cut`, `cute`, `<>`, `<...>` を追加。
2. **Pass 027 (条件分岐) の拡張**:
   - `desugar-cond` に SRFI 61 の 4 要素節 `(<gen> <guard> => <receiver>)` ハンドラを追加。
   - `desugar-and-let*` および `rule-desugar-and-let*` を追加。
3. **Pass 028 (局所束縛) の拡張**:
   - `desugar-rec` および `rule-desugar-rec` を追加。
   - `desugar-cut`, `desugar-cute`, `rule-desugar-cut`, `rule-desugar-cute` を追加。
4. **Pass 029 (動的環境・多値) の拡張**:
   - `desugar-receive` および `rule-desugar-receive` を追加。
5. **Pass 030 (Pass Fusion) の融合ルール登録**:
   - `ulisp/frontend/030_desugar.scm` の `fuse-rules` に以下を登録：
     - `rule-desugar-and-let*`
     - `rule-desugar-rec`
     - `rule-desugar-cut`
     - `rule-desugar-cute`
     - `rule-desugar-receive`
6. **SRFI モジュール群の提供**:
   - `ulisp/lib/srfi/8.sld` (export `receive`)
   - `ulisp/lib/srfi/26.sld` (export `cut`, `cute`, `<>`, `<...>`)
   - `ulisp/lib/srfi/31.sld` (export `rec`)
   - `ulisp/lib/srfi/2.sld` (export `and-let*`)
   - `ulisp/lib/srfi/61.sld` (export `cond`)
   - 全ファイルに Traceability ヘッダーを付与。
7. **包括的テストスイート `test_yellow_docket_macros.scm` の作成**:
   - Group 1: `receive` (多値束縛、1値、複数値、rest引数、入れ子)
   - Group 2: `rec` (無名再帰関数による階乗、相互再帰、無名ストリーム値束縛)
   - Group 3: `and-let*` (空束縛、単一真値、短絡偽値、連鎖束縛参照、副作用順序)
   - Group 4: `cut` / `cute` (定数引数、単一スロット、複数スロット、第一引数スロット、`<...>` レストスロット、`cute` の事前評価保証)
   - Group 5: SRFI 61 `cond` (多値生成、ガード真偽分岐、レシーバー多値適用、通常節との混合)
8. **ビルド & 総合検証**:
   - `Makefile` に `test_yellow_docket_macros` を追加し、`make -C ulisp test_yellow_docket_macros` をパス。
   - `scripts/verify_r7rs_traceability.py` による監査 100% PASS。
   - `make -C ulisp bootstrap` による 5 モジュール並列固定点収束。
   - `make -C ulisp test` の全テストスイート完走。
   - トリプル品質ゲート（`make py_compile && make check_format && make static_analysis`）100% PASS。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `receive` が任意個の多値（0個、1個、複数個、ドット対レスト引数）を正しく束縛して評価できること。
- [x] `rec` が関数短縮形および値束縛形の自己参照無名再帰として正しく動作すること。
- [x] `and-let*` が真値束縛の連鎖および `#f` 短絡を仕様通りに実行すること。
- [x] `cut` および `cute` がスロット `<>`, `<...>` を正しくラムダ式へ展開し、`cute` において非スロット引数の即時副作用評価が保証されること。
- [x] SRFI 61 `(<generator> <guard> => <receiver>)` 節が単値および多値を正しく渡し、真偽ガードによる条件分岐が機能すること。
- [x] `(srfi 8)`, `(srfi 26)`, `(srfi 31)`, `(srfi 2)`, `(srfi 61)` の各 `.sld` ライブラリ定義が作成され、Traceability ヘッダーを満たすこと。
- [x] 新規テストスイート `test_yellow_docket_macros.scm` の全グループが 100% PASS すること。
- [x] `scripts/verify_r7rs_traceability.py` の監査が 100% PASS すること。
- [x] `make -C ulisp bootstrap` による自己ホスト 5 モジュール並列ビルドが固定点収束（Stage 2 == Stage 3 ビット完全一致）すること。
- [x] `make -C ulisp test` の全テストスイートがエラーなく完走すること。
- [x] トリプル品質ゲート（`make py_compile && make check_format && make static_analysis`）が 100% PASS すること。
- [x] ドキュメントやソースコード内に絶対パスが含まれず、すべて相対パスであること。

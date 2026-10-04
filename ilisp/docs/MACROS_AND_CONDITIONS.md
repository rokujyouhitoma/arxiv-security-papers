# ILISP 衛生的マクロ・コンディション・テストハーネス仕様書 (Macros, Conditions & Test Harness)

本ドキュメントは、ILISP (Intelligence LISP) における **Scope Sets 衛生的マクロ展開器**、**現場復帰型コンディション機構**、および **独立テスト実行ハーネス (`test_harness.scm`)** の技術仕様を規定します。

---

## 1. Scope Sets 衛生的マクロ (`define-syntax` & `syntax-rules`)

ILISP は Matthew Flatt (2016) による **Scope Sets アルゴリズム** をマクロ展開エンジンの核として採用しています。

### 1.1 Scope Sets の原理と利点

- **従来の構文リネーム（Kohlbecker）の限界**:
  古典的なアルゴリズムではマクロ展開のパスごとに識別子にマークを付与・置換するため、入れ子マクロやマクロを生成するマクロで予期せぬ名前衝突（Capture）やバインディング消失が発生していました。
- **Scope Sets アプローチ**:
  - すべての識別子（`Symbol`）は、自身が導入された「レキシカルスコープの集合（`Set[Scope]`）」を不変属性として保持します。
  - マクロ展開時に新たなスコープトークンが生成され、マクロ導入構文内の識別子に付与されます。
  - 変数束縛の解決時、参照箇所のスコープ集合の最大真部分集合を持つ定義が数学的一意性をもって照合されます。
  - これにより、意図しない変数の捕捉（Capture）が論理的に排除されます。

### 1.2 パターンマッチングとエリプシス展開 (`...`)

`syntax-rules` は、複数のパターン節とテンプレートから構成され、ゼロ個以上の任意反復を示すエリプシス（`...`）を完全サポートします。

```scheme
(define-syntax my-cond
  (syntax-rules (else =>)
    ((my-cond (else result1 result2 ...))
     (begin result1 result2 ...))
    ((my-cond (test => recipient))
     (let ((temp test))
       (if temp (recipient temp))))
    ((my-cond (test result1 result2 ...) more-clauses ...)
     (if test
         (begin result1 result2 ...)
         (my-cond more-clauses ...)))))
```

---

## 2. 伝統的構文マクロ (`define-macro`)

ブートストラップ初期段階およびコンパイラ内部の脱糖処理を軽量に行うため、S 式 AST を直接変換する伝統的 Lisp マクロ（`define-macro`）も並行サポートしています。

```scheme
(define-macro (when test . body)
  `(if ,test (begin ,@body)))

(define-macro (unless test . body)
  `(if ,test '() (begin ,@body)))
```

---

## 3. 現場復帰型コンディション・例外機構 (Conditions & Restarts)

ILISP は R7RS-small 第6.11節「Exceptions」の完全準拠に加え、Common Lisp 思想を継承した現場復帰型コンディションシステムを提供します。

### 3.1 R7RS 標準例外手続き

- **`(with-exception-handler handler thunk)`**:
  - `thunk` の動的エクステント内で発生した例外を `handler`（1引数手続き）へ渡す。
- **`(raise obj)`**:
  - 巻き戻しを伴う脱出例外を送出。ハンドラが戻った場合は `&non-continuable` エラーとなる。
- **`(raise-continuable obj)`**:
  - 現場復帰型例外を送出。ハンドラが値を返した場合、その値が `raise-continuable` の評価値となり、計算が現場からそのまま継続される。
- **`(guard (var clause ...) body ...)`**:
  - `call/cc` と `with-exception-handler` を組み合わせた構造化例外捕捉構文。

```scheme
(define (safe-divide a b)
  (guard (e ((error-object? e)
             (display "Error handled: ")
             (display (error-object-message e))
             (newline)
             0))
    (/ a b)))
```

---

## 4. 独立テスト実行ハーネスアーキテクチャ (`test_harness.scm`)

外部標準テスト（chibi-scheme 公式テストスイート）の安全な取り込みと、弊社独自知的財産（IP）のライセンス保護を両立するため、テストフレームワークは物理的に完全分離されています。

```
ilisp/tests/
├── r7rs_tests.scm     # chibi-scheme 原本 R7RS テストスイート (Alex Shinn, 3-Clause BSD)
│                      # ※ テストハーネスを含まない純粋な上流コードのみを保持
└── test_harness.scm   # ILISP 独自テスト実行ハーネス (Project ILISP Authors, MIT License)
                       # ※ test, test-assert, test-error, test-values, 失敗ログ記録機構
```

### 4.1 テストハーネス API 仕様

`ilisp/tests/test_harness.scm` で提供されるアサーション構文：

| 構文 | 形式 | 動作仕様 |
| :--- | :--- | :--- |
| `test-begin` | `(test-begin "name")` | テストスイート初期化・カウンタ（`*test-passes*`, `*test-failures*`, `*test-errors*`）のリセット |
| `test` | `(test name-or-expected [expected] expr)` | 式を評価し、期待値との等価性（`equal?` / `eqv?`）を検証 |
| `test-assert` | `(test-assert [name] expr)` | 式が真値（`#f` 以外）を返すことを検証 |
| `test-error` | `(test-error [name] expr)` | 式の評価時に例外が送出されることを検証 |
| `test-values` | `(test-values expected expr)` | 式が多値（Multiple Values）を返し、各値が期待リストと一致することを検証 |
| `test-end` | `(test-end)` | テスト集計を出力し、結果リスト `(total passes failures errors)` を返却 |

### 4.2 失敗ログ記録と自動診断レポート

不合格（FAIL）または予期せぬ例外（ERROR）が発生した場合、ハーネスは即座に `*test-failure-log*` に以下の構造化レコードを追記します：

```scheme
;; 失敗ログの構造
(list 'fail test-name expr expected actual)
(list 'error test-name expr exception-object)
```

CI テストランナー（`tests/ilisp/test_chibi_r7rs_compliance.py`）はこのログを自動走査し、FAIL/ERROR が 1 件でも存在する場合は整形された詳細診断レポートをコンソール出力してテストを即時不合格とします。

---

## 5. 関連ドキュメント体系

- [README.md](README.md): ILISP 概要・クイックスタート・3本柱アーキテクチャ
- [SPEC_R7RS.md](SPEC_R7RS.md): R7RS-small 全203機能の仕様準拠マトリクス & chibi-scheme 公式テスト 100% 適合検証レポート
- [PYTHON_INTEROP.md](PYTHON_INTEROP.md): Python 双方向ゼロコピー相互運用・SequenceView・双方向呼出仕様
- [BOOTSTRAP.md](BOOTSTRAP.md): Kernel ILISP 仕様 & 3段階ブートストラップ連鎖 & 不動点検証
- [DSN-31 包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md): ILISP R7RS コアアーキテクチャ包括設計仕様書

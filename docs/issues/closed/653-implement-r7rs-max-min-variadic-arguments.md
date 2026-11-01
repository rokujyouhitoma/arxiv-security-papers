---
ID: 653
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS §6.2.6 max および min 手続きの可変長引数対応 (ID: 653)

## 1. 概要 / Summary
R7RS-small §6.2.6 (Numerical operations) で規定されている `(max x1 x2 ...)` および `(min x1 x2 ...)` 手続きを、1 引数以上（任意個数）の可変長引数で呼び出し可能にする。
ULisp において、Pass 030 (`030_desugar.scm`) によるインライン直列展開（アロケーションゼロの二項比較連鎖）と、`ulisp/lib/math.scm` における二項カーネル（`max-2`, `min-2`）および第一級手続きオブジェクト（`case-lambda` による動的呼び出しサポート）を整備し、静的呼び出しと `apply` / 高階関数呼び出しの両方を完全サポートする。

---

## 2. 背景と技術的課題 / Background & Technical Challenges
1. **可変長引数のゼロアロケーション最適化 (Pass 030 脱糖)**:
   - 静的な直接呼び出し（例: `(max a b c d)`）に対し、リスト割り当てや手続き呼び出しオーバーヘッドをゼロにするため、Pass 030 で左畳み込み二項比較連鎖 `(max-2 (max-2 (max-2 a b) c) d)` に展開する。
   - 1 引数呼び出し `(max x)` は単に引数自身 `x` に脱糖する。
2. **第一級手続きオブジェクトと `apply` / 高階関数サポート**:
   - `(apply max lst)` や `(map max list1 list2)` 等で手続きとして渡される場合に対応するため、`ulisp/lib/math.scm` に `case-lambda` による手続き定義を配置する。
   - トップレベルの可変長引数定義 `(define (f x . rest) ...)` が引き起こすコンパイラセグフォを回避するため、Pass 028 で安全に展開される `case-lambda` を使用して 1〜4 引数および任意個数ループを定義する。
3. **0 引数呼び出しの厳格なエラーハンドリング**:
   - R7RS 仕様では `max` / `min` は 1 個以上の引数を要求する（0 引数は未定義/エラー）。
   - コンパイル時脱糖（Pass 030）において `(max)` / `(min)` を検出した場合は構文エラーを発行し、実行時手続き呼び出し時も arity エラーとして弾く。
4. **整数塔・負数・極値の正確な比較**:
   - 負の Fixnum、0、正の Fixnum が混在するリストに対しても正確な順序比較（`>` / `<`）を維持する。

---

## 3. セキュリティ要件と脅威分析 / Security Considerations
- **CWE-1284: 不正な引数個数の検証 (Improper Validation of Specified Quantity in Input)**:
  - 0 引数呼び出し `(max)` / `(min)` に対し、不正なメモリアクセスや未定義動作を防止し、明確な arity error を発行。
- **CWE-190: 整数オーバーフロー耐性**:
  - `max` / `min` は比較操作のみを行い、加算・乗算を行わないため値の拡大によるオーバーフローリスクはゼロ。
  - 62-bit Fixnum の全範囲（`[-2^61, 2^61 - 1]`）にわたって比較演算子 `>` / `<` が正しく動作することを保証。
- **DoS / スタックオーバーフロー耐性**:
  - 大量引数の脱糖時にも左畳み込み木による線形展開を行い、深い再帰によるコンパイラスタック枯渇を防止。

---

## 4. トレーサビリティ / Traceability
- **R7RS-small 仕様**:
  - Section 6.2.6 (Numerical operations: `max`, `min`)
- **仕様リファレンス**: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.3 (6.2.6)
- **関連モジュール**:
  - [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm)
  - [ulisp/lib/math.scm](../../ulisp/lib/math.scm)
  - [ulisp/lib/scheme/base.sld](../../ulisp/lib/scheme/base.sld)
  - [ulisp/tests/test_max_min.scm](../../ulisp/tests/test_max_min.scm)

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files
- [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm):
  - `desugar-max` および `desugar-min` ヘルパー関数の追加。
  - `desugar-all` における `((max . ,args) ...)` および `((min . ,args) ...)` パターンのマッチと脱糖。
- [ulisp/lib/math.scm](../../ulisp/lib/math.scm):
  - 二項カーネル `max-2` および `min-2` の定義。
  - 第一級手続きオブジェクト `max` および `min` の `case-lambda` 定義。
- [ulisp/lib/scheme/base.sld](../../ulisp/lib/scheme/base.sld):
  - `(scheme base)` からの `max`, `min` export の確認。
- [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md):
  - §6.2.6 `max`, `min` のステータスを `△` から `◎` に更新。
- [ulisp/tests/test_max_min.scm](../../ulisp/tests/test_max_min.scm):
  - 新規テストスイート（単一引数、二引数、任意可変長引数、負数/ゼロ混在、Fixnum境界値、apply/高階関数連携、0引数エラー）。
- [ulisp/Makefile](../../ulisp/Makefile):
  - `test_max_min` ターゲットの追加および `test:` への統合。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/653-implement-r7rs-max-min-variadic-arguments`

1. **Pass 030 (`ulisp/frontend/030_desugar.scm`) での脱糖実装**:
   ```scheme
   (define (desugar-max args)
     (cond
       ((null? args) (error "max: requires at least one argument"))
       ((null? (cdr args)) (car args))
       ((null? (cddr args)) (list 'max-2 (car args) (cadr args)))
       (else
        (let loop ((curr (list 'max-2 (car args) (cadr args)))
                   (rest (cddr args)))
          (if (null? rest)
              curr
              (loop (list 'max-2 curr (car rest)) (cdr rest)))))))

   (define (desugar-min args)
     (cond
       ((null? args) (error "min: requires at least one argument"))
       ((null? (cdr args)) (car args))
       ((null? (cddr args)) (list 'min-2 (car args) (cadr args)))
       (else
        (let loop ((curr (list 'min-2 (car args) (cadr args)))
                   (rest (cddr args)))
          (if (null? rest)
              curr
              (loop (list 'min-2 curr (car rest)) (cdr rest)))))))
   ```
   `desugar-all` に以下を追加:
   ```scheme
   ((max . ,args) (Expr (desugar-max (map Expr args))))
   ((min . ,args) (Expr (desugar-min (map Expr args))))
   ```
2. **`ulisp/lib/math.scm` での二項カーネルおよび手続き定義**:
   ```scheme
   (define (max-2 a b)
     (if (> a b) a b))

   (define (min-2 a b)
     (if (< a b) a b))

   (define max
     (case-lambda
       ((a) a)
       ((a b) (max-2 a b))
       ((a b c) (max-2 (max-2 a b) c))
       ((a b c d) (max-2 (max-2 (max-2 a b) c) d))
       ((a b c d . rest)
        (let loop ((m (max-2 (max-2 (max-2 a b) c) d)) (r rest))
          (if (null? r)
              m
              (loop (max-2 m (car r)) (cdr r)))))))

   (define min
     (case-lambda
       ((a) a)
       ((a b) (min-2 a b))
       ((a b c) (min-2 (min-2 a b) c))
       ((a b c d) (min-2 (min-2 (min-2 a b) c) d))
       ((a b c d . rest)
        (let loop ((m (min-2 (min-2 (min-2 a b) c) d)) (r rest))
          (if (null? r)
              m
              (loop (min-2 m (car r)) (cdr r)))))))
   ```
3. **テストスイート `ulisp/tests/test_max_min.scm` の作成**:
   - Group 1: 1 引数呼び出し（`(max 42)` => `42`, `(min -10)` => `-10`）
   - Group 2: 2 引数基本比較（正数、負数、同一値、ゼロ）
   - Group 3: 3〜10 引数の任意個数可変長呼び出し（昇順、降順、ランダム順、重複値）
   - Group 4: Fixnum 境界値（Fixnum Max / Min、極値比較）
   - Group 5: 高階関数および `apply` 経由の呼び出し（`(apply max '(1 9 4 2))`）
4. **Makefile, Bootstrap & Triple Quality Gates**:
   - `test_max_min` ターゲット追加および `make test` 統合。
   - `./bootstrap.sh`（3-Stage Bootstrap 固定点収束検証）。
   - `make check_format` および `make static_analysis` の完全通過。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `(max 42)` => `42`、`(min -10)` => `-10` の 1 引数呼び出しが正しく動作すること。
- [x] `(max 10 20)` => `20`、`(min 10 20)` => `10` の 2 引数呼び出しが正しく動作すること。
- [x] `(max 1 9 4 2 8 3)` => `9`、`(min 5 2 8 1 9 7)` => `1` 等の 3 引数以上の可変長呼び出しが正しく評価されること。
- [x] 同一値比較（例: `(max 5 5 5)` => `5`）および負数混在比較（例: `(min -5 -20 0 10)` => `-20`）が正しく動作すること。
- [x] `(apply max '(1 5 3 9 2))` および `(apply min '(1 5 3 9 2))` が正しく評価されること。
- [x] `tests/test_max_min.scm` の全テストが 100% PASS すること。
- [x] 3-Stage Bootstrap (`./bootstrap.sh`) で固定点収束し、Stage 2/3 出力が完全一致すること。
- [x] `ref_r7rs_compliance.md` の §6.2.6 `max`, `min` が `◎` に更新されていること。
- [x] すべての内部リンクが相対パスで記述されていること。


---
ID: 867
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] make-vector および make-bytevector 充填コンストラクタのインライン脱糖 (ID: 867)

## 1. 概要 / Summary
R7RS Section 6.8 (Vectors) および Section 6.9 (Bytevectors) では、充填値 `fill` を受け取る 2 引数コンストラクタ `(make-vector k fill)` および `(make-bytevector k fill)` が規定されている。
現在、Pass 026 ([ulisp/frontend/026_desugar_constructors.scm](../../ulisp/frontend/026_desugar_constructors.scm)) において、`(make-string k ch)` は `desugar-make-string-fill` によりインラインのループ展開（`let` + `letrec`）へ脱糖されているが、`make-vector` と `make-bytevector` は外部ライブラリ関数 `make-vector-fill` / `make-bytevector-fill` への関数呼び出しに脱糖されている。

このため、`(make-vector 3 42)` や `(make-bytevector 3 42)` といった極めて基本的な 2 引数コンストラクタ式を評価・コンパイルする際にも、標準ライブラリ（`lib/vector.scm` や `lib/bytevector.scm`）の include が必須となっている。
これにより、ポータブル C バックエンドテスト（`test_c`）での重複コンパイル負荷、および組み込み・ベアメタル・最小構成バイナリにおけるフットプリント増大の原因となっている。

本 Issue では、`make-vector` および `make-bytevector` の 2 引数フォームを `desugar-make-string-fill` と同様のアーキテクチャでコンパイラ内部にて完全インライン脱糖し、外部関数への暗黙依存を完全解消する。

---

## 2. トレーサビリティ / Traceability
- **規格準拠**:
  - R7RS Section 6.8 (Vectors): `(make-vector k [fill])`
  - R7RS Section 6.9 (Bytevectors): `(make-bytevector k [byte])`
  - DSN-33 Section 4.2 (Nanopass Architecture Specification)
- **関連 Issue**:
  - [Issue #866: test_c.sh のライブラリ過剰 include 解消による C バックエンドテスト大幅高速化](closed/866-optimize-test-c-library-includes-for-high-speed-execution.md)
  - [Issue #868: lib/vector.scm と lib/srfi/133.scm のモジュール分離](868-modularize-r7rs-vector-and-srfi-133-libraries.md)
- **対象ソースコード**:
  - [ulisp/frontend/026_desugar_constructors.scm](../../ulisp/frontend/026_desugar_constructors.scm)
  - [ulisp/tests/passes/test_026_desugar_constructors.scm](../../ulisp/tests/passes/test_026_desugar_constructors.scm)
  - [ulisp/lib/vector.scm](../../ulisp/lib/vector.scm)
  - [ulisp/lib/bytevector.scm](../../ulisp/lib/bytevector.scm)
  - [ulisp/test_c.sh](../../ulisp/test_c.sh)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/frontend/026_desugar_constructors.scm](../../ulisp/frontend/026_desugar_constructors.scm) : `desugar-make-vector-fill` および `desugar-make-bytevector-fill` の追加、`desugar-make-vector` / `desugar-make-bytevector` の脱糖先変更
- [ ] [ulisp/tests/passes/test_026_desugar_constructors.scm](../../ulisp/tests/passes/test_026_desugar_constructors.scm) : 単体テストの追加
- [ ] [ulisp/lib/vector.scm](../../ulisp/lib/vector.scm) : `make-vector-fill` の後方互換性維持確認
- [ ] [ulisp/lib/bytevector.scm](../../ulisp/lib/bytevector.scm) : `make-bytevector-fill` の後方互換性維持確認
- [ ] [ulisp/test_c.sh](../../ulisp/test_c.sh) : `make-vector 3 42` / `make-bytevector 3 42` のゼロ include 化によるさらなる実行時間短縮

---

## 4. 根本原因と設計方針 / Root Cause & Design Approach

### 4.1 現行実装の課題
Pass 026 ([ulisp/frontend/026_desugar_constructors.scm](../../ulisp/frontend/026_desugar_constructors.scm)) において：
```scheme
;; 現行: make-bytevector
(define (desugar-make-bytevector args)
  (if (null? (cdr args))
      (list '%make-bytevector (car args))
      (list 'make-bytevector-fill (car args) (cadr args))))

;; 現行: make-vector
(define (desugar-make-vector args)
  (if (null? (cdr args))
      (list '%make-vector (car args))
      (list 'make-vector-fill (car args) (cadr args))))
```
1 引数の場合はコンパイラ組込みの `%make-vector` / `%make-bytevector`（LIR プリミティブ）へ脱糖されるが、2 引数の場合はライブラリ手続き `make-vector-fill` / `make-bytevector-fill` を参照する AST に変形される。
そのため、ライブラリがロードされていない最小環境では未束縛シンボルエラーとなり、ポータブル C バックエンドテストでも数万行の stdlib include が必要となっていた。

### 4.2 脱糖後の AST 構造設計
Pass 026 の `desugar-make-string-fill` と整合する構造を採用する。

1. **`make-vector` (2 引数: `(make-vector k fill)`)**:
```scheme
(define (desugar-make-vector-fill k fill)
  (let ((n-sym (unique-symbol "mv_n_"))
        (f-sym (unique-symbol "mv_f_"))
        (v-sym (unique-symbol "mv_v_"))
        (i-sym (unique-symbol "mv_i_"))
        (loop-sym (unique-symbol "mv_loop_")))
    (list 'let (list (list n-sym k) (list f-sym fill))
          (list 'let (list (list v-sym (list '%make-vector n-sym)))
                (list 'letrec
                      (list (list loop-sym
                                  (list 'lambda (list i-sym)
                                        (list 'if (list '< i-sym n-sym)
                                              (list 'begin
                                                    (list 'vector-set! v-sym i-sym f-sym)
                                                    (list loop-sym (list '+ i-sym 1)))
                                              v-sym))))
                      (list loop-sym 0))))))
```

2. **`make-bytevector` (2 引数: `(make-bytevector k byte)`)**:
0 充填の場合は calloc / ゼロ初期化を活かして O(1) で即座に返却し、非ゼロの場合のみループを回す最適化を内蔵する：
```scheme
(define (desugar-make-bytevector-fill k byte)
  (let ((n-sym (unique-symbol "mbv_n_"))
        (b-sym (unique-symbol "mbv_b_"))
        (bv-sym (unique-symbol "mbv_bv_"))
        (i-sym (unique-symbol "mbv_i_"))
        (loop-sym (unique-symbol "mbv_loop_")))
    (list 'let (list (list n-sym k) (list b-sym byte))
          (list 'let (list (list bv-sym (list '%make-bytevector n-sym)))
                (list 'if (list '= b-sym 0)
                      bv-sym
                      (list 'letrec
                            (list (list loop-sym
                                        (list 'lambda (list i-sym)
                                              (list 'if (list '< i-sym n-sym)
                                                    (list 'begin
                                                          (list 'bytevector-u8-set! bv-sym i-sym b-sym)
                                                          (list loop-sym (list '+ i-sym 1)))
                                                    bv-sym))))
                            (list loop-sym 0)))))))
```

---

## 5. 実装計画 / Implementation Steps

Target Branch: `feat/867-inline-desugar-make-vector-and-make-bytevector-constructors`

### Step 1: Pass 026 のインライン脱糖器実装
1. [ulisp/frontend/026_desugar_constructors.scm](../../ulisp/frontend/026_desugar_constructors.scm) に `desugar-make-vector-fill` および `desugar-make-bytevector-fill` を定義。
2. `desugar-make-vector` および `desugar-make-bytevector` を更新し、引数が 2 個の場合は上記インライン脱糖器を呼び出すよう改修。
3. `make-vector-fill` および `make-bytevector-fill` のシンボル呼び出しをコンパイラフロントエンドから完全撤廃。

### Step 2: 単体テストの拡充
1. [ulisp/tests/passes/test_026_desugar_constructors.scm](../../ulisp/tests/passes/test_026_desugar_constructors.scm) に以下を追記：
   - `(make-vector 3 42)` の脱糖結果が `let` + `letrec` 構造を保持することのアサーション。
   - `(make-bytevector 3 42)` の脱糖結果が `let` + `if` + `letrec` 構造を保持することのアサーション。
   - 1 引数 `(make-vector 10)` および `(make-bytevector 16)` が引き続き `(%make-vector 10)` / `(%make-bytevector 16)` へ脱糖されることの回帰テスト。
2. `make -C ulisp test_passes` を実行し、全パス単体テストの合格を確認。

### Step 3: ポータブル C バックエンド・自己ホストの検証
1. `ulisp/test_c.sh` の include 判定から `"make-vector 3 42"` / `"make-vector 5 0"` および `"make-bytevector 3 42"` / `"make-bytevector 5 0"` をゼロ include へ移行。
2. `make -C ulisp test_c` を実行し、ライブラリ include なしで `#(42 42 42)` および `#u8(42 42 42)` が正しく出力されることを確認。
3. `make -C ulisp bootstrap` を実行し、自己ホストブートストラップの固定点（Fixpoint）を検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `(make-vector 3 42)` がライブラリ include なしでネイティブ C / x86-64 バックエンドで評価可能となり、`#(42 42 42)` を生成すること。
- [x] `(make-bytevector 3 42)` がライブラリ include なしで評価可能となり、`#u8(42 42 42)` を生成すること。
- [x] `make -C ulisp test_passes` の全 784 単体テストが正常に PASS すること。
- [x] `make -C ulisp test_c` の全 143 テストが正常に PASS すること。
- [x] `make -C ulisp bootstrap` による自己ホスト固定点（Stage 2 & Stage 3 bit-for-bit identical）が正常に収束・パスすること。
- [x] リポジトリ全域において絶対パス違反が 0 件であること。
- [x] Conventional Commits 規約に準拠したコミットが作成され、Issue がクローズされること。

---

## 7. 実装・検証結果サマリー
- **ブランチ**: `feat/867-inline-desugar-make-vector-and-make-bytevector-constructors`
- **成果**:
  - `ulisp/frontend/026_desugar_constructors.scm` (Pass 026) に `desugar-make-vector-fill` および `desugar-make-bytevector-fill` を実装。
  - `make-vector` 2 引数呼び出し（`(make-vector k fill)`）をインラインの `let` + `%make-vector` + `letrec loop` + `vector-set!` へ脱糖。
  - `make-bytevector` 2 引数呼び出し（`(make-bytevector k byte)`）をインラインの `let` + `%make-bytevector` + `(if (= byte 0) bv ...)` + `letrec loop` + `bytevector-u8-set!` へ脱糖。0 充填時は O(1) 即座返却。
  - `ulisp/test_c.sh` の `assert_c` include 判定から `make-vector 3 42`, `make-vector 5 0`, `make-bytevector 3 42`, `make-bytevector 5 0` を除外してゼロ include 化。
  - `make -C ulisp test_c` 実行時間: **1分49秒（109秒）**（Issue 866 の 124 秒からさらに 15 秒短縮、元 276 秒から合計 **167 秒 / 61% 削減**）。
  - `make -C ulisp test_passes`: 全 784 単体テスト 100% PASS。
  - `make -C ulisp bootstrap`: Stage 2 / Stage 3 の bit-for-bit 完全一致により自己ホスト収束・固定点検証完了。`bin/ulisp-boot` 更新完了。

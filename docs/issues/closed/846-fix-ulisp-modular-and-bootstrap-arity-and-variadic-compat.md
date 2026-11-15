---
ID: 846
種別: Bug
優先度: High
ステータス: Closed (Completed)
完了日: 2026-11-15
---

# [BUG/SEC] `make -C ulisp build/ulisp-modular` および `make -C ulisp bootstrap` ビルド失敗の修正と再発防止策の導入 (ID: 846)

## 1. 概要 / Summary
`make -C ulisp build/ulisp-modular` 実行時に `compiler_base` のネイティブコンパイルが `[ULISP ARITY ERROR] Builtin procedure '+' expects 2 argument(s), but got 3` で失敗し、また `make -C ulisp bootstrap` の Stage 1 においてネイティブシード `bin/ulisp-boot` による `compiler_entry.scm` のコンパイルが失敗して ILisp フォールバックが発生する不具合を修正した。併せて再発防止策としてコンパイラ脱糖パスの強化、大域束縛テーブルおよびスコープ解決エンジンの O(1) ハッシュ化・早期 break 最適化、および静的リンタ (`lint_sexpr.py`) による自動検証ゲートを実装した。

### 再現手順 / Steps to Reproduce
1. `make -C ulisp build/ulisp-modular` を実行する。
2. `make -C ulisp bootstrap` を実行し、Stage 1 ログを確認する。

### 再現環境 / Environment
- OS / Env: Linux / x86_64
- File: `../../ulisp/Makefile`, `../../ulisp/compiler_entry.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)
- [x] [sbi.scm](../../ulisp/compiler/sbi.scm)
- [x] [160_backend_c.scm](../../ulisp/backend/160_backend_c.scm)
- [x] [value_repr.scm](../../ulisp/compiler/value_repr.scm)
- [x] [pass_manager.scm](../../ulisp/compiler/pass_manager.scm)
- [x] [scope.scm](../../ulisp/compiler/scope.scm)
- [x] [binding.scm](../../ulisp/compiler/binding.scm)
- [x] [lir_verifier.scm](../../ulisp/lir/lir_verifier.scm)
- [x] [pass_check_affine.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm)
- [x] [pass_split_planes.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_split_planes.scm)
- [x] [131_lower_managed_dialect.scm](../../ulisp/lir/131_lower_managed_dialect.scm)
- [x] [compiler_entry.scm](../../ulisp/compiler_entry.scm)
- [x] [026_desugar_constructors.scm](../../ulisp/frontend/026_desugar_constructors.scm)
- [x] [028_desugar_bindings.scm](../../ulisp/frontend/028_desugar_bindings.scm)
- [x] [lint_sexpr.py](../../ulisp/scripts/lint_sexpr.py)
- [x] [test_lint_sexpr.py](../../ulisp/tests/test_lint_sexpr.py)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **可変長 `+` および 2 引数 `make-string` の残存**:
   ネイティブコンパイラ (`primitives.scm` / `040_analysis.scm`) では `+`, `*`, `/`, `=`, `<`, `<=`, `>`, `>=` は固定 2 引数プリミティブ (`binop-prim?`)、`make-string` は固定 1 引数プリミティブ (`unary-prim?`) である。ILisp/ホスト処理系上でのテスト時は許容されるため、`nanopass_meta.scm`、`sbi.scm`、`160_backend_c.scm` 内の計 7 箇所が見逃されていた。
2. **コンパイラソース内のドット引数・可変長仮引数 `(define (name ... . rest) ...)`**:
   ネイティブシード `bin/ulisp-boot` は生のドット仮引数 (`lambda` の非真リスト仮引数・単独シンボル仮引数) を直接コンパイルできない (クラッシュまたは未束縛グローバル化) 一方、`case-lambda` は `028_desugar_bindings.scm` で `(%num-args)` ベースに正規脱糖される。
3. **`compiler_entry.scm` と `Makefile` のファイルリスト乖離**:
   Issue #835〜#839 で `Makefile` に追加された `compiler/binding.scm`、`compiler/value_repr.scm`、`compiler/sbi.scm`、`lir/131_lower_managed_dialect.scm` の `(include ...)` 宣言が `compiler_entry.scm` に反映されていなかった。
4. **大域バインディング探索および自由変数親伝播の $O(N^2)$ 計算量爆発**:
   `binding.scm` における `*binding-by-id-table*` および `*binding-by-sym-table*` が単一線形 alist 走査であったため、大規模コードコンパイル時に探索が二乗遅延・数 GB ヒープ爆発を引き起こしていた。1024 バケットベクタによるハッシュテーブル化および親スコープ伝播の既知変数早期 break により、`pass-035-scope-resolve` を 370ms / <200MB へ高速・軽量化した。
5. **Managed Runtime Dialect と x86-64 ネイティブバックエンドの例外・継続整合性**:
   `131_lower_managed_dialect.scm` において `%push-handler` / `%pop-handler` / `%raise` を架空の `%c-call "ulisp_raise"` 等へ置換していたため、ネイティブ展開（`140_backend_x86_64.scm`）と不整合が生じていた。これらをバックエンド直接展開対象としてパススルーすることで完全解決した。

---

## 4. 恒久対策 / Permanent Fix
1. コンパイラソース全体から非 2 引数 `+` / 2 引数 `make-string` および生ドット仮引数定義を除去し、バイナリ演算・`case-lambda` 形式へ統一して既存シード `bin/ulisp-boot` でのネイティブコンパイルを回復した。
2. `compiler_entry.scm` に不足していたモジュールの `(include ...)` を追加同期した。
3. `binding.scm` に 1024 バケットハッシュテーブルを導入し、`scope.scm` での自由変数伝播ループに早期 break を実装して Stage 2/3 の超高速実行を達成した。
4. コンパイラフロントエンド (`026_desugar_constructors.scm`, `028_desugar_bindings.scm`) の脱糖ルールを拡充し、可変長 `+`/`*`、2 引数 `make-string` を自動脱糖可能にした。
5. `lint_sexpr.py` にセルフホスティング互換検査 (固定アリティプリミティブ・ドット仮引数禁止・第一級 `car`/`cdr` 禁止) を組み込み、ユニットテスト (`test_lint_sexpr.py`) を追加した。

---

## 5. 完了条件の検証結果 / DoD Verification
- [x] `make -C ulisp compiler.scm lint_sexpr test_lint_sexpr verify_zero_gauche` が成功すること (PASS)
- [x] `make -C ulisp build/ulisp-modular` がエラーなく完了し、`build/ulisp-modular` が生成・動作すること (PASS)
- [x] `make -C ulisp bootstrap` の Stage 1 が `bin/ulisp-boot` でネイティブ成功し、ILisp フォールバックせず不動点検証まで完遂すること (PASS: Stage 2 & 3 bit-for-bit IDENTICAL, smoke test 42 PASS)
- [x] 回帰テスト (`test_pass_manager_cache_invalidation`, `test_ir_serialization`, `test_inline_asm`, `test_value_representation`, `test_case_lambda`) が全件 PASS すること (PASS)
- [x] `make py_compile check_format static_analysis` がエラー 0 件で完了すること (PASS)

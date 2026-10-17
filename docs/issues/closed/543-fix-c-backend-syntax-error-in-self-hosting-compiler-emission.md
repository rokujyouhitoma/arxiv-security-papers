---
ID: 543
種別: Bug
優先度: High
ステータス: Closed (Fixed)
完了日: 2026-10-17
---

# [BUG] ULisp Portable C バックエンドにおける自己ホスティング・算術LIR出力構文エラーの修正 (ID: 543)

## 1. 概要 / Summary
ULisp の Portable C バックエンド (`passes/07_backend_c.scm`) を用いて Scheme コード（特に `compiler.scm` などの自己ホスティングコンパイラ）をコンパイルした際、生成される C ソースコードに `reg_rax = (uint64_t)(((int64_t)reg_rax););););` のような不正な括弧およびセミコロンが多重展開され、GCC や Clang でのビルド時に `error: expected ')' before ';' token` などのコンパイルエラーが発生していた。また、`ulisp_write_string` が未宣言・ディスパッチ未対応により `-Wimplicit-function-declaration` 警告/エラーとなる問題も併発していた。

### 再現手順 / Steps to Reproduce
1. 以下のコマンドを実行して C ソースを生成する:
   ```bash
   mkdir -p ulisp/build && \
   printf '(!target c)\n' | cat - ulisp/build/ulisp_core.scm > ulisp/build/ulisp_core_c.scm && \
   ./ulisp/bin/ulisp-boot ulisp/build/ulisp_core_c.scm > ulisp/build/ulisp_compiler.c
   ```
2. 生成された C コードを gcc でコンパイルする:
   ```bash
   gcc -O2 -Wall -Wextra -Werror ulisp/runtime.c ulisp/build/ulisp_compiler.c -o ulisp/build/ulisp-compiler
   ```
3. `error: expected ')' before ';' token` および `-Wimplicit-function-declaration` によりコンパイル失敗する。

### 再現環境 / Environment
- OS: Linux x86_64
- コンパイラ: GCC 11 / Clang 14
- 関連コンポーネント: `ulisp/passes/04_anf.scm`, `ulisp/passes/01_desugar.scm`, `ulisp/passes/07_backend_c.scm`, `ulisp/runtime.c`, `ulisp/bin/ulisp-boot`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/04_anf.scm](file:///workspace/arxiv-security-papers/ulisp/passes/04_anf.scm)
- [x] [ulisp/passes/01_desugar.scm](file:///workspace/arxiv-security-papers/ulisp/passes/01_desugar.scm)
- [x] [ulisp/passes/07_backend_c.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_c.scm)
- [x] [ulisp/passes/06_lir.scm](file:///workspace/arxiv-security-papers/ulisp/passes/06_lir.scm)
- [x] [ulisp/runtime.c](file:///workspace/arxiv-security-papers/ulisp/runtime.c)
- [x] [ulisp/bin/ulisp-boot](file:///workspace/arxiv-security-papers/ulisp/bin/ulisp-boot)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **ANF テンポラリ変数プールの枯渇と変数シャドウイング**:
   - `ulisp/passes/04_anf.scm` の `%t-var` が `%t0`〜`%t7` の 8 個しか定義されておらず、ネスト深度が 8 以上の場合は一律に `%t8` を返していた。
   - `passes/07_backend_c.scm` のような大規模な文字列生成・連結式において複数の引数が非アトムである場合、複数の引数に同一の `%t8` が割り当てられ、変数が衝突（シャドウイング）した。
   - その結果、`(string-append2 %t8 %t8)` のような自己複製呼び出しが生じ、末尾の `");"` が `"););););"` へと指数関数的に多重結合され、C99 構文として不正なコードが出力されていた。
2. **`string-append` 脱糖の線形展開による過剰な AST 深さ**:
   - `ulisp/passes/01_desugar.scm` の `desugar-string-append` が右結合の線形再帰 `(string-append2 s1 (string-append2 s2 ...))` であったため、多引数連結時に簡単にネスト深度 8 を超過していた。
3. **C バックエンドのヘッダ宣言および `%c-call` ディスパッチ不足**:
   - `passes/07_backend_c.scm` において `ulisp_write_string` の `extern` プロトタイプ宣言が不足し、`%c-call` 命令で `ulisp_write_string` が呼ばれた際に第 1 引数レジスタ `reg_rdi` に引数をセットしていなかった。また `runtime.c` の `print_scheme_value` が `static` となっていた。

---

## 4. 対策内容 / Permanent Fix
1. **ANF テンポラリ変数プールの拡張と動的フォールバック**:
   - `04_anf.scm` の `%t-var` を `%t0`〜`%t63` の 64 個に拡張し、さらに深度 64 超過時にも `(string->symbol (string-append "__anf_t_" (number->string depth)))` による一意な動的シンボル生成を行うよう改修。
2. **`string-append` の二分木バランス脱糖**:
   - `01_desugar.scm` の `desugar-string-append` を半分ずつ再帰分割する二分木バランス展開（$O(\log N)$ 深度）に改修し、AST ネスト深度を劇的に削減。
3. **C バックエンドプロトタイプ・ディスパッチ追加 & ランタイム整合**:
   - `07_backend_c.scm` に `extern uint64_t ulisp_write_string(uint64_t val);` および `extern void print_scheme_value(uint64_t val);` を追加。
   - `%c-call` ハンドラに `ulisp_write_string` 分岐を追加し、`reg_rdi` への引数転送を実装。
   - `runtime.c` の `print_scheme_value` を非 static に変更。
4. **自己ホスティング・ブートストラップ再生成**:
   - `./ulisp/bootstrap.sh` を実行し、Stage 2 と Stage 3 がビット一致（bit-for-bit identical）する固定小数点到達を確認し、`ulisp/bin/ulisp-boot` を更新。

---

## 5. 完了条件の検証結果 / Success Criteria (DoD)
- [x] `printf '(!target c)\n(define (f s) (string-ref s 0))\n(f "hello")\n' | ./ulisp/bin/ulisp-boot` で出力された C コードが GCC でエラーなくコンパイルできること。
- [x] `./ulisp/bin/ulisp-boot ulisp/build/ulisp_core_c.scm > ulisp/build/ulisp_compiler.c && gcc -O2 -Wall -Wextra -Werror ulisp/runtime.c ulisp/build/ulisp_compiler.c -o ulisp/build/ulisp-compiler` が警告・エラー 0 件でビルド完了し、自己ホスティングバイナリが正常動作すること。（5.8MB C コードから 807KB バイナリ生成成功）
- [x] `make -C ulisp test_c` および `test.sh` が 100% PASS すること。（全 42 テスト合格）

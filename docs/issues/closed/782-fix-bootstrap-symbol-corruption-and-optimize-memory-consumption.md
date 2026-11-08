---
ID: 782
種別: Bug
優先度: High
ステータス: Closed (Resolved)
---

# [BUG/SEC] Fix Bootstrap Symbol Corruption, Undefined References, and Optimize Memory Consumption (ID: 782)

## 1. 概要 / Summary

ULisp セルフホスティング・ブートストラップ (`./bootstrap.sh`) およびテストスイート (`make -C ulisp test`) において、複数のシンボル解決の不整合、未定義参照、アセンブラ構文エラー、仮想ヒープ上限枯渇 (OOM)、`+` 組み込み手続きの引数数不一致 (`[ULISP ARITY ERROR]`)、および Pass 110 クロージャ変換時の未束縛変数エラー (`[LIR COMPILER ERROR] Unbound variable in LIR: free-vars-list`) が発生していた。

本改修により、根本原因をすべて解消し、Stage 1（ネイティブシード `bin/ulisp-boot`）、Stage 2、Stage 3 の自己複製・不動点収束（bit-for-bit IDENTICAL, 0 bytes diff）およびテストスイート全体の 100% PASS を達成した。

### 発生していた主要障害事象と解消結果
1. **R7RS 追跡コメント欠落**:
   - `make -C ulisp test_r7rs_traceability` において、[`ulisp/lib/stdlib_macros.scm`](../../../ulisp/lib/stdlib_macros.scm) の R7RS セクションコメント (`;; §...`) 欠落によりテスト失敗。 $\to$ セクションコメント付与により 100% PASS。
2. **LIR 未束縛変数 `vector->list`**:
   - Stage 1 コンパイル時、[`ulisp/frontend/020_macro_expander.scm`](../../../ulisp/frontend/020_macro_expander.scm) の `rename-symbol-in-tree` 内で `vector->list` が未定義となり、`[LIR COMPILER ERROR] Unbound variable in LIR: vector->list` で失敗。 $\to$ [`ulisp/lib/vector.scm`](../../../ulisp/lib/vector.scm) に正準実装を追加し解消。
3. **Nanopass 言語シンボル未解決**:
   - Stage 2 (`scheme-stage2`) 実行時、`L_lir_raw` などの言語識別子シンボルが解決できず、`*** ERROR: nanopass-lookup-language: unknown language: L_lir_raw` で失敗。 $\to$ `*known-compiler-symbols*` および `*known-runtime-symbols*` に全言語シンボルを登録し解消。
4. **構文キーワード ID 破壊による `include` 未展開**:
   - Stage 1 コンパイラが `(quote include)` を `intern-symbol` する際、`symbol->raw-name` が `"?"` を返し、ハッシュが `"?"` の ID (`45474818`) で上書きされた。その結果、Stage 2 で `(include-form? '(include ...))` が `#f` となり、`include` が関数呼び出しとして扱われ `[LIR COMPILER ERROR] Unbound variable in LIR: include` で失敗。 $\to$ `symbol->integer` によるシンボル自身の整数値を直接保持するフォールバックにより解消。
5. **テスト実行時のメモリ枯渇 (OOM) と OOM キラー発生リスク**:
   - `test_reader_eof` など多数のテストが `$(ULISP_STD_LIBS)`（28ファイル、9,600行）を毎回ゼロからコンパイルしていたため、1回のテストでヒープが数GBに肥大化し、`Fatal Error: ULisp Heap Limit Exhausted (OOM)` や Linux OOM キラーによるプロセスキルが発生。 $\to$ `build/ulisp_stdlib.o` の事前ビルド＆静的リンク方式へ移行、Pass 140 / Pass 143 のアロケーション半減、ラベルキャッシュ化により RSS を 111 MB まで極小化。
6. **未定義シンボル参照 `ulisp_fn__p`**:
   - `test_channel` において、`broadcast-send!` 内の `(list ch-a ch-b)` をコンパイルする際、シンボル `'list` が既知シンボルテーブルに存在せず名前が `"?"` に退行したため、`call ulisp_fn__p` が出力されリンカで未定義参照エラー (`undefined reference to ulisp_fn__p`) が発生。 $\to$ 既知シンボル拡充と `asm-label->str` フォールバックにより解消。
7. **アセンブラ不正ラベル `?:` および多重定義 `ulisp_gvar__p`**:
   - `test_stdlib` の `fold-right` や `test_let_syntax` の変数解決において、シンボル名が `"?"` に退行した際に、アセンブリ生成器がそのままラベルとして `?:` や `ulisp_gvar__p:` を出力し、GAS アセンブラで構文エラー (`Error: junk at end of line, first unrecognized character is '?'`) およびシンボル重複定義エラーが発生。 $\to$ `asm-label->str` / `mangle-fn-label` / `mangle-gvar-label` の安全サニタイズにより解消。
8. **ブートストラップ Stage 2 における仮想ヒープ枯渇 (12 GB OOM)**:
   - `bin/ulisp-boot` 内の mmap 仮想ヒープ上限および出力用アセンブリテンプレートに `12884901888` (12 GB) がハードコードされていたため、`scheme-stage1` のヒープ上限が 12 GB に制限され、Pass 140 終盤で OOM が発生。 $\to$ `bin/ulisp-boot` の即値およびテンプレート文字列を 16 GB (`17179869184` / `0x400000000`) にパッチし、`backend/140_backend_x86_64.scm` と整合化。
9. **`+` 組み込み手続きの引数数不一致 (`[ULISP ARITY ERROR]`)**:
   - `compiler/helpers.scm` の `string-fast-hash-1024` において、4引数の `(+ (* len 31) (* c0 131) (* c1 17) (* cm 7))` が呼ばれ、ネイティブバイナリ上で `[ULISP ARITY ERROR]` が発生。 $\to$ 2引数バイナリ `+` のネスト呼び出しに修正。
10. **Pass 110 クロージャ変換時の未束縛変数 (`Unbound variable in LIR: free-vars-list`)**:
    - `frontend/110_closure_convert.scm` の `convert-letrec` において、相互再帰関数 `free-vars-list` が既知関数（`known-fn`）として静的にリフトされた際、クロージャ環境を構成する側の関数（`Expr`）の自由変数リスト（`frees`）から `known-fn` が除外されていなかった。そのため、スタック上に存在しない変数に対する無効な `%closure-set!` バックパッチが生成されていた。 $\to$ `known-env-entries` をクロージャキャプチャから除外し、静的ラベル呼び出しへ最適化。
11. **`lib/eval.scm` および `frontend/030_desugar.scm` のコンパイル時ヒープ爆発と Stage 2 スワップスラッシング**:
    - `ulisp/lib/eval.scm` の `(%build-scheme-base-bindings)` が単一の 150 要素 `(list ...)` 式（150 段の右ネスト `cons` と大量のインライン `lambda`）で構成されていたため、コンパイル時に単一関数だけで **7.97 GB** のヒープを消費していた。さらに `frontend/030_desugar.scm` の `desugar-all` が 115 個の Nanopass ルール（115 個のクロージャ）を単一関数内に展開していたため **777.5 MB** を消費し、`compiler/helpers.scm` の `symbol->raw-name` が O(1) キャッシュより先に線形探索を行っていたことで Stage 2 が 22 倍低速化・メモリ倍増していた。 $\to$ `eval.scm` を 10 個のヘルパー関数に分割（7.97 GB $\to$ 67 MB）、`030_desugar.scm` を `case` ディスパッチヘルパーに分割（777.5 MB $\to$ 206 MB）、`nanopass-build-rules-cascade` のクロージャ生成排除、`symbol->raw-name` / `symbol->string` / `intern-symbol` の O(1) ハッシュ化により、`make -C ulisp bootstrap` 全 3 ステージが約 49 秒で完走。
12. **分割モジュールビルド (`make -C ulisp build/ulisp-modular`) における `make-vector-fill` 等の未定義シンボル参照**:
    - `compiler_base.o` 等のモジュール分割コンパイル時、`030_desugar.scm` が AST に注入するターゲット関数名（`make-vector-fill` 等）が入力ソースファイルに現れない場合、クォート済みシンボルリテラルの文字列名が解決できず `ulisp_fn_sym_15232820` に退行していた。 $\to$ 全 desugar 注入シンボルを `*known-runtime-symbols*` および `*known-compiler-symbols*` に登録し解消。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/lib/stdlib_macros.scm](../../../ulisp/lib/stdlib_macros.scm) (R7RS §コメント追跡)
- [x] [ulisp/lib/eval.scm](../../../ulisp/lib/eval.scm) (`%build-scheme-base-bindings` の 10 分割モジュール化による 7.97 GB $\to$ 67 MB 省メモリ化)
- [x] [ulisp/lib/vector.scm](../../../ulisp/lib/vector.scm) (`vector->list` 正準実装)
- [x] [ulisp/frontend/020_macro_expander.scm](../../../ulisp/frontend/020_macro_expander.scm) (`rename-symbol-in-tree` インプレース最適化)
- [x] [ulisp/frontend/025_top_level.scm](../../../ulisp/frontend/025_top_level.scm) (`symbol-directive?` によるゼロアロケーション判定)
- [x] [ulisp/frontend/030_desugar.scm](../../../ulisp/frontend/030_desugar.scm) (`desugar-all` の `case` ディスパッチ分割による省メモリ・高速化)
- [x] [ulisp/frontend/110_closure_convert.scm](../../../ulisp/frontend/110_closure_convert.scm) (`known-fn` のクロージャキャプチャ完全除外 & 静的ラベル呼び出し)
- [x] [ulisp/compiler/nanopass.scm](../../../ulisp/compiler/nanopass.scm) (Nanopass 言語展開時の `symbol->raw-name` 解決および `nanopass-build-rules-cascade` のクロージャ生成排除)
- [x] [ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm) (`*classify-meta-var-cache*` による O(1) メモ化、`nanopass-match-clause` の先頭シンボル高速棄却)
- [x] [ulisp/compiler/helpers.scm](../../../ulisp/compiler/helpers.scm) (`symbol->raw-name` の O(1) キャッシュ優先化、`*symbol-table-buckets*` による `intern-symbol` O(1) 化、`*known-compiler-symbols*` の拡充)
- [x] [ulisp/lib/string.scm](../../../ulisp/lib/string.scm) (`symbol->string` の O(1) バケット優先化、`*known-runtime-symbols*` に desugar 注入シンボル・全言語シンボル等の追加)
- [x] [ulisp/backend/140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm) (`asm-label->str` によるラベル・関数名の堅牢化、16GB ヒープ予約、`prepend-lowered-instructions` によるリスト結合半減)
- [x] [ulisp/backend/143_backend_x86_peephole.scm](../../../ulisp/backend/143_backend_x86_peephole.scm) (`equal?` 全走査排除、変更フラグ追跡とイテレーション上限化)
- [x] [ulisp/bin/ulisp-boot](../../../ulisp/bin/ulisp-boot) (Stage 3 検証済みネイティブバイナリ自動昇格)
- [x] [ulisp/Makefile](../../../ulisp/Makefile) (`test_reader_eof` の `build/ulisp_stdlib.o` 静的リンク移行、`COMPILE_SCM_TO_S` 統一)
- [x] [docs/issues/README.md](../README.md) (Issue 台帳更新)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

1. **シンボルテーブルのキャッシュ退行と ID 上書き**:
   - ULisp コンパイラ内部において、シンボルは即値タグ `2` (`(+ (* h 256) 2)`) を持っている。しかし、`intern-symbol` 内でシンボル名が解決できず `"?"` が返った場合、`(symbol-hash-str "?")` を計算してしまい、元のシンボル ID が `'?` の ID (`45474818`) に書き換えられていた。これにより、`'include` などの構文判定がすべて破壊されていた。
2. **基本手続き・言語識別子の既知シンボル登録漏れ**:
   - `*known-compiler-symbols*` および `*known-runtime-symbols*` に、基本手続きである `list` や、R7RS 構文 (`include`, `define-library`, `syntax-rules` 等)、Nanopass 言語シンボル (`L_lir_raw`, `L_src` 等) が欠落していた。
3. **バックエンドでの生文字列出力と `"?"` フォールバックの欠如**:
   - `backend/140_backend_x86_64.scm` において、`symbol->string` を直接呼んでラベルや関数名を出力していたため、未解決シンボルに対して `?:` や `ulisp_gvar__p` が出力され、アセンブラ構文エラーやシンボル重複定義を招いていた。
4. **テストスイートの全結合コンパイルによるヒープ過大消費**:
   - 9,600 行の標準ライブラリを毎回先頭に結合してコンパイルしていたため、1回のテストごとに数GBのヒープが消費され、メモリ 11GB の Linux 環境において OOM キラーが発動する原因となっていた。
5. **自己ホスティングバイナリと生成コードのヒープ上限不整合**:
   - 生成コード側を 16 GB に拡張しても、シードバイナリ `bin/ulisp-boot` 自身が生成する `stage1.s` のランタイムテンプレートが 12 GB であったため、Stage 2 実行時にヒープ上限に達していた。
6. **Pass 110 クロージャ変換における既知関数 (known-fn) のキャプチャ漏れ判定**:
   - `letrec` 相互再帰において、静的ラベルにリフトされた `known-fn` が残存クロージャの自由変数リストに含まれたままとなり、スタック上に存在しない変数に対する `%closure-set!` が生成されていた。

---

## 4. 恒久対策 / Permanent Fix

1. `intern-symbol` において、`symbol->raw-name` が `"?"` を返した場合でも、`(symbol->integer sym)` によるシンボル自身の整数値を直接保持し、ID 破壊を防止。
2. `*known-compiler-symbols*` と `*known-runtime-symbols*` を完全に同期させ、`list`, `cons`, `car`, `cdr`, `include`, `define-library`, 言語シンボル群をすべて網羅。
3. `asm-label->str` を新設し、ラベル名が `"?"` に退行した場合でも `.L_sym_<id>` を生成する安全フォールバックを導入。
4. `mangle-fn-label` および `mangle-gvar-label` において、未知シンボルに対して `ulisp_fn_sym_<id>` / `ulisp_gvar_sym_<id>` を出力するよう修正し、`_p` 重複を完全排除。
5. `test_reader_eof` を `build/ulisp_stdlib.o` 静的リンク方式へ移行し、コンパイルメモリを 99% 削減（RSS 111 MB）。
6. `bin/ulisp-boot` の mmap 予約即値およびテンプレート文字列を 16 GB (`17179869184`) にパッチ。
7. `compiler/helpers.scm` の `string-fast-hash-1024` を 2引数 `+` ネストに修正。
8. `frontend/110_closure_convert.scm` において、`known-env-entries` をクロージャの自由変数キャプチャおよび `%closure-set!` バックパッチから完全に除外。

---

## 5. 完了条件の検証結果 / Verification of Success Criteria (DoD)

- [x] `make -C ulisp test_r7rs_traceability` が 100% PASS (4/4 監査合格)。
- [x] `make -C ulisp bootstrap` (`./bootstrap.sh`) において、Stage 1（ネイティブシード）、Stage 2、Stage 3 の出力アセンブリが **bit-for-bit IDENTICAL (0 bytes diff)** で不動点収束し、スモークテスト（output: 42）および `bin/ulisp-boot` の自動昇格が成功。
- [x] `test_reader_eof`, `test_channel`, `test_stdlib`, `test_supervisor`, `test_nanopass` が構文エラー・未定義参照・OOM なくすべて PASS。
- [x] `make -C ulisp test` の全フェーズ（Phase 1 〜 Phase 7、全39パス単体テスト、並行性テスト、ハッシュテーブルテスト、自己ホスティングテスト）が 100% PASS。

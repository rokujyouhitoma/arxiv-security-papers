---
ID: 629
種別: Feature
優先度: High
ステータス: Closed (Fixed)
---

# [FEAT/DX] 静的引数個数検証（Static Arity Checker）およびネイティブ実行時 Arity ガード診断の実装 (ID: 629)

## 1. 概要 / Summary
関数呼び出し時における**「実引数個数と仮引数個数の不整合（Arity Mismatch）」**をコンパイル時に静的検出するとともに、ネイティブ実行時（x86-64 バックエンド）に不正な引数個数での呼び出しを即座にトラップして関数名・引数個数付きで異常終了させる診断基盤を構築する。

現状、ULisp ネイティブコード（x86-64）の関数呼出し規約（`lir/124_lir_call_abi.scm`）では、呼び出し側で引数個数の Fixnum 表現（`(* num-args 4)`）が `%rax` レジスタにセットされて渡されている。しかし、**呼び出し先エントリでの引数個数検証（Arity Checking）が行われていない**。
このため、たとえば 2 引数で定義されている関数 `(define (append l1 l2) ...)` に対して 3 引数 `(append a b c)` を渡して呼び出した場合、コンパイル時にもネイティブ実行時にも警告やエラーが出力されない。その結果：
- 3 つ目以降の引数が静かに切り捨てられるか、スタックフレームの引数スロット計算が破壊される。
- 呼び出し先の内部式や親スコープの変数が解決できなくなり、全く無関係な箇所で `[LIR COMPILER ERROR] Unbound Variable Resolution Failed: Unbound Symbol : ...` や SEGV 等の不可解な障害として連鎖発現する（Issue #624 作業時にも実害が発生）。

※ なお、Gauche（`gosh`）等の成熟した処理系では動的 Arity Check が機能しており、`wrong number of arguments for #<closure (append l1 l2)> (required 2, got 3)` と即座に原因をピンポイントで報告できる。

本 Issue では、コンパイル時および実行時においてこの障害をゼロにする以下の防御機構を実装する：
1. **コンパイラ初期パスでの静的 Arity 検証 (Pass 040 / Pass 110)**:
   - 組み込みプリミティブ関数およびトップレベル既知関数について、呼出式の引数個数不一致をコンパイル段階で静的エラー（`[ULISP ARITY ERROR] ...`）として検出しコンパイルを安全に停止。
2. **ネイティブ実行時 Arity ガード (x86-64 バックエンド)**:
   - ネイティブ関数のプロローグにおいて期待引数個数を `%rax` と比較検証し、不一致時に `ulisp_arity_error(fn_name, expected, actual)` を発報して安全に異常終了させる実行時セーフティネットの整備。

---

## 2. セキュリティ分析 & 脅威モデリング / Security & Threat Analysis
- **脅威ベクトル (Threat Vector)**:
  - 引数不整合呼び出しによるスタック破壊 (Stack Frame Corruption):
    呼び出し側がスタックに積んだ引数個数と呼び出し先が期待するフレームオフセットの不一致により、未初期化スタック領域の参照や親フレームの戻りアドレス近傍の予期せぬメモリアクセスが発生する脆弱性。
  - サイレントな型混乱・未初期化変数伝播 (Type Confusion / Unbound Symbol Access):
    引数個数不足により呼び出し先でレジスタやスタックに残存したゴミ値がポインタとして解釈され、GC やデリファレンス時にクラッシュまたは不正メモリ読み取りが生じる。
- **緩和策 (Mitigation)**:
  - 多層防御 (Defense-in-Depth):
    1. コンパイル時 (AOT / JIT 前段階) の静的検証による事前排除。
    2. ネイティブ実行時 (x86-64 プロローグ) の動的アサーションによる不正呼び出しの即時遮断 (`sys_exit(1)` によるフェイルセーフ)。

---

## 3. トレーサビリティ / Traceability
- **関連 Issue**:
  - [624-phase1-direct-known-function-calls.md](624-phase1-direct-known-function-calls.md) (Pass 110 改修時に 3 引数 append による変数脱落障害が発生)
  - [605-enhance-bootstrap-diagnostics-and-fallback-trace.md](closed/605-enhance-bootstrap-diagnostics-and-fallback-trace.md) (ブートストラップ失敗時の診断トレース)
  - [625-phase2-system-v-register-based-calling-convention.md](closed/625-phase2-system-v-register-based-calling-convention.md) (System V レジスタ引数呼出規約における引数整合性)
  - [628-implement-sexpr-parenthesis-depth-linter-and-eof-diagnostic.md](628-implement-sexpr-parenthesis-depth-linter-and-eof-diagnostic.md) (S式構文解析診断の強化)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/primitives.scm](../../ulisp/compiler/primitives.scm) (組み込み関数・プリミティブの Arity シグネチャ定義)
- [x] [ulisp/frontend/040_analysis.scm](../../ulisp/frontend/040_analysis.scm) (呼出ノードにおける静的引数個数整合性バリデータ `check-arity-in-core-ast`)
- [x] [ulisp/frontend/110_closure_convert.scm](../../ulisp/frontend/110_closure_convert.scm) (既知関数・ローカル関数呼出における静的 Arity 検査)
- [x] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (関数エントリプロローグでの `%rax` (実引数個数) と期待引数個数の比較および Arity ガードルーチンの生成)
- [x] [ulisp/backend/141_backend_x86_gc.scm](../../ulisp/backend/141_backend_x86_gc.scm) または [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (`ulisp_arity_error` ハンドラの実装)
- [x] [ulisp/tests/passes/test_arity_checker.scm](../../ulisp/tests/passes/test_arity_checker.scm) (静的および動的 Arity 検証ユニットテスト)
- [x] [docs/issues/README.md](README.md) (Issue 台帳の進捗同期)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/629-implement-static-arity-checker-and-runtime-arity-guard`

1. **プリミティブ & 組み込み関数の静的 Arity 定義 (`compiler/primitives.scm`)**:
   - 既存の `zero-arg-prim?`, `unary-prim?`, `binop-prim?`, `triop-prim?`, `septop-prim?` を活用。
   - 一般的な組み込み標準関数（`append`, `equal?`, `list`, `string-append` 等）について固定引数個数テーブル `*builtin-fixed-arity*` および下限引数個数テーブル `*builtin-min-arity*` を定義。
   - `(lookup-builtin-arity op)` で期待引数シグネチャ `(exact . N)` または `(min . N)` を取得可能にする。

2. **静的 Arity 検証パス (`frontend/040_analysis.scm` & `frontend/110_closure_convert.scm`)**:
   - `check-arity-in-core-ast`: Pass 030 (`desugar-all`) 直後の Core AST を走査し、
     - トップレベルの `(define (fn x y) ...)` から関数名とパラメータ個数を収集。
     - 各呼び出し式 `(op arg1 ... argN)` において、`op` が組み込み関数または収集されたトップレベル関数であれば `N` と期待個数を比較。
     - 不一致時に `(error (string-append "[ULISP ARITY ERROR] Function '" (symbol->string op) "' expects ..."))` を発報して停止。
   - Pass 110 (`closure-convert`):
     - ローカル既知関数（`known-info`）やラムダ式に対する直接呼出（`%direct-call`）時にも二重で Arity 検査を実施。

3. **ネイティブ実行時 Arity ガード (`backend/140_backend_x86_64.scm`)**:
   - `lir/124_lir_call_abi.scm` では既に呼出時に `(%mov %rax (* num-args 4))` を emit している。
   - `select-instructions-function` (または `emit-x86-function`):
     - 関数の `params` リストの長さを `expected-count` とする。
     - 可変長引数（Rest parameter）を持たない通常関数において、プロローグで `%rax` と `expected-count * 4` を比較：
       ```nasm
       cmp rax, <expected-count * 4>
       jne .L_arity_error_<label>
       ```
     - 不一致時にジャンプするエラーブロック、または共通の `ulisp_arity_error` ルーチンへディスパッチするコードを emit。
   - `ulisp_arity_error`:
     - 関数エントリでエラーが起きた際、stderr に `[ULISP RUNTIME ERROR] Arity mismatch in function call` を出力し、`sys_exit(1)` で安全に終了。

4. **テストスイートの整備**:
   - 静的コンパイル時エラーの検出テスト: `(append 1 2 3)` や `(car)` などの不整合呼び出しが正しくエラーになることを検証。
   - ネイティブ実行時 Arity ガードテスト: 動的呼出で引数不整合が発生した場合にプロセスが exit code 1 で停止することを検証。
   - 既存の全テスト（`make -C ulisp test`）が誤検知なく PASS することを確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `(append a b c)` や `(car)` のような引数個数不整合コードに対して、コンパイル時にピンポイントな Arity エラー（`[ULISP ARITY ERROR]`）が報告されて安全に停止すること。
- [x] ネイティブ実行時（x86-64）に関数呼び出しの引数個数不整合が発生した場合、`ulisp_arity_error` がトラップしてプロセスが exit code 1 で終了すること。
- [x] `make -C ulisp test` の全テストスイートが 100% PASS すること（既存コードへの False Positive ゼロ）。
- [x] `docs/issues/` 台帳が更新され、git 規約に準拠したコミットが行われること。

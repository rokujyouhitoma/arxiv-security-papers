---
ID: 629
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/DX] 静的引数個数検証（Static Arity Checker）およびネイティブ実行時 Arity ガード診断の実装 (ID: 629)

## 1. 概要 / Summary
関数呼び出し時における**「実引数個数と仮引数個数の不整合（Arity Mismatch）」**をコンパイル時に静的検出するとともに、ネイティブ実行時（x86-64 バックエンド）に不正な引数個数での呼び出しを即座にトラップして関数名・引数個数付きで異常終了させる診断基盤を構築する。

現状、ULisp ネイティブコード（x86-64）の関数呼出し規約では、C 言語と同様に引数をスタックに push / レジスタにロードして呼出し命令を発行するのみで、**呼び出し先エントリでの引数個数検証（Arity Checking）が行われていない**。
このため、たとえば 2 引数で定義されている関数 `(define (append l1 l2) ...)` に対して 3 引数 `(append a b c)` を渡して呼び出した場合、コンパイル時にもネイティブ実行時にも警告やエラーが出力されない。その結果：
- 3 つ目以降の引数が静かに切り捨てられるか、スタックフレームの引数スロット計算が破壊される。
- 呼び出し先の内部式や親スコープの変数が解決できなくなり、全く無関係な箇所で `[LIR COMPILER ERROR] Unbound Variable Resolution Failed: Unbound Symbol : ...` や SEGV 等の不可解な障害として連鎖発現する（Issue #624 作業時にも実害が発生）。

※ なお、Gauche（`gosh`）等の成熟した処理系では動的 Arity Check が機能しており、`wrong number of arguments for #<closure (append l1 l2)> (required 2, got 3)` と即座に原因をピンポイントで報告できる。

本 Issue では、コンパイル時および実行時においてこの障害をゼロにする以下の防御機構を実装する：
1. **コンパイラ初期パスでの静的 Arity 検証**: `helpers.scm` 組み込み関数およびトップレベル既知関数について、呼出式の引数個数不一致をコンパイル段階（Pass 040 / Pass 110）で静的エラー（`Compile Error: arity mismatch`）として停止。
2. **デバッグ・ブートストラップ時ネイティブ Arity ガード**: ネイティブ関数のプロローグにおいて期待引数個数を検証し、不一致時に `ulisp_arity_error(fn_name, expected, actual)` を発報する実行時セーフティネットの整備。

---

## 2. トレーサビリティ / Traceability
- **関連 Issue**:
  - [624-phase1-direct-known-function-calls.md](624-phase1-direct-known-function-calls.md) (Pass 110 改修時に 3 引数 append による変数脱落障害が発生)
  - [605-enhance-bootstrap-diagnostics-and-fallback-trace.md](closed/605-enhance-bootstrap-diagnostics-and-fallback-trace.md) (ブートストラップ失敗時の診断トレース)
  - [625-phase2-system-v-register-based-calling-convention.md](closed/625-phase2-system-v-register-based-calling-convention.md) (System V レジスタ引数呼出規約における引数整合性)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm) (標準組み込み関数の静的 Arity シグネチャ定義テーブル)
- [ ] [ulisp/frontend/040_analysis.scm](../../ulisp/frontend/040_analysis.scm) (呼出ノードにおける静的引数個数整合性バリデータ)
- [ ] [ulisp/frontend/110_closure_convert.scm](../../ulisp/frontend/110_closure_convert.scm) (既知関数呼出における静的 Arity 検査)
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (デバッグフラグ時に関数エントリへ Arity アサーション命令列を出力)
- [ ] [ulisp/runtime/entry.scm](../../ulisp/runtime/entry.scm) (`ulisp_arity_error` ハンドラの実装)
- [ ] [docs/issues/README.md](README.md) (Issue 台帳の進捗同期)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/629-implement-static-arity-checker-and-runtime-arity-guard`

1. **静的 Arity テーブルとチェッカーの導入**:
   - `append` (2), `cons` (2), `car` (1), `cdr` (1), `set-car!` (2), `set-cdr!` (2) 等の固定引数コア関数の静的引数個数テーブルを定義。
   - `(op arg1 ... argN)` の AST 走査時に、既知の固定引数関数について `N != Arity` であればファイル・行番号とともに `Compile Error: arity mismatch for '<op>': expected <X>, got <Y>` を発報。
2. **可変長引数（Rest parameter）の考慮**:
   - `list`, `string-append` 等の可変長引数は下限値（>= min_args）のみを検証。
3. **ネイティブ実行時 Arity ガード（`ULISP_CHECK_ARITY=1`）**:
   - 引数個数を呼び出し時に特定レジスタ（またはメタ情報）で渡し、関数のプロローグで一致をアサートするモードを導入。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(append a b c)` のような引数個数不整合コードに対して、コンパイル時にピンポイントな Arity エラーが報告されて停止すること。
- [ ] 意図的な動的引数不整合呼び出しに対して、実行時に `ulisp_arity_error` が発報され、関数名と期待/実引数個数が出力されること。
- [ ] 既存の全テストスイート（`make test`, `./test.sh`）で誤検知（False Positive）なく 100% PASS すること。

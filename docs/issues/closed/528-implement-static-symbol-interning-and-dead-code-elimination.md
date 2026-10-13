---
ID: 528
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] 静的シンボル Intern テーブルおよび到達不能関数デッドコード除去 (DCE) による最適化 (ID: 528)

## 1. 概要 / Summary
現在、シンボルリテラル（例: `'a`）は Pass 5 (`closure-convert`) にて `(string->symbol "a")` という実行時関数呼び出しに脱糖され、`lib/string.scm` の実行時動的レジストリ（`*symbol-registry*`）に依存している。これにより、`test.sh` で `(eq? 'a 'a)` をテストするだけで `lib/string.scm` 全文（156行）の全量コンパイルが強制されている。
さらにコンパイラにトップレベル到達可能性解析に基づくデッドコード除去（Dead Code Elimination: DCE）が存在しないため、ライブラリ内の未使用関数（19個のクロージャ、1,698行のLIR命令）がすべて展開・生成・出力され、単一テストのコンパイル時間が 0.2秒から 23秒へ激増（83倍遅延）している。
本 Issue では、コンパイル時静的シンボル Interning 機構を導入し、CP0 最適化パスにトップレベル到達不能関数の DCE を実装することで、ライブラリ結合時のコンパイル負荷を根本的に削減する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: 
  - `ulisp/compiler.scm` (`convert-expr` quote handling, `cp0-optimize`)
  - `ulisp/passes/00_helpers.scm` (`intern-symbol`, `pure-expr?`)
  - `ulisp/passes/02_analysis.scm` (`free-vars` quote handling)
  - `ulisp/passes/03_cp0.scm` (`cp0-optimize`, `dce-letrec`)
  - `ulisp/passes/03b_lvn.scm` (`lvn-invalidate-pairs`)
  - `ulisp/passes/05_closure_convert.scm` (`convert-expr` quote handling)
  - `ulisp/passes/06_lir.scm` (`generate-lir`, `lir-compile-expr`)
  - `ulisp/lib/string.scm` (`string->symbol`, `*symbol-registry*`)
  - `ulisp/test.sh` (`assert` wrapper string.scm injection logic)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm)
- [x] [ulisp/passes/00_helpers.scm](../../ulisp/passes/00_helpers.scm)
- [x] [ulisp/passes/02_analysis.scm](../../ulisp/passes/02_analysis.scm)
- [x] [ulisp/passes/03_cp0.scm](../../ulisp/passes/03_cp0.scm)
- [x] [ulisp/passes/03b_lvn.scm](../../ulisp/passes/03b_lvn.scm)
- [x] [ulisp/passes/05_closure_convert.scm](../../ulisp/passes/05_closure_convert.scm)
- [x] [ulisp/passes/06_lir.scm](../../ulisp/passes/06_lir.scm)
- [x] [ulisp/tests/test_passes.scm](../../ulisp/tests/test_passes.scm)
- [x] [ulisp/test.sh](../../ulisp/test.sh)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/528-implement-static-symbol-interning-and-dead-code-elimination`

1. **コンパイル時静的シンボル Interning 機構**:
   - `ulisp/passes/00_helpers.scm`: `*symbol-table*` のリセット手続き `reset-symbol-table!` を定義し、既知シンボル定数の一意な整数ID（`tag = 2` の即値ポインタ: `(index << 8) | 2`）生成を保証。
   - `ulisp/passes/05_closure_convert.scm`: `(quote symbol)` を `(string->symbol "symbol")` に脱糖していたロジックを撤廃し、そのまま `(quote symbol)` を維持。
   - `ulisp/passes/02_analysis.scm`: `free-vars` において `quote` 式が `string->symbol` を自由変数として追加していた処理を削除（自由変数なし `'()`）。
   - `ulisp/passes/06_lir.scm`: `lir-compile-expr` の quote 式コンパイルで `intern-symbol` を用いて直接即値 `%mov %rax <id>` を出力。`generate-lir` 開始時に `reset-symbol-table!` を呼出し。

2. **CP0 パスにおけるトップレベル DCE (Dead Code Elimination)**:
   - `ulisp/passes/03_cp0.scm`: `dce-letrec` を実装。
     - `letrec` 束縛変数群（`rec-vars`）間の依存グラフ（Call Graph / Dependency Map）を構築。
     - メイン式 `body` 内の自由変数集合および副作用を持つ（`pure-expr?` が `#f` である）束縛変数を初期ルート集合（`initial-roots`）とする。
     - ワークリスト走査により到達可能な束縛変数の推移閉包（Transitive Closure）を計算。
     - 未到達な束縛を完全に剪定。全束縛が到達不能になった場合は `body` 自体に縮退。
   - `ulisp/passes/00_helpers.scm`: `pure-expr?` を拡張し、`letrec` 式の純粋性判定をサポート。
   - `ulisp/passes/03_cp0.scm`: `let` 式に対しても純粋かつ未参照の死んだ束縛を個別除去する汎用 DCE を導入。

3. **LVN における Pair 破壊的代入の健全な無効化**:
   - `ulisp/passes/03b_lvn.scm`: `lvn-invalidate-pairs` において `set-car!` / `set-cdr!` 発生時にタプルだけでなく `vns` 内の pair 構造体情報を `(type pair)` に降格させ、変更された pair に対する不健全なアクセサ畳み込みを抑止。

4. **`test.sh` のテスト前置依存の純化**:
   - `ulisp/test.sh`: `input =~ \'[a-zA-Z]` による `lib/string.scm` 強制注入ヒューリスティックを撤廃。`string->symbol` または `symbol->string` を直接呼び出すテストのみに注入対象を限定。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `(eq? 'a 'a)` および `(eq? 'a 'b)` が `lib/string.scm` の前置なしで正しくコンパイルおよび実行できること。
- [x] `lib/string.scm` を前置した場合でも、DCE により不要関数が除去され、生成 LIR 命令数が大幅に削減されること。
- [x] `FORCE_ILISP=1 ./test.sh` における `(eq? 'a 'a)` のコンパイル所要時間が 23秒から 0.5秒以下に短縮されること。
- [x] 全 127 以上の単体パス別テスト（`make -C ulisp test_passes`）および `test_lvn` が 100% PASS すること。
- [x] `test.sh`（ネイティブ AOT モード）の全フェーズテストが 100% PASS すること。

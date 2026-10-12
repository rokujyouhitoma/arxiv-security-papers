---
ID: 528
種別: Feature
優先度: High
ステータス: Open (New)
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
  - `ulisp/passes/02_cp0.scm`
  - `ulisp/passes/05_closure_convert.scm`
  - `ulisp/lib/string.scm` (`string->symbol`, `*symbol-registry*`)
  - `ulisp/test.sh` (`assert` wrapper string.scm injection logic)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm)
- [ ] [ulisp/passes/02_cp0.scm](../../ulisp/passes/02_cp0.scm)
- [ ] [ulisp/passes/05_closure_convert.scm](../../ulisp/passes/05_closure_convert.scm)
- [ ] [ulisp/passes/06_lir.scm](../../ulisp/passes/06_lir.scm)
- [ ] [ulisp/test.sh](../../ulisp/test.sh)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/528-implement-static-symbol-interning-and-dead-code-elimination`

1. **コンパイル時静的シンボル Interning 機構**:
   - コンパイラ内で既知のシンボル定数を静的ハッシュ/連想テーブルに記録し、一意な整数ID（`tag = 2` の即値ポインタ）へ直接変換。
   - 単純なシンボル比較 `(eq? 'a 'a)` において `string->symbol` の実行時動的探索呼び出しを不要化。
2. **CP0 パスにおけるトップレベル DCE (Dead Code Elimination)**:
   - メイン式から参照されている大域関数・変数をルート集合として到達可能性グラフ（Call Graph）を構築。
   - 到達不能な未呼出 `define` / 束縛を Pass 3 (ANF) および Pass 5 (クロージャ変換) の前段階で完全に剪定。
3. **`test.sh` のテスト前置依存の純化**:
   - 単純なシンボル比較テストに対して `lib/string.scm` を強制注入するヒューリスティックを撤廃。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(eq? 'a 'a)` および `(eq? 'a 'b)` が `lib/string.scm` の前置なしで正しくコンパイルおよび実行できること。
- [ ] `lib/string.scm` を前置した場合でも、DCE により不要関数が除去され、生成 LIR 命令数が大幅に削減されること。
- [ ] `FORCE_ILISP=1 ./test.sh` における `(eq? 'a 'a)` のコンパイル所要時間が 23秒から 0.5秒以下に短縮されること。
- [ ] 既存の全テストケースおよび自己ホスティング整合性が維持されること。

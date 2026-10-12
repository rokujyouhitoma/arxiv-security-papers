---
ID: 529
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] トップレベル定義の独立コンパイル構造化および自由変数解析集合演算の高速化 (ID: 529)

## 1. 概要 / Summary
`ulisp_core.scm` は 203KB、128 個のトップレベル `define` を含むが、Pass 0 (`rewrite-top-level`) において全 128 個の定義が単一の超巨大 `letrec` 構文木へと結合されている。
この結果、Pass 2 (スコープ解析) および Pass 5 (クロージャ変換 `convert-letrec`) における `free-vars` 解析において、128 個の相互再帰関数に対してリスト線形探索（`memq`, `set-union`）が数万〜数十万回呼び出され、$O(N^2 \sim N^3)$ の計算量爆発を招いている。
これが Stage 2（`scheme-stage1` による `ulisp_core.scm` のコンパイル）や Stage 3 の不動点検証において CPU 時間を著しく消費する主因となっている。
本 Issue では、トップレベル定義を単一 `letrec` へ抱き込まず独立したトップレベル実体として直列処理する構造へ刷新し、自由変数集合演算を高速化することで、自己ホスティングブートストラップ時間を抜本的に短縮する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: 
  - `ulisp/compiler.scm` (`rewrite-top-level`, `free-vars`, `convert-letrec`)
  - `ulisp/passes/01b_rewrite.scm`
  - `ulisp/passes/02_analysis.scm`
  - `ulisp/passes/05_closure_convert.scm`
  - `ulisp/bootstrap.sh` (Stage 1 / Stage 2 / Stage 3)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm)
- [ ] [ulisp/passes/01b_rewrite.scm](../../ulisp/passes/01b_rewrite.scm)
- [ ] [ulisp/passes/02_analysis.scm](../../ulisp/passes/02_analysis.scm)
- [ ] [ulisp/passes/05_closure_convert.scm](../../ulisp/passes/05_closure_convert.scm)
- [ ] [ulisp/passes/06_lir.scm](../../ulisp/passes/06_lir.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/529-implement-toplevel-separate-compilation-and-fast-free-vars`

1. **トップレベル定義の独立化（Pass 0 刷新）**:
   - トップレベル `define` を全量包括の巨大 `letrec` に変換するのを廃止し、`(%program ((%def name params body) ...) main-expr)` 構造へ正規化。
   - 大域定義はクロージャ環境ではなくグローバルシンボルとして扱い、環境キャプチャの走査対象から分離。
2. **`free-vars` 集合演算の高速化**:
   - 自由変数の探索と集合差分・和集合において、線形リストの `memq` 依存を解消し、ビットマップまたはプレフィックスツリー／整列リスト走査による高速演算を導入。
3. **Stage 2 / Stage 3 自己ホスティング検証**:
   - `make stage2` および `make stage3` のビルド時間をプロファイリングし、ビット完全一致（`cmp stage2.s stage3.s`）を維持した上で劇的な高速化を達成。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] トップレベル定義が巨大 `letrec` を介さずに独立してパイプライン処理されること。
- [ ] `free-vars` の集合演算負荷が削減され、Pass 2・Pass 5 の実行時間が半減以下になること。
- [ ] `bootstrap.sh` の Stage 2 / Stage 3 コンパイルがタイムアウトや中断なしに高速に完了すること。
- [ ] `diff stage2.s stage3.s` が 0 byte（完全一致）で PASS すること。

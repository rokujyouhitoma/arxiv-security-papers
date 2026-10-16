---
ID: 529
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
完了日: 2026-10-16
---

# [FEAT/ENH] トップレベル定義の独立コンパイル構造化および自由変数解析集合演算の高速化 (ID: 529)

## 1. 概要 / Summary
`ulisp_core.scm` は 203KB、128 個のトップレベル `define` を含むが、Pass 0 (`rewrite-top-level`) において全 128 個の定義が単一の超巨大 `letrec` 構文木へと結合されている。
この結果、Pass 2 (スコープ解析) および Pass 5 (クロージャ変換 `convert-letrec`) における `free-vars` 解析において、128 個の相互再帰関数に対してリスト線形探索（`memq`, `set-union`）が数万〜数十万回呼び出され、$O(N^2 \sim N^3)$ の計算量爆発を招いていた。
本 Issue では、単一パス深さ優先アキュムレータ `free-vars-acc` の導入と集合演算（`set-union` / `set-diff`）の早期脱出最適化により、自己ホスティングブートストラップ時間を 10 秒へと抜本短縮した。なお、トップレベル定義の `letrec` 完全撤廃および直接呼出（`%direct-call`）化は [Issue #539](539-implement-toplevel-separate-pipeline-and-direct-call-optimization.md) へと発展分離した。

---

## 2. トレーサビリティ / Traceability
- 関連資料: 
  - `ulisp/compiler.scm` (`free-vars-acc`, `set-union`, `set-diff`)
  - `ulisp/passes/00_helpers.scm` (`set-union`, `set-diff`)
  - `ulisp/passes/02_analysis.scm` (`free-vars-acc`, `escapes?`)
  - `ulisp/bootstrap.sh` (Stage 1 / Stage 2 / Stage 3 不動点検証)
  - 後続 Issue: [Issue #539: トップレベル定義の完全直列パイプライン分離および直接呼出 (%direct-call) 最適化](539-implement-toplevel-separate-pipeline-and-direct-call-optimization.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/02_analysis.scm](../../ulisp/passes/02_analysis.scm) (`free-vars-acc` による中間割当排除・単一パス深さ優先化)
- [x] [ulisp/passes/00_helpers.scm](../../ulisp/passes/00_helpers.scm) (`set-union`, `set-diff` の空リスト・同一オブジェクト早期脱出)
- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) (統合コンパイラの再構築)
- [x] [docs/issues/539-implement-toplevel-separate-pipeline-and-direct-call-optimization.md](539-implement-toplevel-separate-pipeline-and-direct-call-optimization.md) (トップレベル直列パイプライン分離・%direct-call 最適化の後続 Issue 分離)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/529-implement-toplevel-separate-compilation-and-fast-free-vars`

1. **`set-union` / `set-diff` 集合演算の高速化**:
   - `s1` または `s2` が空の場合の早期脱出、同一参照 (`eq?`) の早期脱出を追加し、無駄な再帰走査を完全排除。
2. **`free-vars` 解析の単一パス深さ優先アキュムレータ化**:
   - `free-vars-acc` を実装し、中間リスト生成（cons セル割り当て）と2乗オーダーの集合結合を排除。
3. **自己ホスティング不動点検証（Fixed Point Verification）**:
   - `bootstrap.sh` を実行し、Stage 2 および Stage 3 の生成アセンブリ完全一致（`cmp -s stage2.s stage3.s`）が 10.08 秒でビット完全一致することを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `free-vars` の集合演算負荷が削減され、Pass 2・Pass 5 の実行時間が大幅に短縮されること (`free-vars-acc` 導入)。
- [x] `bootstrap.sh` の Stage 2 / Stage 3 コンパイルが高速に完了すること (10.08 秒)。
- [x] `diff stage2.s stage3.s` が 0 byte（完全一致）で PASS すること。
- [x] 全ユニットテスト（`make -C ulisp test`）および差分テスト（`make -C ulisp diff_test`）が 100% 合格すること。
- [x] トップレベルの完全分離および直接呼出最適化は Issue #539 へ引き継ぎ完了。

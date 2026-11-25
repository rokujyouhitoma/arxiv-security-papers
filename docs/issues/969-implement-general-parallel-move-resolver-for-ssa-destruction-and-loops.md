---
ID: 969
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 汎用 Parallel Move Resolver（並列コピー解析・トポロジカルシャッフル）の実装と SSA 解除・継続化ループ更新の統合 (ID: 969)

## 1. 概要 / Summary

現在の `125_lir_continuation.scm` における 2 引数限定の手動シャッフル分岐を廃止し、任意 $N$ 変数の同時代入を有向依存グラフ＋トポロジカルソート＋1 スクラッチレジスタによるサイクル切断で最小命令列へ変換する汎用 Parallel Move Resolver を実装する。
Braun SSA の φ（ブロック引数）解除と継続化ループ変数更新の双方で共通利用する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [Issue #827](closed/827-generalize-pass-132-braun-ssa-for-arbitrary-cfg-and-goto.md)
  - [Issue #966](966-separate-mir-ssa-and-machine-lir-for-unified-middle-end.md)
  - [BASELINE.md](../../ulisp/benchmarks/BASELINE.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [125_lir_continuation.scm](../../ulisp/lir/125_lir_continuation.scm)
- [ ] [132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm)
- [ ] [lir_verifier.scm](../../ulisp/lir/lir_verifier.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/969-general-parallel-move-resolver`

1. `(dst <- src)` 集合から有向依存グラフを構築し、DAG 部分はトポロジカル逆順で直接転送、閉路部分はスクラッチレジスタ（または一時スロット）1 個でサイクルを切断するアルゴリズムを実装する。
2. `125_lir_continuation.scm` の 2 引数専用分岐および `132_lir_braun_ssa.scm` のブロック引数エッジコピー解決を本リゾルバへ統合する。
3. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 任意個数（$N \ge 1$）の循環・連鎖・自己代入を含む並列コピーが正しさ検証付きで最小命令列に展開されること
- [ ] 既存の継続化ループ・Braun SSA・LIR 検証テストが全 PASS すること
- [ ] `make format` / `make static_analysis` / `make test` および `verify-quality-gates` が全 PASS すること

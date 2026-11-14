---
ID: 827
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] Pass 132 Braun SSA の任意 CFG (基本ブロック・多方向分岐・goto) 汎用対応化 (ID: 827)

## 1. 概要 / Summary
Pass 132（`ulisp/compiler/132_braun_ssa.scm`）で実装されている Braun SSA 構築アルゴリズムを拡張し、構造化された木構造だけでなく、多方向ジャンプ（`switch`）や任意ジャンプ（`goto`）、後方参照エッジを含む任意の制御フローグラフ（CFG）に対して堅牢に適用可能にする。
これにより、Scheme における例外処理（`dynamic-wind`, `guard`）やエスケープ継続（`call/cc`）が生成する複雑な CFG の最適化を強靭化するとともに、C 言語由来の素朴なスタック変数（`alloca` 相当）をレジスタへ昇格させる mem2reg 最適化（D1）の基盤を完成させる。

---

## 2. トレーサビリティ / Traceability
- **DSN-38**: §2 (D1: mem2reg, C1: 式と文の lowering, C5: switch と goto)
- **関連 Issue**: #816 (Rtyper Escape Pruning), #826 (Typed LIR)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/132_braun_ssa.scm](../../ulisp/compiler/132_braun_ssa.scm): 任意 CFG 向け Phi ノード配置および未解決ブロック解決
- [ ] [ulisp/compiler/cfg.scm](../../ulisp/compiler/cfg.scm): 基本ブロック（Basic Block）の先行節・後続節グラフ抽象
- [ ] [ulisp/tests/test_braun_ssa_arbitrary_cfg.scm](../../ulisp/tests/test_braun_ssa_arbitrary_cfg.scm): goto/switch 構造を含む CFG の SSA 検証テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/827-braun-ssa-arbitrary-cfg`

1. CFG 表現の一般化：
   - 基本ブロックを `block-id`, `instructions`, `predecessors`, `successors` からなるグラフ構造として明示化。
2. Braun アルゴリズムの不完全ブロック（Incomplete Block）処理の完全化：
   - 後から追加される先行節（ループのバックエッジや前方 goto）に対して、未完了ブロックの Phi ノードを追跡・更新する `seal-block` プロトコルの実装。
   - 冗長な自明 Phi（Trivial Phi）の再帰的除去および定数伝播の統合。
3. 支配木（Dominator Tree）および支配辺境（Dominance Frontier）の妥当性検証器の追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 複雑な相互再帰ループ、前方・後方 goto、および多分岐 switch を模した CFG から正しい SSA 形式（単一代入・適切な Phi 配置）が生成されること。
- [ ] 生成された SSA コードが LIR SSA verifier を 100% 通過すること。
- [ ] スタック退避されたローカル変数が、アドレス取得されていない限り完全に SSA 仮想レジスタへ昇格されること。

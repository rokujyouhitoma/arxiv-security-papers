---
ID: 524
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] フロー依存型推論 (Flow-Sensitive Narrowing) と合流点メッセージ分割 (Path Splitting) の実装 (ID: 524)

## 1. 概要 / Summary
コーネル大学 CS 6120 (Lesson 4 単調データフロー解析 & Lesson 11 SELF言語最適化) の理論に基づき、ULisp の型推論基盤（S-Annotator）とコード具象化基盤（S-RTyper）を高度化する。
条件分岐のエッジごとに型情報を絞り込む「フロー依存型推論（Flow-Sensitive Type Narrowing）」を実装し、`(if (fixnum? x) ...)` の成立パスにおいて静的型を確定させる。さらに、複数パスが合流するブロックで型情報が抽象上限（$\top$）へ劣化するのを防ぐため、SELF コンパイラの手法である「メッセージ分割 / パス分割（Path Splitting）」を導入し、合流後の動的型ディスパッチ命令を先行する具象型パス末尾へ複製・引き上げてネイティブ演算化する。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第8.3節 フロー依存型推論 & メッセージ分割)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連先行 Issue**:
  - Issue #517: ULisp コンパイラへの抽象解釈型推論器 (S-Annotator) と型格子 (Lattice) の実装
  - Issue #518: ULisp 低水準IR具象化器 (S-RTyper) とアンボクシングによるタグ検査完全消去
  - Issue #520: 静的型知識に基づく JIT ガード命令事前消去 (Guard Elimination) と OSR 復元コード合成の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/04b_annotator.scm](../../ulisp/passes/04b_annotator.scm) (エッジ特化型伝達関数およびフロー依存 Narrowing の実装)
- [ ] [ulisp/passes/05b_rtyper.scm](../../ulisp/passes/05b_rtyper.scm) (分岐パス特化アンボックス化の連携)
- [ ] [ulisp/passes/06_lir.scm](../../ulisp/passes/06_lir.scm) (パス分割ノードの複製と合流点バイパス)
- [ ] [ulisp/tests/passes/test_annotator.scm](../../ulisp/tests/passes/test_annotator.scm) (フロー依存型推論テストの拡充)
- [ ] [ulisp/tests/passes/test_rtyper.scm](../../ulisp/tests/passes/test_rtyper.scm) (メッセージ分割アンボックス単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/524-ulisp-flow-sensitive-narrowing-and-path-splitting`

1. **CFG 出線エッジでの型絞り込み（Narrowing）伝達関数の実装**:
   - `(if (<predicate> x) <then> <else>)` の条件ノードに対し、`<then>` 枝へ流入する環境では $x$ の型を述語に応じた具体型（例: `SomeFixnum`, `SomePair`）と交差（Meet: $\sqcap$）させ、`<else>` 枝では否定型を伝播。
2. **合流点におけるメッセージ分割（Path Splitting）**:
   - 合流ブロック $B_{join}$ の先頭に動的型検査やディスパッチ命令が存在する場合、各先行ブロック $B_1, B_2$ において型が確定していれば、対象命令群を $B_1$（Fixnum 専用パス）および $B_2$（Flonum 専用パス）へ複製して引き上げ。
3. **S-RTyper 具象化パスとの直結**:
   - 分割されたパスにおいてタグ検査およびボクシング／アンボックス命令を完全消去し、直接 CPU のネイティブ算術命令（`add`, `sub` 等）へ展開。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 条件分岐内において、先行の型述語判定に続く算術演算のタグ検査命令が 100% 除去されること。
- [ ] 合流点における不要な多相的ディスパッチがパス分割によって排除され、実行時分岐が削減されること。
- [ ] 全ユニットテストスイートおよびセルフホスティング固定点検証（`diff stage2.s stage3.s == 0`）が合格すること。

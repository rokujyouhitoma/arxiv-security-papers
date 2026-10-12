---
ID: 522
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] ドミネータ解析に基づくコンティフィケーション (Contification) と局所クロージャ割当完全消去の実装 (ID: 522)

## 1. 概要 / Summary
コーネル大学 CS 6120 (Lesson 5 & SSA) で扱われるドミネータ解析理論を応用し、Scheme の局所手続きをインライン制御フローへと還元する「コンティフィケーション（Contification）」パスを ULisp に実装する。
`letrec` や局所 `lambda` で定義された手続きのうち、すべての呼び出し箇所（Call sites）が共通の基本ブロックによって支配（Dominate）されているものを特定し、独立した関数フレームおよびフラットクロージャオブジェクトのヒープ生成を完全に消去する。呼び出しは同一関数内のローカルジャンプ（`jmp`）へと変換され、ヒープアロケーション・GC プレッシャーおよび間接呼び出しオーバーヘッドをゼロ化する。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第8.4節 Contification)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連先行 Issue**:
  - Issue #491: ULisp Phase 5: 手続き呼び出し・末尾呼び出し最適化 (TCO)・第一級関数とフラットクロージャの実装
  - Issue #498: ULisp コンパイラへの明示的クロージャ変換 (Closure Conversion) Nanopass の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/04c_contify.scm](../../ulisp/passes/04c_contify.scm) (新規作成: コンティフィケーション最適化パス)
- [ ] [ulisp/passes/02_analysis.scm](../../ulisp/passes/02_analysis.scm) (局所呼び出し箇所およびコールグラフ追跡の拡充)
- [ ] [ulisp/passes/05_closure_convert.scm](../../ulisp/passes/05_closure_convert.scm) (コンティファイ済み関数のクロージャ変換バイパス)
- [ ] [ulisp/passes/08_driver.scm](../../ulisp/passes/08_driver.scm) (パイプラインへの Pass 04c 統合)
- [ ] [ulisp/tests/passes/test_contify.scm](../../ulisp/tests/passes/test_contify.scm) (新規作成: コンティフィケーション単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/522-ulisp-contification-and-closure-elimination`

1. **ドミネータ木と共通支配ノードの判定アルゴリズム**:
   - 局所関数の呼び出し箇所集合 $\{ c_1, c_2, \dots, c_k \}$ に対し、それらすべてを支配する最下層の共通支配基本ブロック（Immediate Common Dominator）を算出。
2. **基本ブロック群への還元とローカルジャンプ化**:
   - 共通支配ノードが存在し、かつ関数ポインタが第一級市民として外部エスケープしない場合、対象関数を呼出元関数の CFG 内の基本ブロックラベル群へインライン展開。
   - 呼び出し `(f arg1 ...)` を引数レジスタ/スタック再配置と `jmp label_f` へ置換。
3. **クロージャ変換パス (Pass 05) との連動**:
   - コンティファイされた局所関数に対し、環境ポインタ配列やヒープ割り当て命令（バンプポインタ進捗）の生成を抑止。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 局所ヘルパー関数および `letrec` ループにおいて、フラットクロージャのヒープ割り当て（バンプアロケーション）が 0 件に消去されること。
- [ ] 間接関数呼び出し（`call [rax + offset]`）が直接ローカルジャンプ（`jmp`）に置き換わること。
- [ ] 包括テストスイートおよび 3 段階ブートストラップの決定論的不動点（`diff stage2.s stage3.s == 0`）が 100% 成立すること。

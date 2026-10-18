---
ID: 568
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Pass 131 スタックマップと保守的スタック走査のフォールバック・ハイブリッド化によるポインタ保護強化 (ID: 568)

## 1. 概要 / Summary
現在、uLisp x86 AOT コンパイラは Pass 131 (`passes/131_stackmap.scm`) による Exact GC（正確なスタックマップ）を採用している。しかし、LIR 最適化やレジスタスピル、C バックエンド連携、外部 FFI、あるいは末尾呼び出しの最適化パスによって、スタックマップの追跡範囲外に Scheme ポインタ（Tagged Pointer）が一時退避されるエッジケースが存在すると、GC実行時にポインタが回収・移動から漏れ、ダングリングポインタや SEGV を招くリスクがある。
Exact スタックマップを主軸としつつ、スタック境界（RSP〜RBP〜スタックベース）の全スロットを保守的に検証（Nursery/Heap 範囲アドレスかつ有効タグを持つ値をポインタと見做す）するハイブリッド走査（Hybrid Exact-Conservative Scanning）機構を導入し、ポインタ破壊を堅牢に防止する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: Issue #525 (TBAA・エスケープ解析に基づくスタック割当昇格とナーサリ世代別コピーGCの実装)
- 関連コンポーネント: uLisp スタックマップ生成パス (`passes/131_stackmap.scm`), コピーGCスキャナ (`runtime/gc.s`, `runtime/runtime.c`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/131_stackmap.scm](file:///workspace/arxiv-security-papers/ulisp/passes/131_stackmap.scm)
- [ ] [ulisp/runtime/gc.s](file:///workspace/arxiv-security-papers/ulisp/runtime/gc.s)
- [ ] [ulisp/runtime/runtime.c](file:///workspace/arxiv-security-papers/ulisp/runtime/runtime.c)
- [ ] [ulisp/test.sh](file:///workspace/arxiv-security-papers/ulisp/test.sh)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/568-implement-hybrid-exact-and-conservative-stack-scanning`

1. **Exact GC スタックマップの一次走査**:
   - リターンアドレスに対応するテーブルから正確なスタックレイアウトを読み出し、オブジェクトを Forwarding（退避）してポインタを書き換え。
2. **保守的フォールバックスキャンの二次走査**:
   - スタックトップ (RSP) からスタックベースまでのフレーム領域を 8 バイト刻みで巡回。
   - 値がナーサリ空間内の有効なアドレス境界であり、かつオブジェクトヘッダが正常なタグを持つ場合、未退避であれば成熟空間へコピーしてポインタを退避。
3. **整合性検証アサーションとデバッグログ**:
   - Exact スタックマップと保守的スキャンで不一致が発生した場合に、警告または詳細ログを出力するデバッグモード（`DEBUG_GC=1`）を導入。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] レジスタスピルやディープスタック再帰、クロージャネスト下でもポインタ破壊やメモリ化けが 100% 発生しないこと。
- [ ] 保守的スタック走査のオーバーヘッドが GC 実行時間の 5% 未満に収まること。
- [ ] `./test.sh` および `./test_c.sh` の全テストが PASS すること。

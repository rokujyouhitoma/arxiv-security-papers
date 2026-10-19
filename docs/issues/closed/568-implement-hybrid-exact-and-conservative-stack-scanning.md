---
ID: 568
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] Pass 131 スタックマップと保守的スタック走査のフォールバック・ハイブリッド化によるポインタ保護強化 (ID: 568)

## 1. 概要 / Summary
現在、uLisp x86 AOT コンパイラは Pass 131 (`passes/131_stackmap.scm` / `passes/131_lir_safepoint.scm`) による Exact GC（正確なスタックマップ）を採用している。しかし、LIR 最適化やレジスタスピル、C バックエンド連携、外部 FFI、あるいは末尾呼び出しの最適化パスによって、スタックマップの追跡範囲外に Scheme ポインタ（Tagged Pointer）が一時退避されるエッジケースが存在すると、GC実行時にポインタが回収・移動から漏れ、ダングリングポインタや SEGV を招くリスクがある。
Exact スタックマップを主軸としつつ、スタック境界（RSP〜RBP〜スタックベース）の全スロットを保守的に検証（Nursery/Heap 範囲アドレスかつ有効タグを持つ値をポインタと見做す）するハイブリッド走査（Hybrid Exact-Conservative Scanning）機構を導入し、ポインタ破壊を堅牢に防止する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: Issue #525 (TBAA・エスケープ解析に基づくスタック割当昇格とナーサリ世代別コピーGCの実装), Issue #566 (Dynamic Heap Growth), Issue #567 (GC Execution Profiles)
- 関連コンポーネント: uLisp スタックマップ生成パス (`passes/131_lir_safepoint.scm`), コピーGCスキャナ (`passes/140_backend_x86_64.scm`, `lib/gc.scm`, `runtime.c`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/gc.scm](../../ulisp/lib/gc.scm)
- [x] [ulisp/passes/140_backend_x86_64.scm](../../ulisp/passes/140_backend_x86_64.scm)
- [x] [ulisp/runtime.c](../../ulisp/runtime.c)
- [x] [ulisp/tests/test_gc_hybrid.scm](../../ulisp/tests/test_gc_hybrid.scm)
- [x] [ulisp/Makefile](../../ulisp/Makefile)
- [x] [ulisp/test.sh](../../ulisp/test.sh)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/568-implement-hybrid-exact-and-conservative-stack-scanning`

1. **Exact GC スタックマップの一次走査 (Pass 1 - Exact Scan)**:
   - スタックマップテーブル `__ulisp_stackmap_table` を参照し、各セーフポイントフレームの追跡ビットマップに従って正確に対象スロットのオブジェクトを退避・ポインタ更新。
2. **保守的フォールバックスキャンの二次走査 (Pass 2 - Conservative Scan)**:
   - スタックトップ (`deepest-sp` / `RSP`) からスタック底 (`bottom` / `stack_base`) までの全スロットを 8 バイト刻みで巡回。
   - スロットの値が有効なポインタタグ (1: Pair, 3: Closure, 5: Vector, 7: String) かつ 8 バイト境界整列アドレスであり、ナーサリ／ヒープ空間内を指している場合:
     - 既に一次走査で Forwarding（退避）済みであれば転送先ポインタ値でスロットを更新。
     - 一次走査で未退避のオブジェクトであれば成熟空間／To-Space へコピーして転送先ポインタを書き込み、スロットを更新。
     - 一次走査で既に更新済み（成熟空間／To-Space を指す）スロットはノーアクションでスキップ。
3. **整合性検証アサーションとデバッグログ (`DEBUG_GC=1`)**:
   - `ulisp_gc_state[15]` にデバッグフラグを配置し、`DEBUG_GC=1` 時に一次走査と二次走査の差分（スタックマップ外のポインタ救出イベント）を検知してログ出力。
4. **テストスイートの整備と品質検証**:
   - `tests/test_gc_hybrid.scm` を新設し、スタックマップ未登録スロットのポインタ救出、ディープ再帰、複合オブジェクトのポインタ整合性を検証。
   - `Makefile` に `test_gc_hybrid` ターゲットを追加し、`test.sh` に統合。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] レジスタスピルやディープスタック再帰、クロージャネスト下でもポインタ破壊やメモリ化けが 100% 発生しないこと。
- [x] 保守的スタック走査のオーバーヘッドが GC 実行時間の 5% 未満に収まること。
- [x] `make test_gc_hybrid` が PASS すること。
- [x] `./test.sh` および `./test_c.sh` の全テストが PASS すること。


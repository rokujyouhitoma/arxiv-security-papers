---
ID: 566
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 成熟空間使用率に応じた動的ヒープ拡張（Growth Policy / mremap）による巨大バッチ・コンパイラOOM防止 (ID: 566)

## 1. 概要 / Summary
現状の uLisp コピーGCは固定長ヒープ（デフォルト64MB〜512MB等）を前提としており、マイナーGCでナーサリから生き残ったオブジェクトが成熟空間（Mature / Old Generation）へ昇格（promotion）し続けると、コンパイラのような巨大バッチ処理で成熟空間が枯渇し、OOM または即時メジャーGCの頻発によるスラッシング（GC pause）を引き起こす。
成熟空間の占有率が閾値（例: 70%）を超えた場合に、Linux `mremap` または追加 `mmap` セグメント割り当てによって成熟空間を動的倍々伸長（Dynamic Heap Expansion）するポリシーを実装し、長大プログラムコンパイルや高負荷時のOOMを恒久防止する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: Issue #563 (コンパイラの大規模AST変換時における12GBヒープ枯渇とOOMセーフガード欠如によるSEGVクラッシュの解消)
- 関連コンポーネント: uLisp コピーGCランタイム (`runtime/gc.s`), Portable C バックエンドランタイム (`runtime/runtime.c`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/gc.s](file:///workspace/arxiv-security-papers/ulisp/runtime/gc.s)
- [ ] [ulisp/runtime/runtime.c](file:///workspace/arxiv-security-papers/ulisp/runtime/runtime.c)
- [ ] [ulisp/compiler/primitives.scm](file:///workspace/arxiv-security-papers/ulisp/compiler/primitives.scm)
- [ ] [ulisp/test.sh](file:///workspace/arxiv-security-papers/ulisp/test.sh)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/566-implement-dynamic-heap-growth-policy-and-mremap`

1. **動的ヒープ拡張ポリシーの設計**:
   - マイナーGC完了時に成熟空間の残量を検査 (`mature_free` と `mature_limit`)。
   - 残量が 30% 未満（使用率 70% 超）の場合、または昇格オブジェクトサイズが空き容量を上回る場合に、ヒープ拡張トリガーを引く。
2. **`mremap` システムコールによる仮想メモリ伸長 (x86_64)**:
   - Linux の `mremap(old_address, old_size, new_size, MREMAP_MAYMOVE)` を利用し、成熟空間を倍々（例: 64MB → 128MB → 256MB → 512MB ... 最大物理RAM考慮上限）で拡張。
   - アドレス移動が発生した場合のベースポインタ更新および境界ポインタ更新をアトミックに適用。
3. **Portable C バックエンド側の追随**:
   - `runtime/runtime.c` においても、GC後の成熟領域チェックを行い、`realloc` または `mremap` による自動伸長をサポート。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 成熟空間が初期上限に達してもクラッシュせず、自動拡張されて巨大なAST/データ構造のコンパイルが正常完遂すること。
- [ ] メモリ枯渇時（OSの仮想メモリ限界）に安全なエラーメッセージを出力して制御された終了ができること。
- [ ] `./test.sh` および `./test_c.sh` でリグレッションがないこと。

---
ID: 566
種別: Feature
優先度: Medium
ステータス: Closed (Resolved)
---

# [FEAT/ENH] 成熟空間使用率に応じた動的ヒープ拡張（Growth Policy / mremap）による巨大バッチ・コンパイラOOM防止 (ID: 566)

## 1. 概要 / Summary
現状の uLisp コピーGCは固定長ヒープ（デフォルト64MB〜512MB等）を前提としており、マイナーGCでナーサリから生き残ったオブジェクトが成熟空間（Mature / Old Generation）へ昇格（promotion）し続けると、コンパイラのような巨大バッチ処理で成熟空間が枯渇し、OOM または即時メジャーGCの頻発によるスラッシング（GC pause）を引き起こす。
成熟空間の占有率が閾値（70%）を超えた場合、または昇格要求サイズが残量を超える場合に、Linux `mremap` システムコール (syscall 25) によるインプレースVMA伸長（Pre-reserved contiguous VMA + in-place mremap）によって成熟空間を動的倍々伸長（Dynamic Heap Expansion）するポリシーを実装し、長大プログラムコンパイルや高負荷時のOOMを恒久防止した。

---

## 2. トレーサビリティ / Traceability
- 関連資料: Issue #563 (コンパイラの大規模AST変換時における12GBヒープ枯渇とOOMセーフガード欠如によるSEGVクラッシュの解消)
- 関連コンポーネント: uLisp コピーGCランタイム (`ulisp/lib/gc.scm`, `ulisp/passes/140_backend_x86_64.scm`), POSIX システムコール (`ulisp/lib/posix.scm`), Portable C バックエンドランタイム (`ulisp/runtime.c`), テストスイート (`ulisp/tests/test_gc_growth.scm`, `ulisp/test.sh`, `ulisp/test_c.sh`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/posix.scm](../../ulisp/lib/posix.scm) - `sys-mremap` (Linux syscall 25) 定義
- [x] [ulisp/lib/gc.scm](../../ulisp/lib/gc.scm) - 成熟空間の動的拡張ポリシー (`gc-grow-mature!`, `gc-check-mature-growth!`, `gc-ensure-mature-capacity!`)
- [x] [ulisp/passes/140_backend_x86_64.scm](../../ulisp/passes/140_backend_x86_64.scm) - ネイティブx86_64 GCマイナーフィニッシュにおける70%使用率検査 & `sys_mremap` 拡張
- [x] [ulisp/runtime.c](../../ulisp/runtime.c) - Portable C バックエンドにおける動的成熟ヒープ拡張 (`ulisp_gc_grow_mature`, `ulisp_oom_exit`)
- [x] [ulisp/tests/test_gc_growth.scm](../../ulisp/tests/test_gc_growth.scm) - 成熟空間動的拡張テストスイート (全11テスト)
- [x] [ulisp/Makefile](../../ulisp/Makefile) - `test_gc_growth` ターゲット追加
- [x] [ulisp/test.sh](../../ulisp/test.sh) - Step 26b として `test_gc_growth` を統合

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/566-implement-dynamic-heap-growth-policy-and-mremap`

1. **動的ヒープ拡張ポリシーの設計**:
   - マイナーGC完了時およびオブジェクト昇格時に成熟空間の残量を検査。
   - 残量が 30% 未満（使用率 70% 超）の場合、または昇格オブジェクトサイズが空き容量を上回る場合に、ヒープ拡張トリガーを発火。
2. **`mremap` システムコールによる仮想メモリ伸長 (x86_64)**:
   - Linux `mremap(old_address, old_size, new_size, flags=0)` を利用し、成熟空間を倍々（64KB → 128KB → 256KB ... 最大1GB）でインプレース拡張。
   - ページアライメント保証とVMA予約を活用して安全な無移動拡張を担保。
3. **Portable C バックエンド側の追随**:
   - `ulisp/runtime.c` において `ulisp_gc_grow_mature()` を追加し、`realloc` による成熟領域自動伸長をサポート。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 成熟空間が初期上限に達してもクラッシュせず、自動拡張されて巨大なAST/データ構造のコンパイルが正常完遂すること。
- [x] メモリ枯渇時（OSの仮想メモリ限界）に安全なエラーメッセージを出力して制御された終了ができること。
- [x] `./test.sh` および `./test_c.sh` でリグレッションがないこと。

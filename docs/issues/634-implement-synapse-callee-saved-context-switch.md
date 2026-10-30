---
ID: 634
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] System V AMD64 Callee-saved 極小スタック・ネイティブコンテキストスイッチの実装 (ID: 634)

## 1. 概要 / Summary
[DSN-37] Phase 2 Task 2.1 に基づき、x86-64 System V ABI に準拠した超軽量（10〜15 命令）コンテキストスイッチルーチンを低レベルアセンブラで実装する。
各タスクが独自の極小スタック（4KB〜16KB）を保持し、Callee-saved レジスタの交換のみで高速にタスク実行を切り替える基盤を確立する。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-37: Synapse 二層分離型並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#144-phase-2-mn-スケジューラ--強プリエンプション) (第 5 章 メモリモデル、第 7.3 節 極小スタック、第 14.4 節 Task 2.1)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/runtime/synapse/context.s` (新規: x86-64 アセンブラコンテキストスイッチ)
- [ ] `ulisp/runtime/synapse/context.scm` (新規: Scheme インターフェース)
- [ ] `tests/synapse/test_context_switch.scm` (新規: コンテキストスイッチ単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/634-synapse-native-context-switch`

1. **アセンブラ関数 `synapse_swap_context`**:
   - 引数 1 (`rdi`): 旧スタックポインタ格納先アドレス (`old_sp_ptr`)
   - 引数 2 (`rsi`): 新スタックポインタ (`new_sp`)
   - 処理:
     - Callee-saved レジスタ（`rbp`, `rbx`, `r12`, `r13`, `r14`, `r15`）を旧スタックに `push`。
     - `mov [rdi], rsp` で現在のスタックポインタを保存。
     - `mov rsp, rsi` で新しいスタックポインタに切り替え。
     - 新スタックから `pop r15 ... rbp` で復元。
     - `ret` 命令で新タスクの再開アドレスへジャンプ。
2. **スタック初期化ヘルパー**:
   - `(setup-task-stack stack-base stack-size entry-fn)` により初期スタックフレームを構築。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 2 つのタスク間でコンテキストスイッチを往復させ、全レジスタ値が改変されないこと
- [ ] スタックアライメント（16 バイト境界）が ABI 規約通りに維持されること
- [ ] 1000 万回のスイッチでスタック破壊やセグメンテーションフォールトが 0 件


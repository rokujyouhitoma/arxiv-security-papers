---
ID: 808
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] safepoint 有効化状態でのプリエンプション実機統合テストの追加と Makefile 除外設定の整理 (ID: 808)

## 1. 概要 / Summary

Issue #796 により `pass-synapse-inject-safepoints` が本番パイプライン (`FRONTEND_PASSES`) に既定で組み込まれた。しかし、`ulisp/Makefile` の33箇所で依然として `(!disable-pass pass-synapse-inject-safepoints)` が指定されており、並行処理テスト全般、stdlib、`lib/posix.scm` 等でsafepoint注入が無効化されている。
さらに、既存のパステスト (`test_pass_inject_safepoints`) はAST変換後の構文形状を検査するのみであり、手動pollを含まない通常のループが、link先タスクからの `kill` によって実際にプリエンプト停止することを検証する動的実機テストが1件も存在しない。
本Issueでは、手書きpollに依存しない純粋なループに対する実機プリエンプション統合テストを追加し、Makefile上の過剰な除外設定を段階的に解除・整理する。

---

## 2. トレーサビリティ / Traceability

- 関連Issue:
  - #796 (セーフポイント注入パスの本番パイプライン統合)
  - #799 (クロスワーカー環境テスト拡充およびLinux実機CI検証)
  - #807 (x86-64バックエンドにおけるセーフポイントポーリングstub重複定義解消)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/Makefile](../../ulisp/Makefile)
- [ ] [tests/test_preemption.scm](../../tests/test_preemption.scm)
- [ ] [tests/test_pass_inject_safepoints.scm](../../tests/test_pass_inject_safepoints.scm)
- [ ] [runtime/preempt.scm](../../runtime/preempt.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/808-add-hardware-safepoint-preemption-tests`

1. **実機動的プリエンプションテストケースの追加**:
   - `tests/test_preemption.scm` に新規テストグループを追加。
   - 手書き `poll` を一切含まない自己再帰／ループ関数を定義し、別タスクからリンクして `kill` 発行時に確実に停止することを検証。
2. **Makefile の `disable-pass` 整理**:
   - `ulisp/Makefile` で `(!disable-pass pass-synapse-inject-safepoints)` が指定されている33箇所を精査。
   - まず並行性テスト群から除外ディレクティブを解除し、正常動作することを確認。
3. **CI検証体制の整備**:
   - Linux x86-64 環境 (CI / Docker) 上で実機テストをパスさせる。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 自動注入された safepoint poll により、手書き poll のない無限ループタスクが外部 `kill` で正常停止する動的テストがパスすること。
- [ ] `ulisp/Makefile` における `(!disable-pass pass-synapse-inject-safepoints)` の記述が精査・削減されていること。
- [ ] CI（Linux x86-64環境）においてテストがリグレッションなく成功すること。


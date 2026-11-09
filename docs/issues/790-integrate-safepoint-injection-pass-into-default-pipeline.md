---
ID: 790
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG/SEC] R7RS タスク強制終了のためのセーフポイント挿入パス (pass-synapse-inject-safepoints) のコンパイラ統合 (ID: 790)

## 1. 概要 / Summary
通常の R7RS Scheme で記述されたタスクに対し、協調的プリエンプションおよび強制終了（Cancel / Termination）を可能にするセーフポイント挿入パス（`pass-synapse-inject-safepoints`）が、コンパイラの標準パイプラインに組み込まれておらず未接続となっている問題を解消する。

現在、セーフポイント挿入パスはパス単体のテスト時のみ手動で連結されており、通常のコンパイル手順には含まれていない。また、プリエンプションの統合テスト（`test_preemption`）でも、コメントで「コンパイラが挿入」と謳いながら実際にはコード内に手動で `(%synapse-safepoint-poll!)` を埋め込んで検証しているため、通常の Scheme ループを実行するタスクが外部からの停止シグナルによって停止できない状態となっている。

### 再現手順 / Steps to Reproduce
1. 通常の R7RS Scheme で無限ループまたは長時間再帰を行うタスクを記述してコンパイルする。
2. 生成されたコードの AST または逆アセンブル結果を確認する。
3. セーフポイント（`%synapse-safepoint-poll!`）が挿入されておらず、タスク強制終了シグナルを発行してもループがブロックし続けて停止しない。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / ULisp Nanopass Compiler
- File: `ulisp/compiler/pass_manager.scm`, `ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [pass_manager.scm](../../ulisp/compiler/pass_manager.scm)
- [ ] [pass_inject_safepoints.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm)
- [ ] [test_preemption_input.scm](../../ulisp/build/test_preemption_input.scm)
- [ ] [test_pass_inject_safepoints_runner.scm](../../ulisp/build/test_pass_inject_safepoints_runner.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `ulisp/compiler/pass_manager.scm` の `init-default-pass-registry!` 内で標準登録されているパス群に `pass-synapse-inject-safepoints` が含まれていない。
- `pass_inject_safepoints.scm` に `inject-synapse-safepoints-pass!` 関数は存在するが、オプトイン（明示的注入呼び出し）が必要であり、通常のプログラムビルドでは実行されない。
- 統合テスト側も手動ポーリング呼び出しでパスしていたため、パイプライン非接続が発見されずに見落とされていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: ユーザーコード側でループバックエッジごとに手動で `(%synapse-safepoint-poll!)` を呼び出す。
* **恒久対策 (Permanent Fix)**:
  - コンパイラの標準パイプライン（`init-default-pass-registry!`、または並行処理オプション有効時のパイプライン編成）に `pass-synapse-inject-safepoints` を正式に組み込む。
  - バックエンド生成前のループバックエッジ（`named-let`、再帰関数）および関数プロローグへ確実にセーフポイントが自動挿入されるようにする。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/790-integrate-safepoint-pass-to-pipeline`

1. `pass_manager.scm` またはコンパイルドライバに `pass-synapse-inject-safepoints` をデフォルトの Frontend/Core パスとして登録。
2. 通常の R7RS 手続き（`let loop` による再帰）をコンパイルし、出力コードに `(%synapse-safepoint-poll!)` が自動注入されていることを検証するコンパイラテストを追加。
3. `test_preemption_input.scm` から手動の `(%synapse-safepoint-poll!)` 呼び出しを削除し、純粋な R7RS ループがピアの終了シグナルによって自動で強制終了されることを実証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] 手動のポーリング呼び出しを行わない純粋な Scheme ループコードに対して、コンパイラによってセーフポイントが自動挿入されること。
- [ ] ループ実行中のタスクに対し、他タスクの終了やタイムアウトによる強制停止シグナルが正常にハンドリングされ終了できること。
- [ ] 既存の全 Nanopass コンパイラテストおよびセーフポイントテストが 100% PASS すること。


---
ID: 796
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG/COMPILER] セーフポイント注入パス (pass-inject-safepoints) の本番コンパイラ PASSES パイプライン正式統合 (ID: 796)

## 1. 概要 / Summary
Issue #790 にてタスク強制終了（kill / cancel）のためのセーフポイント挿入パス（`pass_inject_safepoints.scm`）が実装されたが、本番のコンパイラ（`ulisp/compiler.scm` のパス結合リスト `PASSES`）に登録されておらず、本番コンパイルパイプラインから一度も呼び出されていない。
このため、通常の R7RS で記述されたユーザーコードおよびタスクはセーフポイント（`synapse-safepoint-poll!`）が注入されず、強制終了シグナルを受信してもタスクが停止しない（DSN-37 要件「単一タスクの孤立停止」が本番未達）。現在のテストは変換後の S 式を手書きして poll を呼び出している状態にとどまっている。
本 Issue では、セーフポイント挿入パスを本番の `PASSES` に正式結合し、コンパイル後のアセンブリ出力に poll 呼び出しが含まれることを自動検証する。同時に、ランタイム内部のホットループや短いアクセサに過剰注入されて性能低下を引き起こさない除外制御・インライン境界判定を導入する。

### 再現手順 / Steps to Reproduce
1. 通常の R7RS 構文で無限ループを行うタスクを記述し、通常コンパイラでビルドする。
2. スケジューラ上で当該タスクを実行し、外部から `task-exit!` または kill シグナルを送信する。
3. セーフポイントが挿入されていないため、タスクがシグナルを検知できず停止しない現象を確認する。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / macOS arm64
- File: [compiler.scm](../../ulisp/compiler.scm)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm) - `PASSES` 定義リストへのセーフポイント挿入パス追加
- [ ] [ulisp/build/test_pass_inject_safepoints_runner.scm](../../ulisp/build/test_pass_inject_safepoints_runner.scm) - テストランナー
- [ ] [tests/concurrency/test_pass_inject_safepoints.scm](../../tests/concurrency/test_pass_inject_safepoints.scm) - コンパイル済みバイナリ/アセンブリの poll 存在検証テスト

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `pass_inject_safepoints.scm` 単体の変換関数は実装されたが、コンパイラドライバのパス実行リスト（`PASSES`）への結合が漏れていた。
- 結合が行われないまま、手動で poll を埋め込んだ単体テストのみが記述されていたため、パイプライン未接続のまま Issue #790 がクローズされてしまっていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**:
  - なし（コンパイラパイプラインへの登録が不可欠）。
* **恒久対策 (Permanent Fix)**:
  - `ulisp/compiler.scm` の中間表現変換フェーズ（HIR/LIR 変換前後）の適切な位置に `pass-inject-safepoints` を登録。
  - ランタイムコア（連想リスト走査、極小アクセサ等）に対する不要な poll 注入を抑止するアノテーション/除外フィルタを実装し、実行時オーバーヘッドを最小化する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/796-integrate-pass-inject-safepoints-into-compiler-passes`

1. `ulisp/compiler.scm` の `PASSES` リストに `pass-inject-safepoints` を追加。
2. コンパイラが生成したアセンブリ / 中間コード中に `synapse-safepoint-poll!` の呼び出し命令が正しく生成されているかを検証するテストを追加。
3. 通常 R7RS のループを含むタスクが `task-exit!` によって速やかに停止することを実機テストで検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `compiler.scm` のデフォルトコンパイルパイプラインを通じてセーフポイントが自動注入されること。
- [ ] 生成コードに `synapse-safepoint-poll!` の呼び出しが存在することがテストで確認されること。
- [ ] 強制終了シグナルにより通常のループタスクが即座に停止すること（DSN-37 充足）。
- [ ] ホットパスへの過剰注入による著しい性能低下が発生しないこと。


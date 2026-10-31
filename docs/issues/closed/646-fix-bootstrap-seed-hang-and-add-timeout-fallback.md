---
ID: 646
種別: Bug
優先度: High
ステータス: Closed (Resolved)
完了日: 2026-10-31
---

# [BUG/SEC] bootstrap.sh におけるシードバイナリ無限ループ停止の解消とタイムアウト・フォールバック機構の強化 (ID: 646)

## 1. 概要 / Summary
`make -C ulisp test` または `make -C ulisp bootstrap` を実行した際、Phase 7 (`bootstrap.sh`) の Stage 1 において、シードバイナリ (`ulisp/bin/ulisp-boot`) が `build/ulisp_core.scm` のコンパイル中にユーザーランドで無限ループ（CPU 99%〜100% 占有、メモリ 6GB 以上へ急激に膨張）に陥り、プロセスが停止（ハング）する不具合が発生していた。

さらに、`bootstrap.sh` 内のシード実行ラッパー `run_stage_try` に実行タイムアウト（`timeout`）が設定されていないため、異常終了（クラッシュ）以外の無限ループ時に Gauche / ILisp への自動フォールバック機構が発火せず、永久にプロセスが待機状態となっていた。

### 再現手順 / Steps to Reproduce
1. リポジトリルートで `make -C ulisp bootstrap` または `make -C ulisp test` を実行する。
2. `[1/3] Stage 1: Fast compiling ulisp_core.scm using native seed (/workspace/arxiv-security-papers/ulisp/bin/ulisp-boot)...` が出力された後、プロセスが返ってこなくなる。
3. `top` / `ps aux` で確認すると、`ulisp-boot` が CPU 98%〜100%、メモリ 5GB〜6GB 超を消費し続ける。

### 再現環境 / Environment
- OS / Env: Linux x86_64
- File: `ulisp/bootstrap.sh`, `ulisp/bin/ulisp-boot`, `ulisp/build/ulisp_core.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) : `run_stage_try` におけるタイムアウトガード (`BOOTSTRAP_STAGE_TIMEOUT:-600s`) と自動フォールバックの強化、タイムスタンプ無駄更新防止
- [x] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm) : ホスト環境（Gauche / ILisp）互換 shim (`file-input-port?`, `port-line`, `port-col`) の追加
- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) : コンパイラ統合定義への互換 shim の反映
- [x] [ulisp/lib/string.scm](../../ulisp/lib/string.scm) : `*symbol-registry*` をハッシュバケット（サイズ 1024）に移行し、O(1) 探索へ改善
- [x] [ulisp/bin/ulisp-boot](../../ulisp/bin/ulisp-boot) : 3-Stage 固定点ブートストラップによって再生成された最新シードバイナリ

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **フォールバック欠落の直接原因**:
   `ulisp/bootstrap.sh` の `run_stage_try()` 関数はコマンド終了コード `$rc -ne 0` のみを検知する仕様となっており、ネイティブシードバイナリが無限ループに陥った場合のタイムアウト制限（例: `timeout 600s` 等）が存在しなかった。
2. **シードバイナリ無限ループの根本原因**:
   `ulisp/lib/string.scm` において、`*symbol-registry*` が単一の線形リスト連想配列（A-list）として実装されていた。Nanopass 50パス・26,000行に達する大規模コンパイラコードをインターンする際、シンボル数千件に対する毎回の全件線形探索が走り、$O(N^2)$ 計算量とGCメモリの際限ないアロケーション（6GB+）が発生して実質的な無限ループとなっていた。
3. **Gauche フォールバック時の未定義関数クラッシュ**:
   シードが失敗して Gauche フォールバックが発火した際、Gauche 標準のポート手続きと ULisp 独自ポート手続きの違いにより、`file-input-port?` が未定義となりクラッシュしていた。

---

## 4. 是正対応内容 / Fix Implementation
1. **タイムアウトガード導入**:
   `ulisp/bootstrap.sh` 内の `run_stage_try` に `timeout "${BOOTSTRAP_STAGE_TIMEOUT:-600s}"` を設定し、無限ループ発生時でも安全にセカンダリコンパイラへフォールバックするよう改修。また、`ulisp_core.scm` の上書きコピーに `cmp -s` チェックを入れ、タイムスタンプ更新による `BOOTSTRAP_FAST=1` キャッシュの無効化を防止。
2. **ホスト互換 Shim の導入**:
   `ulisp/compiler/helpers.scm` および `ulisp/compiler.scm` に `file-input-port?`, `port-line`, `port-col` の互換定義を追加し、Gauche 環境下でのコンパイルを安定化。
3. **シンボルレジストリのハッシュバケット化**:
   `ulisp/lib/string.scm` において、`*symbol-str-buckets*` / `*symbol-sym-buckets*`（サイズ 1024）によるハッシュバケット探索へ全面刷新。プリミティブ `%make-vector` と `vector-set!` ループで初期化し、ライブラリ未ロード環境でも独立して動作するよう堅牢化。
4. **テスト・固定点ブートストラップ検証**:
   - `make -C ulisp lint_sexpr`: 88 ファイル全 S 式括弧バランス PASS。
   - `make -C ulisp test_passes`: 全 38 パス、145 単体テスト 100% PASS。
   - `make -C ulisp bootstrap`: 3-Stage 固定点収束（0 bytes diff: bit-for-bit identical）を達成。
   - `make -C ulisp test`: 全テストスイート完走 PASS。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/bootstrap.sh` において、シードバイナリがハングした場合でもタイムアウト（600秒）により自動フォールバックが正常に動作すること。
- [x] Gauche フォールバック時の `file-input-port?` 未定義エラーを解消し、ブートストラップが完走すること。
- [x] `ulisp/lib/string.scm` のシンボルレジストリ（`*symbol-str-buckets*` / `*symbol-sym-buckets*`）をハッシュバケット化し、O(N²) 線形探索ボトルネックを解消すること。
- [x] `make -C ulisp bootstrap` が Stage 1〜3 を経て固定点到達（0 bytes diff: bit-for-bit identical）を達成すること。
- [x] 変更内容がリポジトリの品質ゲートを満たすこと。


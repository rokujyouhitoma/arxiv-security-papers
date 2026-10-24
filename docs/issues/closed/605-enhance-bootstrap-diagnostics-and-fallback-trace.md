---
ID: 605
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] bootstrap.sh におけるコンパイル失敗時の自動診断・詳細スタックトレース採取（Gauche/ILispフォールバック）機能の導入 (ID: 605)

## 1. 概要 / Summary
現在、`ulisp/bootstrap.sh` において Stage 1 〜 Stage 4 のコンパイルが失敗した場合、単に終了コードと不完全なアセンブリ出力（または断片的な Scheme ランタイムエラー）を出力して即座に終了する。
特に AOT ネイティブバイナリ（`ulisp-boot`, `scheme-stage1`, `scheme-stage2` 等）がセグメンテーション違反（exit code 139）や未捕捉例外でクラッシュした場合、エラーメッセージの断片しか得られず、開発者は手動で Gauche や Python ILisp を起動して同一入力を再実行し、問題の発生したパスや式を特定する必要があった。

本 Issue では、`bootstrap.sh` の障害ハンドリング機構を大幅に強化し、コンパイル失敗または不正出力を検知した際に**自動的に詳細診断（Diagnostic Advisory）をトリガーする機構**を導入した。
Issue #604 で導入されたコンパイラコールスタック追跡（`format-call-stack-traceback` / `--debug`）およびセカンドオピニオン実行エンジン（Gauche または ILisp）と連携し、障害発生時に即座に完全なスタックトレース・AST文脈・推奨対処手順を出力することで、ブートストラップ障害時の平均修復時間（MTTR）を極小化した。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ULisp ブートストラップ検証プロトコル](../../ulisp/docs/spec_pipeline.md)
- **関連 Issue**:
  - [Issue #541: ブートストラップシード導入による高速ビルドパイプラインの構築](541-implement-fast-bootstrap-seed-and-subsecond-build-pipeline.md)
  - [Issue #579: 3-Stage Bootstrap の固定点自動検証プロトコルの確立](579-establish-3-stage-bootstrap-fixed-point-verification-protocol.md)
  - [Issue #604: コンパイラ例外発生時のコールスタック・トレースバック機能の実装](604-implement-call-stack-traceback-for-compiler-exceptions.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (`diagnose_stage_failure` の追加、`compile_asm` の安全アセンブル統合、`run_stage` / `check_asm_output` における診断フック統合)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`bootstrap_diagnose` および `test_bootstrap_diagnostics` ターゲットの追加)
- [x] [ulisp/tests/test_bootstrap_diagnostics.sh](../../ulisp/tests/test_bootstrap_diagnostics.sh) (自動診断機能の検証用エンドツーエンドテスト)
- [x] [docs/issues/README.md](../README.md) (台帳更新)

---

## 4. セキュリティ・堅牢性設計 / Security & Threat Modeling
- **コマンドインジェクション防止**:
  - `bootstrap.sh` 内でステージ名やファイルパス、フォールバックコマンドを展開する際、すべての変数展開をダブルクォート（`"$@"`、`"$stage_name"` 等）で保護し、悪意ある文字列や空白混入によるシェルインジェクションを完全に防止。
- **診断再帰（無限ループ）の防止**:
  - フォールバック診断実行（Gauche / ILisp）自体がクラッシュした場合に、再度診断ルーチンが呼ばれることを防ぐガード変数（`_DIAGNOSING=1`）を設け、最大1回の診断実行で確実に終了コードを保持して exit。
- **実行タイムアウトの保護**:
  - フォールバックトレース実行が無限ループに陥らないよう、`timeout 30s` によるタイムアウト枠を設定。
- **情報漏洩・セキュアな一時ファイル**:
  - 診断用の一時生成ファイルは安全な `$BUILD_DIR` 配下（`build/diag_*`）に限定し、ホストの機密環境変数をトレース出力に混入させない。

---

## 5. 実装内容 / Implementation Details
Target Branch: `feat/605-enhance-bootstrap-diagnostics-and-fallback-trace`

### 5.1 自動診断制御フロー (`diagnose_stage_failure`)
1. **トリガー条件**:
   - `run_stage` での非ゼロ終了コード（exit code ≠ 0）。
   - `check_asm_output` での出力アセンブリ不正（空ファイル、または `*** ERROR:` 検出）。
   - `compile_asm` での gcc アセンブル/リンク失敗。
2. **制御フラグ**:
   - 環境変数 `BOOTSTRAP_DIAGNOSE`（デフォルト `1`: 有効、`0` で無効化）。
3. **診断レポート出力構成**:
   - **ヘッダ表示**: 失敗ステージ名、終了コード、対象ファイルサイズ、障害分類（SIGSEGV, Runtime Exception, Empty ASM, Syntax Error）。
   - **直前出力の抜粋**: 出力ファイル内のエラーメッセージ（`*** ERROR:` 等）のハイライト表示。
   - **セカンドオピニオン・トレースバック採取**:
     - Gauche (`$GOSH_BIN`) または ILisp (`$PYTHON_BIN -m ilisp`) により `(!debug #t)` を付与して再実行。
     - Issue #604 のコンパイラコールスタック追跡（`format-call-stack-traceback`）とランタイム例外スタックを同時採取。
   - **推奨再現コマンド**: 手元で直接デバッグ可能な 1 ライナーコマンドの提示。

### 5.2 `ulisp/Makefile` への診断ターゲット追加
- `make bootstrap_diagnose`: `BOOTSTRAP_DIAGNOSE=1 ./bootstrap.sh` を明示的に実行するターゲット。
- `make test_bootstrap_diagnostics`: 診断バナー生成、エラー分類、抑制フラグ、再帰防止を検証。

### 5.3 自動テストスクリプト (`ulisp/tests/test_bootstrap_diagnostics.sh`)
- 7 項目の包括的テストスイートにより、診断レポート出力、SIGSEGV 分類、実行時エラー抽出、フラグ抑制、再帰防止、セカンドオピニオン実行を検証し、全テスト 100% PASS を達成。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `run_stage` および `check_asm_output` の失敗時に `diagnose_stage_failure` が自動発火すること。
- [x] 終了コード 139（SIGSEGV）や `*** ERROR:` 発生時に、障害分類と視認性の高いハイライトバナーが出力されること。
- [x] 利用可能な環境（Gauche または ILisp）において、セカンドオピニオンによるバックトレースが採取・表示されること。
- [x] 環境変数 `BOOTSTRAP_DIAGNOSE=0` で診断機能がオーバーヘッドなしでバイパスできること。
- [x] 正常系ブートストラップ（`bash ulisp/bootstrap.sh` および `make bootstrap`）が 100% PASS し、一切の悪影響を与えないこと。
- [x] `ulisp/tests/test_bootstrap_diagnostics.sh` が PASS すること（7/7 PASS）。
- [x] 品質ゲート（`make py_compile` / `make static_analysis` / `make test_passes` / `make test_nanopass`）がオールグリーンであること。

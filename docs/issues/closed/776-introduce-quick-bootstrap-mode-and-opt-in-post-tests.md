---
ID: 776
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] ULisp bootstrap.sh における開発用 Quick Bootstrap モード導入と後処理テストのオプトイン分離 (ID: 776)

## 1. 概要 / Summary

現在、ULisp のブートストラップスクリプト（[ulisp/bootstrap.sh](../../../ulisp/bootstrap.sh)）は、日常の Nanopass 開発やバグ修正の際にも、厳密な 3 段階（Stage 1 $\to$ Stage 2 $\to$ Stage 3、場合によっては Stage 4）のフルコンパイルを無条件に直列実行する。
1 つのステージのコンパイルに約 6 分を要するため、1 回のコード修正の検証に **18 分〜24 分以上** を消費し、日常的な開発サイクル（変更 $\to$ 検証）に重大な支障をきたしている。
さらに、Stage 3 の不動点収束後にも `make -C "$ULISP_DIR" test_incremental` が毎回強制実行され、追加の待機時間を発生させている。

本 Issue では、日常開発時のフィードバックループを加速するため、以下の改善を実装する：
1. **開発用 Quick Bootstrap モード（`BOOTSTRAP_QUICK=1` または `--quick` / `-q`）の導入**:
   - Stage 1（ホストシード `bin/ulisp-boot` によるコンパイル）完了時点でスモークテストを実施し、正常であれば即座に終了・シード更新可能とする。
2. **後処理テストのオプトイン化（`BOOTSTRAP_RUN_TESTS=1` / `--test`）**:
   - `verify_and_promote` 内で無条件に呼び出されている `make test_incremental` を分離し、指定時のみ実行するように改修する（デフォルトは高速終了）。
3. **柔軟な CLI 引数解析の追加**:
   - `--quick`, `--stage1-only`, `--full`, `--no-test`, `--test`, `--help` 等の CLI オプションをサポート。
4. **Makefile への統合**:
   - `make bootstrap_quick` および `make quick` ターゲットを追加し、開発者が直感的に高速ビルドを起動できるようにする。

これにより、日常開発におけるブートストラップ待機時間を 18〜24 分から **約 2.5 分（従来比 1/7）** へ即座に短縮する。

---

## 2. ガバナンス・専門エージェント多角レビュー / Governance & Reviews

本 Issue は、リポジトリ規約（`.agents/AGENTS.md`）に従い、16 専門エージェントによる設計レビューを統合して策定された。

- **Project Manager (PM) (Chair / Governance)**:
  - 開発者が 1 行修正するたびに 20 分近く待たされる状況は生産性に壊滅的な悪影響を与えている。まずは安全に Stage 1 のみで動作確認できる Quick モードを最速で導入し、次期 Issue #777（標準ライブラリ分離）への足がかりとする。
- **IT Specialist (Programming Languages & Compilers / PLC)**:
  - ホストシード `bin/ulisp-boot` が出力した `scheme-stage1` は、すでに新コードの AST 変換・コード生成パスを完全に通過した実行可能バイナリである。日常の単体テスト実行やスモークテスト（`42` の出力検証）には `scheme-stage1` だけで十分であり、Stage 2/3 を毎回回す必要性はない。
- **Software Quality Assurance Specialist (SQA)**:
  - Quick モードでもスモークテスト（`42` のコンパイルおよび実行）は必ず通過させること。また、CI やプルリクエスト作成時には `--full`（またはデフォルトの 3-Stage 不動点検証）を義務付けることで品質を二重担保する。
- **Systems Architect**:
  - `bootstrap.sh` の CLI オプション解析は標準 POSIX/Bash 互換（`getopts` または `while [ $# -gt 0 ]`）とし、既存の環境変数（`BOOTSTRAP_FAST`, `FULL_BOOTSTRAP`, `BOOTSTRAP_WITH_GOSH` 等）との完全な後方互換性を維持する。
- **Information Security Specialist**:
  - CLI 引数のサニタイズを行い、任意のコマンド注入や不正フラグによるバイパスを防止する。

---

## 3. セキュリティ設計・脅威分析 / Security Considerations & Threat Modeling

| 脅威分類 (STRIDE) | 脆弱性識別子 (CWE) | 潜在的リスク / シナリオ | 適用する防護措置・緩和策 |
| :--- | :--- | :--- | :--- |
| **Tampering** | CWE-78 (OS コマンドインジェクション) | 不正な CLI 引数によるシェル変数展開の悪用 | 引数パース時に未知のフラグを厳格に拒否（`exit 1`）し、固定値代入のみを行う。 |
| **Elevation of Privilege** | CWE-494 (未検証バイナリの昇格) | Quick モードで誤動作するバイナリが `bin/ulisp-boot` へ昇格 | `verify_and_promote` 内のスモークテスト（`42` 評価）が完全一致（PASS）しない限りシード更新を行わない。 |
| **Denial of Service** | CWE-400 (リソース枯渇) | 不要なテストの重複実行による CPU/ディスク I/O 枯渇 | デフォルトで後処理テストをオプトイン化し、開発サイクルの不要な負荷を削減。 |

---

## 4. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 5 章「3段階セルフホスティングブートストラップ連鎖と不動点検証」
- 依存・関連 Issue:
  - [Issue #541](541-implement-fast-bootstrap-seed-and-subsecond-build-pipeline.md): ブートストラップシード (`bin/ulisp-boot`) 導入
  - [Issue #605](605-enhance-bootstrap-diagnostics-and-fallback-trace.md): ブートストラップ診断機構
  - [Issue #777](../777-bootstrap-compiler-alone-with-precompiled-stdlib-static-linking.md): 事前コンパイル済み標準ライブラリ静的リンクによるコンパイラ単体ブートストラップ
  - [Issue #778](../778-implement-modular-parallel-incremental-bootstrap.md): モジュール分割増分コンパイルと make -j 並列実行

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/bootstrap.sh](../../../ulisp/bootstrap.sh) (CLI 引数解析追加、Quick モード早期脱出、`verify_and_promote` 内オプトイン化)
- [x] [ulisp/Makefile](../../../ulisp/Makefile) (`bootstrap_quick`, `quick` ターゲット追加)
- [x] [ulisp/tests/test_bootstrap_diagnostics.sh](../../../ulisp/tests/test_bootstrap_diagnostics.sh) (既存診断テストの後退なきことの確認)
- [x] [docs/issues/README.md](../README.md) (Issue 台帳のステータス更新)

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/776-introduce-quick-bootstrap-mode-and-opt-in-post-tests`

### ステップ 1: `ulisp/bootstrap.sh` の CLI 引数解析とフラグ設定
- スクリプト冒頭（ディレクトリ設定直後）に引数ループを実装：
  ```bash
  BOOTSTRAP_QUICK="${BOOTSTRAP_QUICK:-0}"
  BOOTSTRAP_RUN_TESTS="${BOOTSTRAP_RUN_TESTS:-0}"
  FULL_BOOTSTRAP="${FULL_BOOTSTRAP:-0}"

  while [ $# -gt 0 ]; do
      case "$1" in
          --quick|-q|--stage1-only)
              BOOTSTRAP_QUICK=1
              shift
              ;;
          --full)
              FULL_BOOTSTRAP=1
              BOOTSTRAP_QUICK=0
              shift
              ;;
          --test)
              BOOTSTRAP_RUN_TESTS=1
              shift
              ;;
          --no-test)
              BOOTSTRAP_RUN_TESTS=0
              shift
              ;;
          --fast)
              BOOTSTRAP_FAST=1
              shift
              ;;
          --help|-h)
              echo "Usage: $0 [--quick|-q] [--full] [--test] [--no-test] [--fast]"
              exit 0
              ;;
          *)
              echo "Unknown option: $1" >&2
              exit 1
              ;;
      esac
  done
  ```

### ステップ 2: Stage 1 生成後の早期完了（Quick Exit）制御
- Stage 1 コンパイル・リンク成功直後に Quick モード判定を挿入：
  ```bash
  if [ "${BOOTSTRAP_QUICK:-0}" = "1" ]; then
      echo -e "\033[1;36m=== [QUICK BOOTSTRAP] Stage 1 built successfully. Skipping Stage 2/3 ===\033[0m"
      verify_and_promote "$BUILD_DIR/scheme-stage1" "Stage 1"
      exit 0
  fi
  ```

### ステップ 3: `verify_and_promote` 内の `test_incremental` オプトイン化
- `make -C "$ULISP_DIR" test_incremental` の呼び出しを `BOOTSTRAP_RUN_TESTS=1` の場合のみにガード：
  ```bash
  if [ "${BOOTSTRAP_RUN_TESTS:-0}" = "1" ]; then
      echo "=== Running Modular Separate Compilation & Incremental Verification (Issue #608) ==="
      make -C "$ULISP_DIR" test_incremental
  else
      echo "Skipping post-bootstrap tests (enable with BOOTSTRAP_RUN_TESTS=1 or --test)."
  fi
  ```

### ステップ 4: `ulisp/Makefile` への開発ターゲット追加
- 以下のターゲットを追加：
  ```makefile
  .PHONY: bootstrap_quick quick
  bootstrap_quick quick: core
  	BOOTSTRAP_QUICK=1 ./bootstrap.sh
  ```

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `./bootstrap.sh --quick` または `make -C ulisp quick` が実行可能であり、Stage 1 のみでスモークテストに合格し、約 2.5 分（従来比 1/7）で正常終了すること。
- [x] Quick モード実行時に `ulisp/bin/ulisp-boot` の安定シードが保護され、`make build/ulisp-modular` や `make test_incremental` のビルドが破損しないこと。
- [x] 通常の `./bootstrap.sh`（引数なし）実行時に、デフォルトで `test_incremental` がスキップされ、不要な重複待機時間が発生しないこと。
- [x] `./bootstrap.sh --test` 実行時には `test_incremental` が確実に実行されること。
- [x] 既存の `make -C ulisp test_bootstrap_diagnostics` が 100% PASS すること。
- [x] `make py_compile` および `make static_analysis` がエラー 0 件で通過すること。
- [x] 相対リンク規約に 100% 準拠していること。

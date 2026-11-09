---
ID: 694
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] MinGW-w64 および Wine を用いた Windows 向けクロスコンパイル・ローカル検証環境の構築 (ID: 694)

## 1. 概要 / Summary

ULisp コンパイラおよび Synapse 並行性ランタイムにおけるマルチ OS サポート（特に Windows x64 / Win32 環境）を、Linux 開発環境上で Windows 実機なしに高速かつ決定論的にクロス検証可能とするため、**MinGW-w64 (`x86_64-w64-mingw32-gcc`, `as`, `ld`)** および **Wine (`wine64` / `wine`)** を用いたローカルクロスコンパイル・実行検証基盤を構築する。

本 Issue は、後続の Issue #695 (ULisp Portable C99 バックエンドの Windows 移植) および Issue #697 (クロスプラットフォーム OSAL / IOCP 統合) に先立つ**基盤検証環境の確立**を目的とする。Linux ホスト上で `make -C ulisp test_wine_env`（またはルート `make test_wine_env`）を 1 コマンド実行するだけで：
1. MinGW-w64 クロスコンパイラツールチェインの存在およびバージョン検証
2. Wine ユーザー空間エミュレータの存在およびヘッドレス設定検証
3. 最小 PE32+ (x86-64 Windows) 実行可能バイナリのクロスコンパイルと終了コード (`exit(42)`) 検証
4. CRT 標準 I/O (`printf` / `write`) による標準出力キャプチャ検証
5. Direct Win32 API (`GetStdHandle`, `WriteFile`, `ExitProcess`) のリンクおよび実行検証
6. Microsoft x64 ABI（32 バイト Shadow Space / スタック 16 バイトアライメント境界）の健全性検証

を一括自動実行し、カラー化された結果レポートと合否ステータスを出力する検証パイプラインを確立する。

---

## 2. 脅威モデル分析とセキュリティ要件 (STRIDE & CWE)

本環境の導入およびクロスバイナリ実行に伴うセキュリティ上の脅威と対策を以下のように策定・厳格適用する。

| 脅威カテゴリ (STRIDE) | 脆弱性識別子 (CWE) | 潜在的リスク / 脅威シナリオ | 本 Issue における緩和策・防御仕様 |
| :--- | :--- | :--- | :--- |
| **Elevation of Privilege** (特権昇格) / **Tampering** | **CWE-250** / **CWE-732** (Uncontrolled Environment in Wine / Global Prefix Corruption) | ホストのデフォルト Wine プレフィックス (`~/.wine`) を直接使用した場合、ホストユーザーのファイルやレジストリが汚染・改ざんされるリスク。 | 検証スクリプト実行ごとに一意な一時ディレクトリ (`mktemp -d /tmp/ulisp_wine_XXXXXX`) を生成し、`WINEPREFIX` として隔離指定。スクリプト終了時に `wineserver -k` によるデーモン停止と一時ディレクトリ全消去を `trap` で強制保証。 |
| **Denial of Service** (サービス拒否) | **CWE-400** (Resource Exhaustion / Uncontrolled Process Hang) | Wine が初回起動時の Gecko/Mono インストールダイアログや GUI ウィンドウを表示してブロックし、CI/ローカルビルドが永久停止する。 | `WINEDEBUG=-all`、`WINEDLLOVERRIDES="mscoree,mshtml="`、`DISPLAY=` を明示指定してヘッドレス実行を強制。全実行コマンドに `timeout 30s` ガードを付与。 |
| **Tampering** (メモリ破損) | **CWE-787** / **CWE-119** (Out-of-bounds Write / Stack Corruption via ABI Mismatch) | Microsoft x64 ABI では呼出元 (Caller) が関数の直前に 32 バイトの Shadow Space (Homing Space) をスタック上に確保することが義務付けられている。これを怠ると、Win32 API がスタック上の隣接フレームを上書き破壊する。 | MinGW コンパイルバイナリおよびインラインアセンブリにおいて、MS x64 呼出規約 (`sub rsp, 32` / `add rsp, 32` および `rsp % 16 == 0`) に完全準拠していることを検証ケースで直接アサート。 |

---

## 3. トレーサビリティと影響範囲 / Traceability & Scope

### 3.1 仕様書トレーサビリティ
- **DSN-33**: §4 (フェーズ別コンパイラ設計), §7.4 (多重ターゲットバックエンド), §10 (品質ゲート・テスト自動化)
- **関連 Issue**:
  - [closed/504-implement-portable-c-backend-via-lir.md](closed/504-implement-portable-c-backend-via-lir.md) (Portable C Backend via LIR)
  - [closed/689-establish-qemu-user-emulation-multi-architecture-test-harness.md](closed/689-establish-qemu-user-emulation-multi-architecture-test-harness.md) (QEMU Multi-Arch Test Harness)
  - [closed/693-integrate-qemu-aarch64-automated-regression-test-suite-into-makefile.md](closed/693-integrate-qemu-aarch64-automated-regression-test-suite-into-makefile.md) (QEMU AArch64 Regression Test Suite)
  - [695-port-c-backend-to-windows-and-verify-via-wine.md](695-port-c-backend-to-windows-and-verify-via-wine.md) (後続: Windows C99 Backend 移植)

### 3.2 影響ファイル一覧
- [x] [docs/issues/694-setup-mingw-and-wine-verification-environment.md](694-setup-mingw-and-wine-verification-environment.md) (本仕様書)
- [x] [docs/issues/README.md](README.md) (Issue 台帳のステータス更新)
- [x] [ulisp/scripts/test_wine_env.sh](../../ulisp/scripts/test_wine_env.sh) (新規作成: MinGW & Wine ヘッドレス疎通・ABI 検証スクリプト)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`CROSS_CC_WIN64`, `WINE64` 変数および `test_wine_env` / `test-wine-env` ターゲット追加)
- [x] [Makefile](../../Makefile) (ルート `test_wine_env` ターゲット追加と委譲)
- [x] [docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (テスト自動化マトリクス追記)

---

## 4. アーキテクチャ設計 / Technical Architecture

```
+---------------------------------------------------------------------------------------+
|  Host: Linux x86-64 Environment                                                       |
|                                                                                       |
|   make test_wine_env / make -C ulisp test_wine_env                                    |
|         │                                                                             |
|         ▼                                                                             |
|   ulisp/scripts/test_wine_env.sh                                                      |
|         │                                                                             |
|         ├── [1] Toolchain & Emulator Detection                                        |
|         │         x86_64-w64-mingw32-gcc, x86_64-w64-mingw32-ld, wine64 / wine       |
|         │                                                                             |
|         ├── [2] Isolated Headless Wine Environment Setup                              |
|         │         WINEPREFIX=/tmp/ulisp_wine_XXXXXX                                   |
|         │         WINEDEBUG=-all, DISPLAY=, WINEDLLOVERRIDES="mscoree,mshtml="        |
|         │                                                                             |
|         ├── [3] Stage 1: Minimal PE32+ exit(42) Binary                                |
|         │         $CROSS_CC_WIN64 -O2 test_exit42.c -o test_exit42.exe                |
|         │         wine64 test_exit42.exe -> assert(exit == 42)                        |
|         │                                                                             |
|         ├── [4] Stage 2: CRT Stdio & String I/O Capture                               |
|         │         $CROSS_CC_WIN64 -O2 test_stdio.c -o test_stdio.exe                   |
|         │         wine64 test_stdio.exe -> assert(stdout == "MinGW Wine OK")          |
|         │                                                                             |
|         ├── [5] Stage 3: Direct Win32 API Linkage & Invocation                        |
|         │         $CROSS_CC_WIN64 -O2 test_win32.c -lkernel32 -o test_win32.exe       |
|         │         wine64 test_win32.exe -> GetStdHandle / WriteFile / ExitProcess(42) |
|         │                                                                             |
|         ├── [6] Stage 4: Microsoft x64 Calling Convention Invariants                  |
|         │         RCX/RDX/R8/R9 arg registers, 32-byte Shadow Space, RSP % 16 == 0    |
|         │         wine64 test_abi.exe -> assert(shadow_space_ok && exit == 0)         |
|         │                                                                             |
|         └── [7] Trap Cleanup & Summary Matrix Reporting                               |
|                   wineserver -k, rm -rf $WINEPREFIX, ANSI Colored Summary Table       |
+---------------------------------------------------------------------------------------+
```

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/694-setup-mingw-wine-verification-environment`

### Step 1: ホスト環境へのツールチェイン導入確認とパッケージ整備
- ホスト上の `gcc-mingw-w64-x86-64` および `wine64` / `wine` パッケージのインストール確認。
- 未導入の場合、`apt-get install -y gcc-mingw-w64-x86-64 wine64 wine` を実行し、`x86_64-w64-mingw32-gcc --version` および `wine64 --version` がパス解決可能であることを確認。

### Step 2: ヘッドレス Wine 疎通・ABI 検証スクリプトの作成 (`ulisp/scripts/test_wine_env.sh`)
- `ulisp/scripts/test_wine_env.sh` を新規作成（実行権限 `chmod +x` 付与）：
  - **Toolchain Discovery**:
    - `CROSS_CC_WIN64` (既定: `x86_64-w64-mingw32-gcc`)
    - `WINE64` (既定: `command -v wine64 || command -v wine`)
    - ツール未検出時の親切なエラーメッセージと終了コード `1` でのフェイルファスト。
  - **Isolated Ephemeral WINEPREFIX**:
    - `WINEPREFIX=$(mktemp -d /tmp/ulisp_wine_XXXXXX)`
    - 環境変数 `WINEDEBUG=-all`, `DISPLAY=`, `WINEDLLOVERRIDES="mscoree,mshtml="`
    - `trap 'wineserver -k 2>/dev/null || true; rm -rf "${WINEPREFIX}" "${TMP_DIR}"' EXIT`
  - **Test Stage 1: Minimal PE32+ Exit Code (42)**:
    - 最小 C コード `int main(void) { return 42; }` をコンパイル・実行し、終了ステータス 42 を確認。
  - **Test Stage 2: CRT Stdio Output Capture**:
    - `printf("ULisp Windows Wine Verification: OK\n")` をコンパイル・実行し、標準出力を完全一致キャプチャ。
  - **Test Stage 3: Direct Win32 API Linkage**:
    - `<windows.h>` をインクルードし、`GetStdHandle(STD_OUTPUT_HANDLE)`、`WriteFile()`、`ExitProcess(42)` を実行・検証。
  - **Test Stage 4: Microsoft x64 Calling Convention Invariants**:
    - インラインアセンブリまたは C で 4 引数 (`rcx`, `rdx`, `r8`, `r9`) および 32 バイト Shadow Space (`[rsp + 32]`) の退避・16 バイトスタックアラインメント境界を検証。
  - **Summary Matrix Table**:
    - ANSI カラー表示による明瞭な結果サマリー表を出力。

### Step 3: Makefile ターゲット統合とエイリアス整備
- `ulisp/Makefile`:
  - 変数 `CROSS_CC_WIN64 ?= x86_64-w64-mingw32-gcc`
  - 変数 `WINE64 ?= $(shell command -v wine64 2>/dev/null || command -v wine 2>/dev/null)`
  - ターゲット `test_wine_env` およびハイフン付きエイリアス `test-wine-env` を追加。
- ルート `Makefile`:
  - ターゲット `test_wine_env` および `test-wine-env` を追加し、`make -C ulisp test_wine_env` を委譲実行。

### Step 4: 全品質ゲート検証とドキュメント更新
- `make -C ulisp test_wine_env` および `make test_wine_env` が 4/4 全ステージ PASS することを確認。
- 既存 x86-64 テスト (`make -C ulisp test_context_switch` 等) および AArch64 QEMU テスト (`make test_aarch64_qemu`) が 100% 維持されること。
- `make -C ulisp lint_sexpr` が 100% balanced。
- `make verify_quality` が 100% PASS。
- [DSN-33](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 設計ドキュメントに Windows Wine 検証環境を追記。
- Issue #694 を `docs/issues/closed/` へ移動し、[docs/issues/README.md](README.md) の台帳を更新。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] **クロスコンパイル＆エミュレータツールの配備とパス解決**:
  - `x86_64-w64-mingw32-gcc --version` および `wine64 --version` (または `wine --version`) が正常に終了コード 0 を返却すること。
- [x] **全自動ワンコマンド疎通検証**:
  - `make -C ulisp test_wine_env`（および `make test_wine_env`）の 1 コマンドで、全 4 ステージのコンパイル・実行・出力検証が自動完走すること。
- [x] **Win32 API および MS x64 呼出規約の整合性**:
  - Direct Win32 API 呼び出しおよび 32 バイト Shadow Space / 16 バイトスタックアライメントが Wine 上で正常動作すること。
- [x] **完全隔離されたヘッドレス実行**:
  - 一時 `WINEPREFIX` 上で `WINEDEBUG=-all` かつ `DISPLAY=` により GUI ダイアログ一切なしでヘッドレス完走し、終了時に `wineserver -k` で確実にクリーンアップされること。
- [x] **既存環境への無影響 (リグレッションフリー)**:
  - `make test_aarch64_qemu` (206 件) および `make -C ulisp test_context_switch` (89 件) が 100% PASS を維持すること。
- [x] **品質ゲート 100% 合格**:
  - `make -C ulisp lint_sexpr` が 100% PASS すること。
  - `make py_compile`, `make check_format`, `make static_analysis` がエラー 0 件で合格すること。

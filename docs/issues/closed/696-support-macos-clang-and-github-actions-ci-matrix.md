---
ID: 696
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] ULisp Portable C99 バックエンドの macOS (Clang) 対応および GitHub Actions CI マトリクス検証の確立 (ID: 696)

## 1. 概要 / Summary
ULisp の C99 バックエンド（Pass 160: `ulisp/backend/160_backend_c.scm`）によるトランスパイル出力を、macOS（Darwin / Apple Clang / Apple Silicon M1・M2 & Intel x86-64）環境において警告・エラー 0 件で完全動作するように適合させる。

macOS では POSIX 規格に準拠しつつも、動的リンカにおける大域変数 `environ` の直接参照制約（`crt_externs.h` の `_NSGetEnviron()` 必須）、厳格な W^X（Write XOR Execute）メモリ保護モデル（Hardened Runtime & System Integrity Protection / SIP）、および Apple Clang 特有の厳格な警告（`-std=c99 -Wall -Wextra -Werror -pedantic`）が存在する。
本 Issue ではこれらをプラットフォーム抽象化レイヤーに統合し、macOS 向けターゲット（`c-macos`, `c-darwin`）のサポートを追加するとともに、GitHub Actions 上で `macos-14` (Apple Silicon arm64) および `macos-13` (Intel x86_64) を含むマルチ OS CI マトリクス（`.github/workflows/os_matrix.yml`）を新設して継続的品質保証を確立する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §2.1 (Tagged Pointer メモリモデル), §3 (言語機能と低レイヤコード生成仕様), §6.1 (セルフホスティングパイプライン)
- **DSN-33-02**: §2.1 (Pass 160 Portable C Backend), §7.2 (C バックエンド同期とクロスプラットフォーム検証)
- **関連 Issue**:
  - #504: Portable C Backend via LIR
  - #694: MinGW & Wine Environment Verification
  - #695: ULisp Portable C99 Backend Windows (MinGW/MSVC) 移植と Wine 実行検証
  - #691: AArch64 Native Machine Code Generation & ABI
  - #831: C バックエンドにおける型付き機械語 LIR セマンティクスの完全同期

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm):
  - macOS (Darwin) 向けプリプロセッサヘッダー分岐の追加（`<crt_externs.h>`, `_NSGetEnviron()`）
  - Apple Clang 向け警告抑止ディレクティブ（`-Wunused-label`, `-Wunused-parameter`）の整備
  - メモリ保護 W^X 準拠（データヒープの `PROT_READ | PROT_WRITE` 保持と `MAP_ANON` 整合）
- [x] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm):
  - `--target c-macos`, `--target c-darwin`, `--target c-apple` CLI ターゲットエイリアスの追加
- [x] [ulisp/tests/test_c_backend_clang.scm](../../ulisp/tests/test_c_backend_clang.scm):
  - Clang (`clang -std=c99 -O2 -Wall -Wextra -Werror -pedantic`) を用いた C コード生成・コンパイル・実行検証スイート
- [x] [ulisp/Makefile](../../ulisp/Makefile) & [Makefile](../../Makefile):
  - `make test_c_clang` および `make test_c_macos` ターゲットの追加
- [x] [.github/workflows/os_matrix.yml](../../.github/workflows/os_matrix.yml):
  - Ubuntu (`ubuntu-24.04`), macOS (`macos-14` arm64, `macos-13` x86_64), Windows (`windows-latest`) を対象とする GitHub Actions マトリクス CI ワークフローの構築

---

## 4. 脅威モデルとセキュリティ検証 (Threat Model & Security Mitigation)

| 脅威項目 (Threat Vector) | 影響度 | 脆弱性メカニズム | 対策・緩和策 (Mitigation) |
| :--- | :---: | :--- | :--- |
| **W^X メモリ保護違反によるプロセス強制終了** | High | macOS Hardened Runtime 下で、同一メモリ領域に実行可能属性 (`PROT_EXEC`) と書込属性 (`PROT_WRITE`) が付与されると `EXC_BAD_ACCESS` / `SIGKILL` が送出される。 | Cheney 2-space GC ヒープは純粋なデータ領域（`PROT_READ \| PROT_WRITE`）として `mmap` し、実行属性を一切要求しない。JIT 命令生成とデータヒープの境界を完全に物理分離する。 |
| **動的リンク時の大域変数 `environ` シンボル未解決** | Medium | macOS の Mach-O では `environ` が共有ライブラリから直接エクスポートされない場合があり、実行時未解決シンボルエラーまたは不正メモリアクセスが発生する。 | `#if defined(__APPLE__)` では `<crt_externs.h>` をインクルードし、Apple 推奨の `(*_NSGetEnviron())` 経由で取得する。 |
| **環境変数・引数ポインタの不正デリファレンス** | Medium | `argc`, `argv`, `envp` の取得時に NULL ポインタを dereference するとクラッシュする。 | `ulisp_environ` 格納時に NULL ガードを実施し、常に安全なフォールバックを適用する。 |

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/696-support-macos-clang-and-ci-matrix`

### 5.1 `ulisp/backend/160_backend_c.scm` の改修詳細
1. **Darwin / macOS 固有の環境変数取得マクロ (`ulisp_get_environ`) の導入**:
   ```c
   #if defined(__APPLE__)
   #include <crt_externs.h>
   #define ulisp_get_environ() (*_NSGetEnviron())
   #elif defined(_WIN32)
   extern char **_environ;
   #define ulisp_get_environ() (_environ)
   #else
   extern char **environ;
   #define ulisp_get_environ() (environ)
   #endif
   ```
   `main` 関数内の `ulisp_environ` 初期化を以下のように統一：
   ```c
   ulisp_environ[0] = (uint64_t)(uintptr_t)(envp ? envp : ulisp_get_environ());
   ulisp_environ[1] = (uint64_t)argc;
   ulisp_environ[2] = (uint64_t)(uintptr_t)argv;
   ```

2. **Apple Clang 向け警告ディレクティブの統合**:
   ```c
   #if defined(__clang__)
   #pragma clang diagnostic ignored "-Wunused-label"
   #pragma clang diagnostic ignored "-Wunused-parameter"
   #pragma clang diagnostic ignored "-Wunused-variable"
   #elif defined(__GNUC__)
   #pragma GCC diagnostic ignored "-Wunused-label"
   #endif
   ```

3. **メモリマッピング整合性**:
   macOS の `mmap` では `MAP_ANON` が定義されているため、既存の `#ifndef MAP_ANONYMOUS` ガードが正しく機能することを確認。アライメント要件（16バイト境界）およびページサイズ（Apple Silicon 16KB ページ、Intel 4KB ページ）に対して、ヒープサイズ（16MB）が整数倍で整合格納されることを担保。

### 5.2 `ulisp/compiler/driver.scm` の CLI ターゲット拡張
- `compile-backend` のターゲット判定に `'c-macos`, `'c-darwin`, `'c-apple` を追加。
- CLI `--target c-macos` 等で C バックエンドが正しく選択されるように設定。

### 5.3 テストスイート `ulisp/tests/test_c_backend_clang.scm` の新設
- ホストに `clang` が存在する場合に `clang -std=c99 -O2 -Wall -Wextra -Werror -pedantic` で生成コードをビルドし、実行結果を検証。
- 整数演算 (Fixnum)、真偽値、ペア・リスト、クロージャ、再帰階乗計算、バイナリ文字列出力、および Cheney コピー GC（10,000 ペア確保）の正常動作をアサート。

### 5.4 GitHub Actions CI マトリクス (`.github/workflows/os_matrix.yml`) の新設
- **トリガー**: `push` / `pull_request` (branches: `[main]`)
- **マトリクス構成**:
  - `ubuntu-24.04` (GCC 13 / Clang)
  - `macos-14` (Apple Silicon M1/M2, Apple Clang)
  - `macos-13` (Intel x86_64, Apple Clang)
  - `windows-latest` (MinGW-w64 / MSVC)
- **実行ステップ**:
  1. リポジトリのチェックアウト
  2. システム依存パッケージのセットアップ（Gauche / Clang / GCC）
  3. ULisp C99 バックエンドによる Scheme コードのトランスパイル
  4. ネイティブコンパイラ（Apple Clang / GCC）による `-Wall -Wextra -Werror` ビルド
  5. 生成バイナリの実行と出力・戻り値の自動アサート検証

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] **macOS Clang 適合性**:
  - 出力された C ソースコードが Apple Clang および LLVM Clang の `-std=c99 -O2 -Wall -Wextra -Werror -pedantic` オプションで無警告・無エラーでビルド可能であること。
- [x] **環境変数アクセスの完全性**:
  - macOS 上で `_NSGetEnviron()` を用いて `environ` が正常に取得でき、リンカエラー（`undefined symbol: _environ`）が一切発生しないこと。
- [x] **W^X メモリ保護適合性**:
  - Apple Silicon (arm64) および Intel (x86_64) の macOS 環境で Cheney GC ヒープが安全に確保・解放され、`SIGSEGV` や `EXC_BAD_ACCESS` が発生しないこと。
- [x] **CI マトリクスワークフローの確立**:
  - `.github/workflows/os_matrix.yml` が新設され、GitHub Actions 上で `macos-14`、`macos-13`、`ubuntu-24.04`、`windows-latest` が構文エラーなく定義されていること。
- [x] **テストスイート PASS**:
  - `make test_c_clang`（または CI 上での Clang テスト）が 100% PASS すること。
- [x] **相対パス準拠**:
  - 本ファイルおよび関連ドキュメント内に絶対パスリンクが 0 件であること。

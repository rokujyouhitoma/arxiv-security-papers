---
ID: 696
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] ULisp Portable C99 バックエンドの macOS (Clang) 対応および GitHub Actions CI マトリクス検証の確立 (ID: 696)

## 1. 概要 / Summary
ULisp の C99 バックエンド（Pass 160: `ulisp/backend/160_backend_c.scm`）によるコード出力を macOS（Darwin / Apple Silicon / Intel）環境に完全適合させる。
Apple Clang での厳格なコンパイルチェック（`-std=c99 -Wall -Wextra -Werror -pedantic`）、`libSystem` リンケージ、および macOS 特有の W^X メモリ保護規約への準拠を確保し、GitHub Actions の `macos-14` (Apple Silicon M1) / `macos-13` ランナーを用いた自動回帰テストパイプラインを確立する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §3 (言語機能と低レイヤコード生成仕様), §6.1 (セルフホスティングパイプライン)
- **関連 Issue**: #504 (Portable C Backend via LIR), #695 (Windows C99 Backend), #691 (AArch64 Codegen)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm): macOS (Darwin) 向け C コード生成規約適合
- [ ] [.github/workflows/os_matrix.yml](../../.github/workflows/os_matrix.yml): GitHub Actions マルチ OS (Linux / macOS / Windows) マトリクス定義
- [ ] [ulisp/Makefile](../../ulisp/Makefile): macOS 向け Clang コンパイルフラグの整備

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/696-support-macos-clang-and-ci-matrix`

1. macOS 向け C コード生成の適合性向上：
   - `#ifdef __APPLE__` におけるヘッダー依存（`<sys/mman.h>`, `<mach/mach_time.h>` 等）の整理。
   - Apple Silicon における JIT / コード実行境界（`pthread_jit_write_protect_np` 等）の考慮。
2. GitHub Actions ワークフロー（`.github/workflows/os_matrix.yml`）の新設：
   - マトリクス: `[ubuntu-latest, macos-14, windows-latest]`
   - 各 OS で Scheme 入力から C コードをトランスパイルし、現地のネイティブ C コンパイラ（GCC / Apple Clang / MSVC）でビルド＆実行。
3. エラー・回帰発生時のログ通知およびレポート自動生成。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 出力された C ソースコードが Apple Clang で警告・エラー 0 件でビルドできること。
- [ ] GitHub Actions 上で `macos-14`（Apple Silicon M1）による自動テストが完走し、全テストケースが PASS すること。


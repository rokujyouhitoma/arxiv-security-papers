---
ID: 542
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT] Prepare MacOS Compatibility for Portable C Backend and Comprehensive Build Documentation (ID: 542)

## 1. 概要 / Summary
uLisp の可搬性（Portability）を最大化するため、手元に実機のない MacOS 環境（Apple Silicon / Intel Mac）でも、C 言語バックエンド（`(!target c)`）および `runtime.c` を用いて確実にビルド・実行できるよう、OS 差異の事前吸収コードの追加、ULisp コンパイラ自身および任意の Scheme プログラムのビルド手順の完全ドキュメント化、ならびに x86-64 ネイティブバックエンドとの実測性能評価を実施した。

具体的には以下を完遂した：
1. `ulisp/runtime.c` における MacOS (Darwin / Clang) 固有のシグナルコンテキスト・メモリマッピング定数（`MAP_ANON` / `MAP_ANONYMOUS`、`ucontext_t` レジスタアクセス）のクロスプラットフォーム両立改修。
2. `ulisp/test_c.sh` における OS 判定および Clang/GCC 自動判別対応。
3. 包括的手順書 `ulisp/docs/PORTABLE_BUILD_GUIDE.md` の整備（ULisp コンパイラ自身のビルド手順、任意の Scheme コードのコンパイル手順、前提環境、実測性能評価、FAQ）。
4. `ulisp/README.md` および `ulisp/docs/README.md` への導線追加。
5. x86-64 ネイティブ vs Portable C バックエンドの実測ベンチマーク測定 (`ulisp/benchmarks/run_bench_c_vs_x86.sh`) の実施と性能特性の解明。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §6 (マルチターゲットバックエンド & ポータビリティ仕様)
- **先行 Issue**: #504 (Portable C / WebAssembly Backend via LIR)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/runtime.c](file:///workspace/arxiv-security-papers/ulisp/runtime.c): Darwin (macOS) / Linux 双方で警告ゼロとなるプリプロセッサ分岐・`MAP_ANONYMOUS` フォールバック
- [x] [ulisp/test_c.sh](file:///workspace/arxiv-security-papers/ulisp/test_c.sh): macOS (Darwin) 環境での Clang 自動選択・ポータブル実行対応
- [x] [ulisp/docs/PORTABLE_BUILD_GUIDE.md](file:///workspace/arxiv-security-papers/ulisp/docs/PORTABLE_BUILD_GUIDE.md): クロスプラットフォーム・コンパイル＆ビルド手順書（新設）
- [x] [ulisp/benchmarks/run_bench_c_vs_x86.sh](file:///workspace/arxiv-security-papers/ulisp/benchmarks/run_bench_c_vs_x86.sh): x86-64 vs C 実測性能測定スクリプト（新設）
- [x] [ulisp/README.md](file:///workspace/arxiv-security-papers/ulisp/README.md): ポータブル C バックエンドおよびビルド手順の記載
- [x] [ulisp/docs/README.md](file:///workspace/arxiv-security-papers/ulisp/docs/README.md): 開発者リファレンス目次の更新
- [x] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳の更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/542-prepare-macos-portability-for-c-backend-and-documentation`

1. **`runtime.c` の Darwin 互換性担保**:
   - `MAP_ANONYMOUS` 未定義時の `MAP_ANON` フォールバック定義。
   - `crash_handler` のレジスタダンプにおいて、`__APPLE__` 環境下では Darwin の安全なシグナル情報出力へフォールバックして `-Werror` 警告・エラーを完全防止。
2. **テストスクリプトの macOS 適合化 (`ulisp/test_c.sh`)**:
   - `uname -s` で `Darwin` を検知した場合、デフォルト C コンパイラを `clang` に設定。
3. **クロスプラットフォーム手順書の作成 (`ulisp/docs/PORTABLE_BUILD_GUIDE.md`)**:
   - 前提環境（Xcode Command Line Tools: `xcode-select --install`, Python 3, Git）
   - ULisp コンパイラ自身の 3 つのビルド方式（方式 A: シードバイナリ即時ビルド、方式 B: Python 完全自律ブートストラップ、方式 C: C バックエンドによるコンパイラバイナリ化）
   - 任意の Scheme プログラムの C トランスパイルおよび Clang/GCC によるネイティブバイナリ生成手順
   - 実測ベンチマーク結果（fib, loop, closure, list）の記載
   - トラブルシューティング（セキュリティ権限、mmap 等）
4. **性能比較ベンチマークの実装・実行**:
   - 代表的ワークロード 4 種（fib 30, loop 10M, closure 1M, list 100k）での実測比較。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `runtime.c` が Darwin / Linux の両方でコンパイル可能なコード構成になっていること。
- [x] `ulisp/test_c.sh` が Linux 環境で全 42 テスト PASS すること。
- [x] `ulisp/docs/PORTABLE_BUILD_GUIDE.md` が作成され、ULisp コンパイラ自身のビルド手順および任意のコードのコンパイル手順が網羅されていること。
- [x] `ulisp/README.md` および `ulisp/docs/README.md` に手順書のリンク・概要が記載されていること。
- [x] x86-64 ネイティブと C バックエンドの性能比較結果が提示されていること。
- [x] 全品質ゲート（`make check_format`, `make py_compile`）をパスすること。


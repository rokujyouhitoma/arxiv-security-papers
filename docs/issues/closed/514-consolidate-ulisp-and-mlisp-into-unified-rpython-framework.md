---
ID: 514
種別: Refactor
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] ULisp と MLisp の完全統合による統一 RPython スタイルメタプログラミング言語基盤の確立 (ID: 514)

## 1. 概要 / Summary

これまで別々の最上位ディレクトリとして開発されてきた `ulisp` (Nanopass AOT コンパイラ基盤) と `mlisp` (限定継続メタトレーシング JIT エンジン) を、単一の統一言語基盤フレームワーク `ulisp/` 配下に完全統合・再編した。

RPython のアーキテクチャ (`rpython/translator` + `rpython/jit` + `rpython/memory` + `rpython/rlib`) に倣い、ULisp を以下の 3 層統合フレームワークとして昇格させた：
1. **Layer 1: AOT Nanopass Substrate (`ulisp/passes/`, `ulisp/compiler.scm`)**: 決定論的自己ホスティング (`stage2.s` と `stage3.s` のビット一致) を維持する極小 AOT コア。
2. **Layer 2: Standard Substrate & Runtime (`ulisp/lib/`, `ulisp/gc/`, `ulisp/runtime.c`)**: RPython の `rlib` / `memory` に相当する標準ライブラリ群 (`rposix`, `rstring`, `rdict`, `rgc`, `rjit` スタブ)。
3. **Layer 3: Meta-tracing JIT (`ulisp/jit/`, `ulisp/driver/jit.scm`)**: 旧 MLisp の全モジュール (限定継続 `delimcc`, トレース抽出, 部分評価 `pe`, 仮想オブジェクト除去 `virtuals`, LIR ブリッジ `to_lir`) を取り込み、ワンバイナリ `ulisp-jit` を生成・実行する JIT ランタイム。

本統合により、二重管理されていた Makefile・テストスイート・ビルドスクリプトを単一の `ulisp/Makefile` に一本化し、境界線のあいまいさを根絶した。

---

## 2. トレーサビリティ / Traceability

- 関連 Issue:
  - Issue 507: 限定継続と ULisp LIR に基づく内因的メタトレーシング JIT (MLisp) の実装
  - Issue 508: MLisp の AOT 統合および JIT 内蔵型ワンバイナリの生成
  - Issue 512: ULisp AOT コンパイラと MLisp JIT エンジンを統合したワンバイナリ (ulisp-jit) の構築と性能比較評価
  - Issue 513: MLisp コードベースの純化・重複解消および不要コードの完全排除
- 関連設計書:
  - `docs/designs/DSN-34-mlisp_endogenous_meta_tracing_jit_architecture_specification.md`
  - `ulisp/README.md`
  - `mlisp/README.md`

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/jit/](ulisp/jit/) (新規: `mlisp/core`, `tracer`, `optimizer`, `bridge`, `runtime`, `examples` を移設)
- [x] [ulisp/driver/jit.scm](ulisp/driver/jit.scm) (新規: `mlisp/driver/ulisp_jit.scm` を移設・統合)
- [x] [ulisp/tests/jit/](ulisp/tests/jit/) (新規: `mlisp/tests/` の全 94 テストを移設・統合)
- [x] [ulisp/benchmarks/](ulisp/benchmarks/) (新規: `mlisp/benchmarks/` を移設)
- [x] [ulisp/Makefile](ulisp/Makefile) (AOT bootstrap, JIT binary, 統一テストスイートを一括管理できるように拡張)
- [x] [ulisp/README.md](ulisp/README.md) (統一アーキテクチャ仕様・ディレクトリ構成・ビルド手順の包括的改訂)
- [x] [mlisp/README.md](mlisp/README.md) (移行完了アナウンスおよび `ulisp/jit/` への案内)
- [x] [docs/issues/README.md](docs/issues/README.md)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/514-consolidate-ulisp-and-mlisp-into-unified-rpython-framework`

1. **モジュール移設とパス再編**:
   - `mlisp/core/`, `tracer/`, `optimizer/`, `bridge/`, `runtime/`, `examples/` を `ulisp/jit/` へ移設。
   - `mlisp/driver/ulisp_jit.scm` を `ulisp/driver/jit.scm` へ移設し、内部の相対パスを `ulisp/` 基準に更新。
   - `mlisp/tests/` を `ulisp/tests/jit/` へ移設。
   - `mlisp/benchmarks/` を `ulisp/benchmarks/` へ移設し、パスを調整。
2. **Makefile の統合 (`ulisp/Makefile`)**:
   - `make test`: AOT パステスト (`test_passes`, `test_aarch64`) と JIT 全テスト (`test_jit`) を一括実行。
   - `make bootstrap`: AOT 自己ホスティング連鎖 (`stage1 -> stage2 -> stage3 -> diff`) を実行。
   - `make jit` / `make bin/ulisp-jit`: AOT + JIT 統合ワンバイナリ `ulisp-jit` を生成。
   - `make run_jit`: `bin/ulisp-jit` の JIT ループ実行 (45) および AOT コンパイル (120) を検証。
   - `make bench`: AOT vs JIT ベンチマークを一括実行。
3. **旧 `mlisp/` のクリーンアップ**:
   - `mlisp/` 配下のソースコードを削除し、移行案内 `mlisp/README.md` と後方互換フォワーダー `mlisp/Makefile` を整備。
4. **品質検証**:
   - `make -C ulisp bootstrap` による自己ホスティング不動点検証 (`cmp stage2.s stage3.s == 0`)。
   - `make -C ulisp test` (全 AOT + JIT 94 テスト PASS)。
   - `make -C ulisp run_jit` (JIT + AOT 両モード正常動作)。
   - リポジトリ全域の品質ゲート (`make check_format`, `make py_compile`) 通過。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `mlisp` の全 JIT モジュールが `ulisp/jit/` 配下に統合されていること。
- [x] `ulisp/Makefile` で `make test` を実行した際、AOT テストおよび JIT 94 テストが全て PASS すること。
- [x] `make -C ulisp bootstrap` が成功し、`stage2.s` と `stage3.s` がビット完全一致すること。
- [x] `make -C ulisp run_jit` が成功し、`bin/ulisp-jit` が正常に JIT 実行 (45) および AOT コンパイル (120) を完了すること。
- [x] `ulisp/README.md` に RPython 完全相似モデルとしての統一設計が記載されていること。
- [x] リポジトリ全体の品質ゲート (`make format`, `make static_analysis`) が 100% PASS すること。

---
ID: 608
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Nanopass・モジュール単位の完全分割コンパイル（.o）および増分ビルド（Incremental Build）基盤の実装 (ID: 608)

## 1. 概要 / Summary
Issue 607 により標準ライブラリとコンパイラ本体の 2 分割リンクが実現された後、最終的な理想アーキテクチャとして、コンパイラを構成する各 Nanopass（フロントエンド、解析、最適化、LIR、バックエンド）およびライブラリをモジュール単位で個別に `.o`（ELF オブジェクト）化し、変更のあったファイルのみを再コンパイルする「完全増分ビルド（Incremental Build）」を実現する。

本 Issue では、各 Nanopass やライブラリが提供する構文マクロや型注釈等のコンパイル時メタデータを抽出・共有するインターフェース生成機構（`.sym` / `.sbi`）を構築し、GNU Make の依存関係グラフと連動させる。これにより、特定の Nanopass（例: `128_lir_branch_fusion.scm`）を 1 行修正した際、そのパスの `.o` のみコンパイルしてリンクするだけで開発サイクルを回せる極限のサブセカンド（0.05秒以下）ビルドを実現する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/spec_pipeline.md)
- **関連 Issue**:
  - Issue 541: ブートストラップシード導入による高速ビルドパイプラインの構築
  - Issue 598: 統一 Pass Manager の導入によるパイプライン制御・最適化レベルスケジューリング・観測性の一元化
  - Issue 606: ビルド時 cat 結合の廃止と R7RS include 構文によるソース位置追跡基盤の導入
  - Issue 607: 外部シンボル（extern）参照解決と標準ライブラリ・コンパイラの2分割 .o 静的リンク基盤の導入

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (モジュール別 `.scm -> .o` パターンルールおよび依存関係グラフの構築)
- [ ] [ulisp/frontend/010_library.scm](../../ulisp/frontend/010_library.scm) (モジュール境界とエクスポート定義の厳格化)
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm) (独立コンパイル時の Pass 登録とメタデータ共有)
- [ ] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (モジュール別増分検証の統合)
- [ ] [ulisp/tests/test_incremental_build.sh](../../ulisp/tests/test_incremental_build.sh) (新規: 増分ビルド挙動検証テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/608-implement-modular-separate-compilation-and-incremental-build`

1. **コンパイル時メタデータ（マクロ・構文定義）のキャッシュ機構**:
   - マクロ展開器（Pass 020）や DSL 定義（Pass 015）を提供するコアモジュールのコンパイル時環境をバイナリまたは S 式形式でシリアライズ（`.sym`）。
   - 後続の Pass を独立コンパイルする際、このシンボル環境のみをロードして高速に展開。
2. **Makefile パターンルールの整備**:
   - `build/%.o: %.scm` ルールを策定。
   - 各 Pass を `build/frontend/%.o`、`build/lir/%.o`、`build/backend/%.o` に個別出力。
3. **トップレベル静的リンカスクリプトの整備**:
   - 全 Pass の `.o` および標準ライブラリ `.o` を一括で `ld` / `gcc -nostdlib` でリンクし、`bin/ulisp` を生成。
4. **増分ビルドの検証**:
   - 1 ファイルのみ `touch` した場合に、そのファイルのみがコンパイルされ、リンクが実行されることをテスト。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 各 Nanopass（`010`〜`160`）が独立して `.o` ファイルにコンパイルできること。
- [ ] 1 ファイルの変更時、他の Pass の再コンパイルがスキップされ、0.1 秒未満でリンク完了すること。
- [ ] 全体のブートストラップ（3-stage bootstrap fixed-point）が 100% 成立すること。
- [ ] `make test_unit` および `bash ulisp/test.sh` が 100% PASS すること。

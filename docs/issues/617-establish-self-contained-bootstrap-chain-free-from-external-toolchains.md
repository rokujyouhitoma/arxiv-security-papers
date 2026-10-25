---
ID: 617
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 外部ツール完全非依存な自給自足 3-Stage セルフホスティングブートストラップの確立 (ID: 617)

## 1. 概要 / Summary
Issue 615（脱 GCC ドライバ）および Issue 616（Direct-to-ELF バックエンド）の成果を統合し、ULisp の 3-Stage ブートストラップ（セルフホスティング連鎖）を、ホスト環境の GCC、Clang、GNU binutils（as / ld）、Python 等の外部ツールに一切依存しない「完全自給自足（Self-contained）」形態へと昇格させる。

リポジトリにコミットされたシードバイナリ（`bin/ulisp-boot`）を出発点とし、自身（`ulisp_core.scm`）を直接 ELF バイナリとしてコンパイルして `stage1` を生成、さらに `stage1` が `stage2` を生成し、`stage2` と `stage3` のビット単位完全一致（Fixed Point）を達成する。これにより、クリーンな Linux 環境において追加パッケージのインストールなしに ULisp 自身を再構築できる極限の独立性を確立する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 5 章 セルフホスティングブートストラップ連鎖と不動点検証)
  - [ULisp ポータブルビルドガイド](../../ulisp/docs/guide_portable_build.md)
- **関連 Issue**:
  - Issue 541: ブートストラップシード導入による高速ビルドパイプラインの構築
  - Issue 579: 3-Stage Bootstrap の固定点（Fixed-Point）自動検証プロトコルの確立
  - Issue 605: bootstrap.sh におけるコンパイル失敗時の自動診断機能の導入
  - Issue 615: ビルドパイプラインからの GCC 呼出し排除と GNU as / ld 直接駆動への移行
  - Issue 616: Scheme ネイティブ x86-64 マシン語エンコーダおよび ELF64 実行可能バイナリ直接出力バックエンドの実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (外部ツール非依存モード `--pure-self-host` の実装)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`bootstrap_pure` ターゲットの新設と依存性ルール改修)
- [ ] [ulisp/bin/ulisp-boot](../../ulisp/bin/ulisp-boot) (直接 ELF 出力能力を持つシードバイナリへの更新)
- [ ] [ulisp/docs/spec_pipeline.md](../../ulisp/docs/spec_pipeline.md) (完全自己完結型ブートストラップ仕様の追記)
- [ ] [ulisp/tests/test_pure_bootstrap.sh](../../ulisp/tests/test_pure_bootstrap.sh) (新規: 隔離環境・外部ツール無効化テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/617-establish-self-contained-bootstrap-chain-free-from-external-toolchains`

1. **直接 ELF 生成能力を持つシードバイナリの整備**:
   - Issue 616 で実装した Pass 144（Direct-to-ELF）を含めた ULisp コンパイラをビルドし、新たな `bin/ulisp-boot` としてコミット。
2. **純粋自己完結ブートストラップ連鎖の実装**:
   - `bootstrap.sh` において、`as` や `ld`、`gcc` を介さず、以下のようにバイナリを直接出力する連鎖を構築：
     - `bin/ulisp-boot --target-elf -o build/scheme-stage1 build/ulisp_core.scm`
     - `./build/scheme-stage1 --target-elf -o build/scheme-stage2 build/ulisp_core.scm`
     - `./build/scheme-stage2 --target-elf -o build/scheme-stage3 build/ulisp_core.scm`
3. **決定論的 ELF 生成と不動点（Fixed-Point）検証**:
   - 生成される ELF バイナリについて、タイムスタンプや非決定論的要素を排除し、`cmp -s build/scheme-stage2 build/scheme-stage3` による 100% bit-for-bit 一致を検証。
4. **外部ツール無効化テストの実施**:
   - `PATH` から `gcc`, `clang`, `as`, `ld`, `python` を隠蔽（空のダミーディレクトリを先頭に配置）した最小環境で、`make bootstrap_pure` が正常に完遂することをテスト。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] ホスト環境に `gcc`, `as`, `ld` が存在しない（または PATH から除外された）状態でも、`make bootstrap_pure` が完遂すること。
- [ ] `stage2` と `stage3` の ELF バイナリがビット単位で完全一致（bit-for-bit identical）すること。
- [ ] 生成された `scheme-stage2` が全ての標準テストスイート（`make test`）を正常に実行できること。
- [ ] ブートストラップ所要時間が従来の外部 as/ld 起動オーバーヘッド削減により大幅に短縮されること。

---
ID: 503
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] Implement AArch64 (ARM64) Backend via Low-Level IR for ULisp (ID: 503)

## 1. 概要 / Summary
Issue #502 で導入される低レベルIR（LIR: Low-level IR）をターゲット機械命令にマッピングし、**AArch64（ARM64 / Apple Silicon / AWS Graviton / Raspberry Pi）向けのネイティブコード生成バックエンド** を実装する。
Scheme コンパイラ自身がマルチアーキテクチャ対応し、x86-64 以外の主要 64bit アーキテクチャでもネイティブ実行およびセルフホスティングが可能となる基盤を確立する。
また、AArch64 バックエンド固有のパス単体テストおよびクロスコンパイル／QEMU 実行テストを整備する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §3 (言語機能と低レイヤコード生成仕様), §4 (フェーズ別コンパイラ設計), §6.1 (セルフホスティングパイプライン)
- **DSN-31**: §3.2 (Backend B: ULisp AOT Native Backend)
- **先行 Issue**: #502 (Introduce Low-Level IR and Decouple Backend Codegen)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/07_backend_aarch64.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_aarch64.scm): 新設する AArch64 アセンブリ生成バックエンド
- [ ] [ulisp/passes/08_driver.scm](file:///workspace/arxiv-security-papers/ulisp/passes/08_driver.scm): ターゲット切り替えフラグ（`--target=x86_64` / `--target=aarch64`）のサポート
- [ ] [ulisp/runtime_aarch64.s](file:///workspace/arxiv-security-papers/ulisp/runtime_aarch64.s): AArch64 向けランタイムエントリポイント
- [ ] [ulisp/tests/test_backend_aarch64.scm](file:///workspace/arxiv-security-papers/ulisp/tests/test_backend_aarch64.scm): AArch64 パス単体テスト
- [ ] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile): AArch64 ビルド・クロスコンパイルターゲットの追加
- [ ] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳の更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/503-implement-ulisp-aarch64-backend-via-lir`

1. **AArch64 レジスタ・ABI マッピング**:
   - 引数レジスタ: `x0`〜`x7`
   - ヒープポインタ（アロケータレジスタ）: `x19`（Callee-saved）
   - コンテキスト/クロージャポインタ: `x16` / `x17`
   - 一時・スクラッチレジスタ: `x9`〜`x15`
2. **LIR 命令の AArch64 命令への 1対1 マッピング**:
   - `%mov`: `mov dst, src`
   - `%load`: `ldr dst, [base, #offset]`
   - `%store`: `str src, [base, #offset]`
   - `%add`, `%sub`: `add dst, s1, s2`, `sub dst, s1, s2`
   - `%jump`: `b label`
   - `%tail-call`: 引数レジスタを設定して `br reg`
3. **テストの拡充**:
   - LIR から AArch64 アセンブリ文字列への出力一致テスト
   - `aarch64-linux-gnu-gcc` および `qemu-aarch64` を利用した実バイナリ実行テスト

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `07_backend_aarch64.scm` が LIR 命令列から有効な GNU AArch64 アセンブリを正しく生成すること。
- [ ] 固定引数、クロージャ、再帰、末尾呼び出し最適化（TCO）が AArch64 命令列で正常に展開されること。
- [ ] AArch64 向けのパス単体テストが整備され、100% PASS すること。
- [ ] すべての既存品質ゲート（`make check_format`, `make py_compile`）を通過すること。

---
ID: 507
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT] Implement MLisp: Endogenous Meta-Tracing JIT via Delimited Continuations and ULisp LIR (ID: 507)

## 1. 概要 / Summary
RPython（PyPy）が持つ「インタプリタを記述することで、コンパイラおよびメタトレーシング JIT（Meta-Tracing JIT）を備えた仮想マシンを自動生成する」パラダイムを、Scheme の真の言語能力（同図像性・第一級限定継続・マクロ・部分評価）によって極限まで昇華させた **MLisp（Meta-Lisp）ツールチェーン** を新規構築した。

外部から物理レジスタやメモリスタックを覗き見る従来の泥臭い外因的トレーシングを排し、**限定継続（`shift`/`reset`）によりインタプリタ自身が自己の将来の実行経路を S 式トレースとして直接キャプチャする「内因的メタトレーシング（Endogenous Meta-Tracing）」** を実現した。

既存の ULisp（[DSN-33](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)）の堅牢な基盤を壊さずに活用するため、独立ディレクトリ `mlisp/` として論理分離しつつ、ULisp の **Pass 6: Low-Level IR (LIR)** および **Pass 7: Multi-Backend Codegen (C99, AArch64, x86-64)** を共有する「モノレポ型ハイブリッド分離アーキテクチャ」を採用した。

全レイヤ（限定継続、内因的メタトレーサ、トレース部分評価、エスケープ解析付き仮想オブジェクト縮退、ULisp LIR 変換ブリッジ、JIT バッファマネージャ、サンプル VM）を **100% Pure Scheme で実装** した。

---

## 2. トレーサビリティ / Traceability
- **正典アーキテクチャ設計書**: [docs/designs/DSN-34-mlisp_endogenous_meta_tracing_jit_architecture_specification.md](../../designs/DSN-34-mlisp_endogenous_meta_tracing_jit_architecture_specification.md)
- **共有コンパイラ基盤仕様**: [docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **LIR 仕様書**: [ulisp/docs/lir_specification.md](../../../ulisp/docs/lir_specification.md)
- **先行 Issue**: #502 (Introduce Low-Level IR), #504 (Portable C Backend via LIR), #503 (AArch64 Backend via LIR)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [docs/designs/DSN-34-mlisp_endogenous_meta_tracing_jit_architecture_specification.md](../../designs/DSN-34-mlisp_endogenous_meta_tracing_jit_architecture_specification.md): アーキテクチャ設計書
- [x] [docs/issues/closed/507-implement-mlisp-endogenous-meta-tracing-jit.md](507-implement-mlisp-endogenous-meta-tracing-jit.md): 本 Issue 仕様書
- [x] [docs/issues/README.md](../README.md): Issue 台帳の更新
- [x] `mlisp/`: 新設された独立サブシステム (100% Pure Scheme)
  - [x] `mlisp/core/delimcc.scm`: 限定継続（`shift`/`reset`）コアプリミティブ (Pure Scheme)
  - [x] `mlisp/tracer/tracer.scm`: 内因的 S 式トレース抽出器 & `jit-merge-point` (Pure Scheme)
  - [x] `mlisp/optimizer/pe.scm`: トレース部分評価・ディスパッチ消去 (Pure Scheme)
  - [x] `mlisp/optimizer/virtuals.scm`: 仮想オブジェクト縮退・エスケープ解析 (Pure Scheme)
  - [x] `mlisp/bridge/to_lir.scm`: トレースから ULisp LIR へのアダプタ (Pure Scheme)
  - [x] `mlisp/runtime/jit_buffer.scm`: Pure Scheme W^X メモリ保護 & JIT ディスパッチャ
  - [x] `mlisp/examples/tiny_vm.scm`: スタック型バイトコード VM サンプル (Pure Scheme)
  - [x] `mlisp/examples/scheme_eval.scm`: メタサーキュラー Scheme 評価器 (Pure Scheme)
  - [x] `mlisp/tests/test_delimcc.scm`: 限定継続単体テストスイート
  - [x] `mlisp/tests/test_tracer.scm`: 内因的メタトレーサ単体テストスイート
  - [x] `mlisp/tests/test_optimizer.scm`: トレースオプティマイザ単体テストスイート
  - [x] `mlisp/tests/test_bridge.scm`: LIR ブリッジ & JIT ランタイム単体テストスイート
  - [x] `mlisp/tests/test_examples.scm`: サンプル VM & E2E JIT 検証テストスイート
  - [x] `mlisp/Makefile`: MLisp 独立ビルド・テストランナー

---

## 4. 実装方針 / Implementation Plan (Phase 1 〜 Phase 5)

Target Branch: `feat/507-implement-mlisp-endogenous-meta-tracing-jit`

### Phase 1: 基盤整備 & 限定継続（`shift`/`reset`）コアの実装
1. `mlisp/` ディレクトリ新設および `mlisp/Makefile` 整備。
2. `mlisp/core/delimcc.scm` における限定継続プリミティブ（`reset`, `shift`）の実装。
3. `mlisp/tests/test_delimcc.scm` による制御フロー脱出・再入の厳密な単体テスト（全ケース PASS）。

### Phase 2: 内因的 S 式メタトレーサ & ループフックの実装
1. `(jit-merge-point pc env ...)` マーカーの実装とホットループ検出器。
2. ループ 1 周期分の実行経路を副作用なく S 式命令列（`%trace ...`）としてキャプチャする内因的レコーダ。

### Phase 3: トレースオプティマイザ & 仮想オブジェクト縮退の実装
1. 部分評価器によるバイトコードディスパッチや環境ルックアップの完全消去。
2. エスケープ解析による中間ペア（`cons`）や一時クロージャのヒープ確保消去（$O(0)$ 縮退）。

### Phase 4: ULisp LIR ブリッジ & JIT 実行ランタイム
1. 最適化トレースから ULisp の `%lir-program`（Pass 6）への変換アダプタ。
2. ULisp C99 バックエンド（Pass 7b）と連携し、メモリ上で即座に機械語（または動的リンク）として実行。
3. ガード失敗時の安全なインタプリタ復帰（Bailout / Deoptimization）。

### Phase 5: サンプル VM 実証 & 単一バイナリ出力
1. サンプル言語処理系（スタックマシン型 VM / Scheme 評価器）での JIT 動作確認。
2. スタンドアロンな単一自己完結バイナリ（`build/scheme-jit`）のビルド検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] DSN-34 アーキテクチャ設計書が承認・登録されていること。
- [x] `mlisp/core/delimcc.scm` で限定継続（`shift`/`reset`）が正しく動作し、`make -C mlisp test` で全テストが PASS すること。
- [x] `make check_format` および `make py_compile` が 100% エラーゼロであること。
- [x] ドキュメント内のリンクがすべて相対パスで記述されていること（絶対パス 0 件）。

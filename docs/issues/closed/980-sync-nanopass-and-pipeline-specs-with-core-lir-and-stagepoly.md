---
ID: 980
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] Nanopass 言語仕様書自動生成（spec_nanopass.md）の更新と spec_pipeline.md（Scheme/C99 の L_lir_core 合流・部分評価経路）の実態同期 (ID: 980)

## 1. 概要 / Summary

ULisp コンパイラの仕様書と現行実装の間で発生していた以下の乖離・確認事項（項番 4・項番 6）を解消した。

1. **`spec_nanopass.md`（自動生成）の入力追加と再生成（項番 4 前半）**:
   - [Makefile](../../../ulisp/Makefile#L186-L190) の `docs_nanopass` ターゲットが `frontend_c/c_lang.scm`（`L_c_ast` / `L_c_typed`）を読み込んでおらず、さらに [generate_nanopass_docs.scm](../../../ulisp/tools/generate_nanopass_docs.scm) のゼロ引数 `main` 定義が Gauche（`gosh`）の `(main args)` フックと衝突して実行失敗していた問題を是正した。
   - [spec_nanopass.md](../../../ulisp/docs/spec_nanopass.md) を再生成し、`L_cst`・`L_src`・`L_core`・`L_anf`・`L_lifted`・`L-StagePoly`・`L-Residual-ANF`・`L_lir_core`・`L_lir_managed`・`L_lir_raw`・`L_lir_canonical`・`L_asm_x86`・`L_asm_aarch64`・`L_c_ast`・`L_c_typed` の全 15 言語の継承図と詳細定義を反映した。
2. **`spec_pipeline.md` §2・§3.1 の実態同期（項番 4 後半）**:
   - [spec_pipeline.md](../../../ulisp/docs/spec_pipeline.md) から実装上存在しない `L_lir_ssa` と `L_ast_c99` を除去し、Scheme フロントエンド（`L_lifted -> Pass 130 -> L_lir_managed -> Pass 131 -> L_lir_core`）と C99 フロントエンド（`L_c_ast -> L_c_typed -> lower_to_lir -> L_lir_core`）が **`L_lir_core` で合流する構成**およびレガシー階層（`L_lir_raw -> L_lir_canonical`）の位置付けへ刷新した。
3. **部分評価系統（`pass-075-stage-poly-lower` / `L-StagePoly` / `L-Residual-ANF`）の明文化（項番 6）**:
   - `Pass 070 (L_anf)` 直後の `Pass 075`（メタ構文含有時のみ `L-StagePoly -> L-Residual-ANF` を実行し通常コードは `L_anf` 素通し）および [130_lir.scm](../../../ulisp/lir/130_lir.scm#L539) の `L-Residual-ANF -> LIR` 直接 Lowering ブリッジを [spec_pipeline.md](../../../ulisp/docs/spec_pipeline.md) §1・§2・§3.1 に明記した。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [spec_pipeline.md](../../../ulisp/docs/spec_pipeline.md)
  - [spec_nanopass.md](../../../ulisp/docs/spec_nanopass.md)
  - [spec_lir.md](../../../ulisp/docs/spec_lir.md)
  - [generate_nanopass_docs.scm](../../../ulisp/tools/generate_nanopass_docs.scm)
  - [Makefile](../../../ulisp/Makefile)
  - [frontend_lang.scm](../../../ulisp/frontend/frontend_lang.scm)
  - [c_lang.scm](../../../ulisp/frontend_c/c_lang.scm)
  - [lir_lang.scm](../../../ulisp/lir/lir_lang.scm)
  - [979-tighten-lir-language-compatibility-and-reconcile-lir-dialects.md](979-tighten-lir-language-compatibility-and-reconcile-lir-dialects.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [Makefile](../../../ulisp/Makefile) (`docs_nanopass` ターゲットへの `frontend_c/c_lang.scm` 追加)
- [x] [generate_nanopass_docs.scm](../../../ulisp/tools/generate_nanopass_docs.scm) (エントリ関数 `generate-nanopass-docs-main` 化・ヘッダ更新)
- [x] [spec_nanopass.md](../../../ulisp/docs/spec_nanopass.md) (`make -C ulisp docs_nanopass` による再生成：全 15 言語)
- [x] [spec_pipeline.md](../../../ulisp/docs/spec_pipeline.md) (§1 全体図、§2 Pass 035/075/131/133 追加、§3.1 `L_lir_core` 合流図刷新、§3.2 リンク修正)
- [x] [spec_lir.md](../../../ulisp/docs/spec_lir.md) (`L_lir_core` / `L_lir_managed` / `validate-core-lir` とレガシー `L_lir_canonical` 記載整合)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `docs/980-sync-nanopass-and-pipeline-specs`

### Phase 1: `docs_nanopass` 生成パイプライン修正と `spec_nanopass.md` 再生成
1. [Makefile](../../../ulisp/Makefile#L186-L190) の `docs_nanopass` で `frontend_c/c_lang.scm` を入力に追加し、C99 中間言語（`L_c_ast`・`L_c_typed`）をドキュメント生成時にロードするようにした。
2. [generate_nanopass_docs.scm](../../../ulisp/tools/generate_nanopass_docs.scm) のゼロ引数 `main` を `generate-nanopass-docs-main` に改名して Gauche の `(main args)` 呼び出し衝突を解消し、`make -C ulisp docs_nanopass` で [spec_nanopass.md](../../../ulisp/docs/spec_nanopass.md) を再生成した。

### Phase 2: `spec_pipeline.md` §1・§2・§3.1 の実態同期と部分評価系統の明文化（項番 6）
1. [spec_pipeline.md](../../../ulisp/docs/spec_pipeline.md) §1 および §2 に `Pass 035`・`Pass 075`（`L-StagePoly -> L-Residual-ANF`、および `130_lir.scm` 直接 Lowering 経路）・`Pass 131`（`L_lir_managed -> L_lir_core`）・`Pass 133` を追記した。
2. §3.1 から未存在言語（`L_lir_ssa`, `L_ast_c99`）および旧 `L_lir_raw -> L_lir_ssa -> L_lir_canonical` 表記を除去し、Scheme / C99 両経路の `L_lir_core` 合流図および各層詳細へ更新した。
3. §3.2 内の既存クローズ済み Issue リンク（#594〜#600 およびドキュメント構成案内リンク）を有効な相対パスへ修正した。

### Phase 3: リンク・記載整合性の検証
1. [spec_lir.md](../../../ulisp/docs/spec_lir.md) §1・§5 を `L_lir_core` / `L_lir_managed` および Issue #979 の契約整合に合わせて更新した。
2. 更新対象ドキュメント全体に対し、絶対パス 0 件・相対リンク切れ 0 件・`make -C ulisp lint_sexpr`・`make check_format && make static_analysis` 全 PASS を確認した。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `make -C ulisp docs_nanopass` がエラーなく完了し、[spec_nanopass.md](../../../ulisp/docs/spec_nanopass.md) に `L_lir_core`・`L_lir_managed`・`L_c_ast`・`L_c_typed`・`L-StagePoly`・`L-Residual-ANF` がすべて出力されていること。
- [x] [spec_pipeline.md](../../../ulisp/docs/spec_pipeline.md) から未存在言語（`L_lir_ssa`・`L_ast_c99`）が完全に除去され、Scheme / C99 の `L_lir_core` 合流図および `pass-075-stage-poly-lower` の接続仕様が明記されていること。
- [x] 更新した Markdown ファイル群に絶対パスが含まれず、全相対リンクが有効であること。

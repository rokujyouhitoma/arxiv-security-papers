---
ID: 980
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] Nanopass 言語仕様書自動生成（spec_nanopass.md）の更新と spec_pipeline.md（Scheme/C99 の L_lir_core 合流・部分評価経路）の実態同期 (ID: 980)

## 1. 概要 / Summary

ULisp コンパイラの仕様書と現行実装の間で発生している以下の乖離・確認事項（項番 4・項番 6）を解消する。

1. **`spec_nanopass.md`（自動生成）の入力不足と未再生成（項番 4 前半）**:
   - [Makefile](../../ulisp/Makefile#L186-L190) の `docs_nanopass` ターゲットは `build/compiler_passes.scm` と [generate_nanopass_docs.scm](../../ulisp/tools/generate_nanopass_docs.scm) のみを連結して実行しているため、C99 言語定義を含む `ulisp/frontend_c/c_lang.scm`（`L_c_ast` / `L_c_typed`）がロード対象に入っていない。
   - また [spec_nanopass.md](../../ulisp/docs/spec_nanopass.md) が古いままのため、`L_lir_core`・`L_lir_managed`（[lir_lang.scm](../../ulisp/lir/lir_lang.scm)）、`L-StagePoly`・`L-Residual-ANF`（[frontend_lang.scm](../../ulisp/frontend/frontend_lang.scm)）、および `L_c_ast`・`L_c_typed` が継承図・詳細一覧に掲載されていない。
2. **`spec_pipeline.md` §3.1 の実態乖離（項番 4 後半）**:
   - [spec_pipeline.md](../../ulisp/docs/spec_pipeline.md#L230-L237) に実装上存在しない `L_lir_ssa` と `L_ast_c99` が記載され、LIR 層の遷移が `raw → ssa → canonical` となっている。
   - 実際のパイプラインに合わせて、Scheme フロントエンドと C99 フロントエンドが **`L_lir_core` で合流する現行構成**へ図表と説明を書き換える必要がある。
3. **部分評価系統（`pass-075-stage-poly-lower` / `L-StagePoly` / `L-Residual-ANF`）の接続仕様の明文化（項番 6）**:
   - [pass_manager.scm](../../ulisp/compiler/pass_manager.scm#L1551-L1556) 上で `pass-075-stage-poly-lower`（`L-StagePoly -> L-Residual-ANF`）が `pass-070-anf` 直後に組み込まれており、ステージメタ構文含有時は `stage-poly-lower-all` を実行し、通常コードでは `L_anf` を素通しする。また [130_lir.scm](../../ulisp/lir/130_lir.scm#L539) に `L-Residual-ANF` を直接 LIR へ落とすブリッジが存在する。これらを仕様書へ正確に反映する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [spec_pipeline.md](../../ulisp/docs/spec_pipeline.md)
  - [spec_nanopass.md](../../ulisp/docs/spec_nanopass.md)
  - [spec_lir.md](../../ulisp/docs/spec_lir.md)
  - [generate_nanopass_docs.scm](../../ulisp/tools/generate_nanopass_docs.scm)
  - [Makefile](../../ulisp/Makefile)
  - [frontend_lang.scm](../../ulisp/frontend/frontend_lang.scm)
  - [c_lang.scm](../../ulisp/frontend_c/c_lang.scm)
  - [lir_lang.scm](../../ulisp/lir/lir_lang.scm)
  - [979-tighten-lir-language-compatibility-and-reconcile-lir-dialects.md](closed/979-tighten-lir-language-compatibility-and-reconcile-lir-dialects.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [Makefile](../../ulisp/Makefile) (`docs_nanopass` ターゲットへの `frontend_c/c_lang.scm` 追加)
- [ ] [generate_nanopass_docs.scm](../../ulisp/tools/generate_nanopass_docs.scm) (全言語メタ情報出力・Mermaid 継承図生成確認)
- [ ] [spec_nanopass.md](../../ulisp/docs/spec_nanopass.md) (`make -C ulisp docs_nanopass` による再生成)
- [ ] [spec_pipeline.md](../../ulisp/docs/spec_pipeline.md) (§2 Pass 075 / Pass 131 追加、§3.1 遷移・Mermaid 合流図刷新)
- [ ] [spec_lir.md](../../ulisp/docs/spec_lir.md) (`L_lir_core` / `L_lir_managed` / `L_lir_canonical` 記載整合確認)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `docs/980-sync-nanopass-and-pipeline-specs`

### Phase 1: `docs_nanopass` 生成パイプライン修正と `spec_nanopass.md` 再生成
1. [Makefile](../../ulisp/Makefile#L186-L190) の `docs_nanopass` ターゲットで、`build/compiler_passes.scm` に加えて `frontend_c/c_lang.scm` を読み込んで `build/generate_docs_runner.scm` を構築するよう修正する（`c_lang.scm` が単独で評価可能か、必要なヘルパー依存の有無も事前確認する）。
2. [generate_nanopass_docs.scm](../../ulisp/tools/generate_nanopass_docs.scm) が `nanopass-get-all-languages` から全登録言語（`L_cst`, `L_src`, `L_core`, `L_anf`, `L_lifted`, `L-StagePoly`, `L-Residual-ANF`, `L_lir_core`, `L_lir_managed`, `L_lir_canonical`, `L_asm_x86`, `L_asm_aarch64`, `L_c_ast`, `L_c_typed` 等）を取得し、ハイフン含む言語名でも有効な Mermaid ノード ID/エッジとして出力できることを確認する（必要なら Mermaid ノード ID サニタイズを追加）。
3. `make -C ulisp docs_nanopass` を実行して [spec_nanopass.md](../../ulisp/docs/spec_nanopass.md) を再生成する。

### Phase 2: `spec_pipeline.md` §2・§3.1 の実態同期と部分評価系統の明文化（項番 6）
1. [spec_pipeline.md](../../ulisp/docs/spec_pipeline.md) §2 に `Pass 075`（`pass-075-stage-poly-lower`: `L-StagePoly -> L-Residual-ANF`、および非メタ構文時の `L_anf` 素通し）と `Pass 131`（`pass-131-lower-managed-dialect`: `L_lir_managed -> L_lir_core`）の仕様を追記し、既存の `130_lir.scm` の `L-Residual-ANF -> LIR` ブリッジ経路も整理して記述する。
2. §3.1 から未存在言語（`L_lir_ssa`、`L_ast_c99`）および旧 `L_lir_raw -> L_lir_ssa -> L_lir_canonical` 表記を削除し、以下の合流構成を表す Mermaid 図と階層表へ刷新する:
   - **Scheme 経路**: `L_cst -> L_src -> L_core -> L_anf`（ステージ構文時は `L-StagePoly -> Pass 075 -> L-Residual-ANF`）`-> L_lifted -> Pass 130 -> L_lir_managed -> Pass 131 -> L_lir_core`
   - **C99 経路**: `L_c_ast -> L_c_typed -> lower_to_lir -> L_lir_core`
   - **共通 LIR・Backend 経路**: `L_lir_core -> Pass 128/132/133 -> L_lir_canonical -> L_asm_x86 / L_asm_aarch64 / ANSI C99`

### Phase 3: リンク・記載整合性の検証
1. [spec_lir.md](../../ulisp/docs/spec_lir.md) と [spec_pipeline.md](../../ulisp/docs/spec_pipeline.md) で LIR 方言名が矛盾しないことを確認する。
2. 更新対象ドキュメント全体に対し、絶対パス 0 件・相対リンク切れ 0 件・`docs_nanopass` 冪等性を確認する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `make -C ulisp docs_nanopass` がエラーなく完了し、[spec_nanopass.md](../../ulisp/docs/spec_nanopass.md) に `L_lir_core`・`L_lir_managed`・`L_c_ast`・`L_c_typed`・`L-StagePoly`・`L-Residual-ANF` がすべて出力されていること。
- [ ] [spec_pipeline.md](../../ulisp/docs/spec_pipeline.md) から未存在言語（`L_lir_ssa`・`L_ast_c99`）が完全に除去され、Scheme / C99 の `L_lir_core` 合流図および `pass-075-stage-poly-lower` の接続仕様が明記されていること。
- [ ] 更新した Markdown ファイル群に絶対パスが含まれず、全相対リンクが有効であること。

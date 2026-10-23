---
ID: 590
種別: Feature
優先度: High
ステータス: Closed (Done)
---

# [FEAT/ENH] ULisp コンパイラ層の物理分離（Frontend/Nanopass メタコンパイラ層と Backend/低レベルコード生成層の分離） (ID: 590)

## 1. 概要 / Summary

現在、`ulisp/passes/` 直下に Pass 010 から Pass 160 までの全 33 パスが平坦（フラット）に配置されており、高水準 S 式変換（マクロ・脱糖・CPS/ANF・型推論・クロージャ変換等）と、中間表現 LIR の構築・最適化、および低水準マシン語/Cコード生成処理の境界がディレクトリ構造上で曖昧になっていた。

本 Issue では、Issue 589 で確立された Canonical LIR（正典低水準中間表現）境界を軸に、ULisp コンパイラの内部モジュール配置およびパイプラインを以下の 3 つの独立した物理ディレクトリ層へ再編・分離した：

1. **Frontend 層 (`ulisp/frontend/`)**:
   - Scheme ソースコードを入力とし、S 式 AST の高水準意味論変換（Nanopass DSL 展開、マクロ展開、脱糖、静的解析、ANF、型推論、クロージャ変換、エスケープ解析）を担当する。
2. **LIR / Middle-End 層 (`ulisp/lir/`)**:
   - 高水準 AST から Canonical LIR への低レベル化、ABI 呼出展開、ファーストクラス継続・dynamic-wind、ランタイム・プリミティブ選択、Safepoint スタックマップ、Braun SSA 変換、および LIR 不変条件バリデータ（LIR Verifier）を担当する。
3. **Backend 層 (`ulisp/backend/`)**:
   - Canonical LIR AST のみを入力とし、ターゲット依存のマシン語（x86-64 / AArch64 GNU Asm）および C99 コード生成、世代別コピー GC / アロケータランタイム、およびフリースタンディング実行基盤を担当する。

これにより、高水準言語仕様の拡張（R7RS-large 対応等）や Nanopass DSL の進化と、ターゲット固有のハードウェア最適化（レジスタ割付、SIMD、JIT エンジン等）が互いに干渉せず疎結合に発展できる堅牢なコンパイラアーキテクチャを実現した。

---

## 2. トレーサビリティ / Traceability

- **アーキテクチャ仕様**:
  - DSN-33 コンパイラアーキテクチャ仕様書: [DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ulisp/docs/pipeline_architecture.md](../../ulisp/docs/pipeline_architecture.md)
  - [ulisp/docs/lir_specification.md](../../ulisp/docs/lir_specification.md)
- **関連 Issue**:
  - [closed/589-establish-canonical-lir-specification-and-boundary-validator.md](closed/589-establish-canonical-lir-specification-and-boundary-validator.md) (Canonical LIR 仕様とバリデータ導入による境界確立)
  - [closed/553-refactor-ulisp-passes-and-compiler-architecture.md](closed/553-refactor-ulisp-passes-and-compiler-architecture.md) (compiler 基盤切り出しと 3 桁ナンバリング)
  - [closed/587-extract-dsl-expansion-pass-before-macro-expander.md](closed/587-extract-dsl-expansion-pass-before-macro-expander.md) (Pass 015 Nanopass DSL 先行展開)
  - [closed/583-nanopass-decomposition-of-lir-pass-130.md](closed/583-nanopass-decomposition-of-lir-pass-130.md) (LIR パスの機能責務別ナノパス分割)
  - [closed/579-establish-3-stage-bootstrap-fixed-point-verification-protocol.md](closed/579-establish-3-stage-bootstrap-fixed-point-verification-protocol.md) (3-Stage Bootstrap 固定点自動検証プロトコル)
  - [591-hierarchical-compiler-driver-and-test-suites.md](591-hierarchical-compiler-driver-and-test-suites.md) (コンパイラドライバおよびテストスイートの階層化)

---

## 3. セキュリティ・脅威分析 / Threat Analysis & Security Considerations

- **脅威ベクトル 1: レイヤード境界違反・逆流依存（Leaky Abstractions & Layer Inversion）によるターゲット非依存性の破壊**
  - フロントエンドパス（Nanopass）がバックエンドの低レベルアセンブリ命令やターゲット依存のレジスタ名（`%rax`, `%r15` 等）を直接埋め込む、あるいはバックエンドがフロントエンドの高水準構文（`lambda`, `letrec`, `syntax-rules` 等）を直接参照してしまうことによるモジュール完全性の破壊。
  - **対策**: フロントエンドの出力は Canonical LIR AST のみに限定し、バックエンドは `validate-lir` で検証済みの LIR AST のみを消費するクリーンな単方向データフロー（Scheme $\to$ AST $\to$ LIR $\to$ Asm/C）を維持する。
- **脅威ベクトル 2: ビルドパイプライン（Makefile / bootstrap.sh）における結合順序の乱れ・循環依存によるブートストラップ固定点（Fixed-Point）破損**
  - パスの物理配置変更に伴い、Makefile でのファイル結合順序（`cat $(PASSES) > compiler.scm`）が意図せず入れ替わった場合、前方参照エラー、未束縛マクロ、あるいは潜在的な構文エラーが発生し、3-stage fixed-point bootstrap が破綻する。
  - **対策**: Makefile の変数定義を `FRONTEND_PASSES`, `LIR_PASSES`, `BACKEND_PASSES` の階層別に厳密にグループ化し、結合順序（Pass 010 $\to$ 160）を不変に保つ。ブートストラップ検証（`make bootstrap`）でバイトレベルの固定点完全一致（Diff 0）を強制。
- **脅威ベクトル 3: 内部非公開関数・グローバル状態のレイヤー間リークによる予期しない副作用・メモリ破壊**
  - フロントエンドの解析パス（例: `040_analysis.scm`, `080_annotator.scm`）が生成した一時的なグローバルキャッシュやメタデータが、バックエンドのコード生成処理において予期せず参照・上書きされ、不正な命令選択やレジスタ破壊を招く。
  - **対策**: LIR への変換（Pass 130）においてすべてのフロントエンド解析情報（型注釈、エスケープ情報、クロージャ環境）を Canonical LIR の明示的なアトリビュートまたは構造体へ完結させ、グローバル状態を介した隠蔽されたデータ受け渡しを排除する。
- **脅威ベクトル 4: テストスイートおよびドキュメントのリンク破損による回帰見逃し・品質ゲート空洞化**
  - 既存のテストスクリプト（`NANOPASS_TESTS`、個別パステスト等）や仕様書ドキュメントが旧 `passes/` パスを参照したまま孤立し、テストがスキップされたり偽陽性/偽陰性が発生する。
  - **対策**: `ulisp/Makefile` 内の全テストターゲット（`NANOPASS_TESTS`, `test_passes`, 各種個別ランナー）、`tests/` スクリプト、および仕様書（`pipeline_architecture.md`, `r7rs_specification_compliance.md` 等）の参照パスを一括同期更新する。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

### A. 新設・配置変更ディレクトリ及びファイル群

- [x] `ulisp/frontend/`（新設: 高水準言語処理 Nanopass 群 18 ファイル）
  - `010_library.scm`（R7RS ライブラリ構文脱糖）
  - `015_dsl_expander.scm`（Nanopass DSL 先行展開）
  - `020_macro_expander.scm`（衛生的マクロ展開器）
  - `025_top_level.scm`（トップレベル定義巻き上げ）
  - `026_desugar_constructors.scm`（コンストラクタ脱糖）
  - `027_desugar_conditionals.scm`（条件分岐脱糖）
  - `028_desugar_bindings.scm`（束縛構文脱糖）
  - `029_desugar_dynamic.scm`（動的環境・例外構文脱糖）
  - `030_desugar.scm`（統合脱糖コア）
  - `040_analysis.scm`（自由変数・静的スコープ解析）
  - `050_cp0.scm`（定数畳み込み・ソース最適化）
  - `060_lvn.scm`（局所値番号付け LVN）
  - `070_anf.scm`（A-Normal Form 正規化）
  - `080_annotator.scm`（抽象解釈型推論器）
  - `090_rtyper.scm`（RType 推論・アンボクシング）
  - `100_contify.scm`（Contification 既知関数最適化）
  - `110_closure_convert.scm`（明示的クロージャ変換）
  - `120_alias_escape.scm`（TBAA・エスケープ解析）
- [x] `ulisp/lir/`（新設: 共通低水準中間表現 LIR 群 11 ファイル）
  - `lir_verifier.scm`（Canonical LIR 不変条件バリデータ - 旧 `compiler/lir_verifier.scm` から移管）
  - `123_lir_closures.scm`（クロージャ割当・タプル低レベル化）
  - `124_lir_call_abi.scm`（関数呼出 ABI 規約低レベル化）
  - `125_lir_continuation.scm`（継続・スタック退避復元）
  - `126_lir_control.scm`（制御フロー・ジャンプ低レベル化）
  - `127_lir_runtime.scm`（ランタイム支援機能低レベル化）
  - `128_lir_branch_fusion.scm`（分岐・フラグ融合）
  - `129_lir_primitives.scm`（コアプリミティブ命令選択）
  - `130_lir.scm`（LIR プログラム生成・メイン制御）
  - `131_lir_safepoint.scm`（GC Safepoint スタックマップ生成）
  - `132_lir_braun_ssa.scm`（Braun 法オンザフライ SSA 構築）
- [x] `ulisp/backend/`（新設: 低レベルコード生成層 5 ファイル）
  - `140_backend_x86_64.scm`（x86-64 GNU Asm コード生成）
  - `141_backend_x86_gc.scm`（x86 世代別コピー GC ルーチン）
  - `142_backend_x86_freestanding.scm`（x86 フリースタンディングベアメタルランタイム）
  - `150_backend_aarch64.scm`（AArch64 GNU Asm コード生成）
  - `160_backend_c.scm`（ANSI C99 コード生成）
- [x] `ulisp/passes/`（全 33 ファイル移管後にディレクトリを完全削除）

### B. コンパイラ基盤およびドライバ

- [x] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm)（パイプライン手続きを `compile-to-lir` と `compile-backend` の明示的 2 段階関数にリファクタリング）
- [x] [ulisp/compiler/verifier.scm](../../ulisp/compiler/verifier.scm)（`lir_verifier.scm` の移管に伴う呼び出し整合性の維持）

### C. ビルドシステムおよびテスト連携

- [x] [ulisp/Makefile](../../ulisp/Makefile)
  - `FRONTEND_PASSES`, `LIR_PASSES`, `BACKEND_PASSES` の分割定義
  - `PASSES_LIB` および `PASSES` 結合順序の厳密化
  - `NANOPASS_TESTS` および個別パステストランナーの参照パス更新
  - ビルド中間生成物ターゲットの整合化

### D. ドキュメントおよびリンク仕様

- [x] [ulisp/docs/pipeline_architecture.md](../../ulisp/docs/pipeline_architecture.md)（3 層物理構造を反映したレイヤード Mermaid パイプライン図および各パスパス名の更新）
- [x] [ulisp/docs/lir_specification.md](../../ulisp/docs/lir_specification.md)（LIR Verifier 所在地の更新）
- [x] [ulisp/docs/README.md](../../ulisp/docs/README.md)（リポジトリ構成ツリーの更新）
- [x] [ulisp/docs/r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md)（各パスへの相対リンクの更新）
- [x] [ulisp/docs/PORTABLE_BUILD_GUIDE.md](../../ulisp/docs/PORTABLE_BUILD_GUIDE.md)（パス参照の更新）

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/590-physical-layer-separation-of-frontend-and-backend`

### Step 1: ディレクトリ構造の物理作成とパスファイルの移管
1. `ulisp/frontend/`, `ulisp/lir/`, `ulisp/backend/` の 3 ディレクトリを作成。
2. `ulisp/passes/` 内の全 33 ファイルを各新設ディレクトリへ移動：
   - Pass 010〜120（計 18 ファイル） $\to$ `ulisp/frontend/`
   - Pass 123〜132（計 10 ファイル） $\to$ `ulisp/lir/`
   - Pass 140〜160（計 5 ファイル） $\to$ `ulisp/backend/`
3. `ulisp/compiler/lir_verifier.scm` を `ulisp/lir/lir_verifier.scm` へ移動し、LIR 仕様・検証ロジックを LIR 層へ集約。
4. 旧 `ulisp/passes/` ディレクトリを削除。

### Step 2: コンパイラドライバの 2 層手続き化 (`ulisp/compiler/driver.scm`)
1. 単一の巨大な `let*` 実行ブロックを以下の 2 つの明示的手続きに分割：
   - `(compile-to-lir forms verify-mode trace-mode)`: forms を入力とし、Pass 010 から Pass 130/131/132 まで直列変換を実行し、`verify-mode` 時に `validate-lir` を呼び出し、検証済み Canonical LIR AST を返却。
   - `(compile-backend lir-ast target gc-mode)`: LIR AST を受け取り、ターゲット（`'c`, `'aarch64`, `'x86_64`）に応じたコード生成ルーチン（`emit-c`, `emit-aarch64`, `emit-x86-64`）を呼び出し。
2. これにより、Issue 591 での `(!target lir)` 出力分岐追加が極めて自然に行える疎結合ドライバ構造を確立。

### Step 3: `ulisp/Makefile` のビルドパイプライン再編
1. パス変数を 3 層に分割定義：
   ```makefile
   FRONTEND_PASSES = frontend/010_library.scm \
                     frontend/015_dsl_expander.scm \
                     ... \
                     frontend/120_alias_escape.scm

   LIR_PASSES = lir/lir_verifier.scm \
                lir/123_lir_closures.scm \
                ... \
                lir/132_lir_braun_ssa.scm

   BACKEND_PASSES = backend/140_backend_x86_64.scm \
                    backend/141_backend_x86_gc.scm \
                    ... \
                    backend/160_backend_c.scm

   PASSES_LIB = $(COMPILER_BASE) $(FRONTEND_PASSES) $(LIR_PASSES) $(BACKEND_PASSES)
   ```
2. `compiler.scm` および `build/compiler_passes.scm` のターゲット依存関係を更新。
3. `NANOPASS_TESTS`、`test_passes`、および各個別パステストターゲット内の `passes/` 参照パスを新設ディレクトリ構造に追従。

### Step 4: ドキュメントおよびリンクの網羅的同期
1. `ulisp/docs/pipeline_architecture.md`:
   - レイヤードアーキテクチャ図（Mermaid）を「Frontend (Pass 010〜120)」「LIR / Middle-End (Pass 123〜132)」「Backend (Pass 140〜160)」の 3 サブグラフで明確に区分。
   - 各パスの見出しおよびパス名記述（`frontend/`, `lir/`, `backend/`）を更新。
2. `ulisp/docs/README.md`, `r7rs_specification_compliance.md`, `lir_specification.md`, `PORTABLE_BUILD_GUIDE.md` 内の相対リンクを同期。

### Step 5: 全品質ゲートと固定点ブートストラップ検証
1. `make -C ulisp test_all_passes`（全 33 ナノパステスト）の PASS を確認。
2. `make -C ulisp test_c`（全 139 C バックエンドテスト）の PASS を確認。
3. `make -C ulisp test_nanopass`（Nanopass DSL ユニットテスト）の PASS を確認。
4. `make -C ulisp test_lir_verifier` の PASS を確認。
5. `./ulisp/bootstrap.sh`（または `make -C ulisp bootstrap`）を実行し、Stage 2 と Stage 3 の生成アセンブリ完全一致（Diff 0）によるブートストラップ固定点を検証。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/passes/` が全 33 ファイルの移管に伴い完全に解消され、`ulisp/frontend/`（18ファイル）、`ulisp/lir/`（11ファイル）、`ulisp/backend/`（5ファイル）に整然と配置されていること。
- [x] `ulisp/compiler/driver.scm` が `compile-to-lir` と `compile-backend` に構造分離され、フロントエンドとバックエンドの境界が手続きとして定義されていること。
- [x] `ulisp/Makefile` が階層別変数（`FRONTEND_PASSES`, `LIR_PASSES`, `BACKEND_PASSES`）に再編され、単一ファイル `compiler.scm` への結合が破綻なく動作すること。
- [x] `make -C ulisp test_all_passes`, `make -C ulisp test_nanopass`, `make -C ulisp test_lir_verifier` が 100% PASS すること。
- [x] `make -C ulisp test_c` が 100% PASS すること。
- [x] `make -C ulisp bootstrap` による 3 段階ブートストラップ固定点（Fixed-Point）検証が Diff ゼロで PASS すること。
- [x] `ulisp/docs/pipeline_architecture.md` および関連仕様書内の相対パスリンクがすべて正常に解決され、壊れたリンクがゼロであること。
- [x] OKF v0.2 品質基準およびプロジェクト規則に違反がないこと。

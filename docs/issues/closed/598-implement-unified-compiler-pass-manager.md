---
ID: 598
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] 統一 Pass Manager の導入によるパイプライン制御・最適化レベルスケジューリング・観測性の一元化 (ID: 598)

## 1. 概要 / Summary
ULisp コンパイラドライバおよびパイプライン実行において、約30におよぶ Nanopass / コンパイラパスが直列にハードコード接続されている現状を解消し、LLVM / GCC 相当の統一 **Pass Manager（パイプライン統御・最適化スケジューラ）** 基盤を導入する。

### 背景と課題:
1. **固定的な直列実行と最適化スケジューリングの欠如**:
   - 現在のコンパイラドライバ（`ulisp/compiler/driver.scm` 内の `compile-to-lir`）では、Pass 010 から Pass 133 までの 20 以上のパスが巨大な `let*` 式で一本道に直列結線されている。
   - `-O0`（最小限の高速コンパイル）、`-O1`（基本最適化）、`-O2`（高度最適化）などの最適化レベルに応じた動的なパスの有効化・無効化やパイプラインの組み替えが不可能となっている。
2. **パス間不変条件・前提依存関係の未検証**:
   - 各コンパイラパスは特定の中間不変条件（例: 「Pass 070 ANF 変換済みであること」「Pass 110 クロージャ変換済みであること」等）を前提として動作しているが、これらが明示的な前提条件（Prerequisites / Invariants）として宣言・検証されていない。
   - 開発者が実験的にパスをスキップまたは順序変更した場合に、暗黙の前提崩壊が下流パスで未定義動作やクラッシュとして発現するリスクがある。
3. **観測性・プロファイリング基盤の散乱と一括制御の欠如**:
   - パスごとの実行時間・メモリ消費量のプロファイリング（`--time-passes`）、特定パス前後の中間 AST ダンプ（`--dump-ir=<pass>` / `--print-after-all`）、AST 構造差分表示（`--trace-passes`）、および IR Verifier の検証フックが個別に散在しており、一元的なパイプライン観測ができない。
4. **セルフホスティング制約との両立**:
   - ULisp は自らをコンパイルするセルフホスティングコンパイラであり、可変長引数（dot/rest-arg lambda）の不使用、トップレベル `set!` の抑制（cons cell パターン）、およびポータブル Scheme（Gauche, ILisp/Python, ULisp AOT）での動作要件を満たす必要がある。

---

## 2. ガバナンス・専門エージェント多角レビュー / Governance & Reviews

本 Issue は、16専門エージェントフレームワークに基づき、以下の重点専門領域からの設計レビューを統合して策定された。

- **IT Specialist (Programming Languages & Compilers / PLC)**:
  - LLVM `PassManager` / GCC パス機構を参考にしつつ、Lisp/Scheme 特有の S 式 AST および Canonical LIR に最適化された階層的 Pass Descriptor 仕様を策定。
  - 各パスの入出力言語（`L_src`, `L_core`, `L_anf`, `L_lifted`, `L_lir_canonical`）とメタデータ（ID, 名前, カテゴリ, 最適化レベル, 前提条件）の宣言的登録APIを設計。
- **Systems Architect**:
  - Frontend（式木変換）、Middle-End（LIR 最適化）、Backend（コード生成）の 3 層物理境界（Issue #590）を尊重し、全層共通のパイプラインスケジューラとして `ulisp/compiler/pass_manager.scm` を `COMPILER_BASE` に配置。
- **Software Quality Assurance Specialist (SQA)**:
  - `-O0`, `-O1`, `-O2` の各最適化レベルにおけるセマンティクス等価性（Differential Testing）を保証するテストスイートを設計。
  - 任意パスの単体実行・スキップ時の前提条件整合性エラー検出を検証要件に定義。
- **Information Security Specialist**:
  - コンパイラ最適化・中間 IR 変換過程におけるコード置換の完全性と、悪意ある式変形・スタック破壊・無限再帰の未然防止を脅威分析（STRIDE / CWE）に基づき定義。

---

## 3. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/spec_pipeline.md)
  - [LIR 命令セット仕様書](../../ulisp/docs/spec_lir.md)
  - [Nanopass 言語仕様書](../../ulisp/docs/spec_nanopass.md)
- **関連 Issue**:
  - Issue #576: [軽量 IR Verifier（Pass Checker）フレームワークの導入による中間不変条件の機械的検証](closed/576-implement-lightweight-ir-verifier-framework.md)
  - Issue #586: [Nanopass Framework DSL Phase 4: パイプライン統御・AST Diff トレーサおよび不変条件 Verifier 自動フック統合](closed/586-nanopass-framework-phase4-pipeline-observability-diff-trace-and-verifier-hooks.md)
  - Issue #589: [LIR (Low-level IR) 仕様の厳格化と不変条件バリデータ導入によるフロントエンド・バックエンド境界の確立](closed/589-establish-canonical-lir-specification-and-boundary-validator.md)
  - Issue #590: [ULisp コンパイラ層の物理分離（Frontend/Nanopass メタコンパイラ層と Backend/低レベルコード生成層の分離）](closed/590-physical-layer-separation-of-frontend-and-backend.md)
  - Issue #591: [コンパイラドライバおよびテストスイートの階層化（LIR中間出力モード `--target-lir`）](closed/591-hierarchical-compiler-driver-and-test-suites.md)
  - Issue #593: [LIR層: define-language L_lir_canonical の導入と lir_verifier 宣言的統合](closed/593-define-lir-canonical-language-and-verifier-integration.md)
  - Issue #594: [Frontend層: define-language L_anf / L_lifted の導入と不変条件自動検証](closed/594-define-frontend-anf-and-lifted-languages.md)
  - Issue #597: [IR Verifier 基盤の共通化・階層分離と LIR 検証パフォーマンス最適化](closed/597-unify-ir-verifier-framework-and-optimize-lir-performance.md)
  - Issue #604: [コンパイラ実行時のコールスタック追跡（Call Stack Traceback）および未捕捉例外時のバックトレース表示機能の実装](closed/604-implement-call-stack-traceback-for-compiler-exceptions.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm) (新規: 統一 Pass Manager コア基盤)
- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (ドライバ連携・パイプライン起動ルーチン・CLI ディレクティブ拡張)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`COMPILER_BASE` への `compiler/pass_manager.scm` 追加およびテストターゲット定義)
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm) (Makefile 結合ターゲット自動再生成)
- [ ] [ulisp/tests/test_pass_manager.scm](../../ulisp/tests/test_pass_manager.scm) (新規: Pass Manager 単体テスト・依存関係・-Oフラグ・観測性テストスイート)
- [ ] [ulisp/docs/spec_pipeline.md](../../ulisp/docs/spec_pipeline.md) (Pass Manager アーキテクチャおよび最適化レベル仕様の追記)
- [ ] [docs/issues/598-implement-unified-compiler-pass-manager.md](598-implement-unified-compiler-pass-manager.md) (本設計書)
- [ ] [docs/issues/README.md](README.md) (Issue 管理台帳のステータス更新)

---

## 5. 脅威分析とセキュリティ要件 / Threat Modeling & Security Requirements

コンパイラの最適化パス順序の動的組み替えやスキップ機能は、生成されるネイティブコードの正当性と直結する。STRIDE および CWE 観点での脅威分析を実施し、防護要件を策定する。

| 脅威分類 (STRIDE / CWE) | 脅威シナリオ | 影響度 | 対策要件 (Mitigation Requirements) |
| :--- | :--- | :---: | :--- |
| **改ざん / 不正変形 (Tampering / CWE-697)** | 最適化パスの前提条件（例: ANF化されていない式へのLVN適用）が破綻し、式の評価順序や副作用が破壊された不正コードが生成される。 | High | パス登録時に前提条件（`prerequisites`）を明示し、パイプライン構築時に DAG 依存関係検証を自動実行。前提未達のパス実行を即時拒否・エラー報告する。 |
| **サービス拒否 (DoS / CWE-400 / CWE-674)** | 最適化レベルやユーザーループ指定によってパスの無限反復や循環依存が発生し、コンパイル処理がハングアップまたはスタックオーバーフローする。 | High | パイプラインは有向非巡回グラフ（DAG）順序のみを許容し、サイクル検出アルゴリズム（Cycle Detection）を組み込む。 |
| **情報漏洩・観測性破綻 (CWE-209 / CWE-532)** | `--dump-ir` や `--print-after-all` による AST ダンプ出力時に、巨大な式木や循環参照がコンソールを溢死させ、診断情報が取得不能になる。 | Medium | 既存の `truncate-expr-for-diagnostics` および安全な S 式シリアライザを適用し、深度制限付きフォーマット出力を行う。 |
| **未検証パス実行 (CWE-20)** | 未知の無効なパス名が CLI や `(!disable-pass ...)` から渡された場合、静かに無視されるか異常終了する。 | Low | パス識別子の完全検証を行い、類似シンボル推薦（`find-similar-symbols` - Issue #603）による親切な診断レポートを出力する。 |

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/598-implement-unified-compiler-pass-manager`

### 6.1 Pass Manager コアアーキテクチャ (`ulisp/compiler/pass_manager.scm`)
1. **Pass Descriptor データ構造**:
   - セルフホスティング Scheme 互換の固定長リスト形式でパス情報をカプセル化：
     ```scheme
     (make-pass-descriptor
       id               ; symbol: 一意パスID (例: 'pass-050-cp0)
       name             ; string: 可読パス名称 (例: "CP0 Source Optimizer")
       category         ; symbol: 'frontend | 'middle | 'backend
       opt-level        ; integer: 最小最適化レベル (0: 必須, 1: 基本, 2: 高度)
       pass-fn          ; procedure: (lambda (ast) -> ast)
       verifier-phase   ; symbol or #f: 自動実行する Verifier フェーズ名 (例: 'desugar, 'anf, 'lir)
       in-lang          ; symbol: 入力 Nanopass 言語名 (例: 'L_core, 'L_anf, '* )
       out-lang         ; symbol: 出力 Nanopass 言語名 (例: 'L_anf, 'L_lifted, '* )
       prerequisites    ; list of symbols: 必須前提パスID一覧 (例: '(pass-030-desugar))
       mandatory?       ; boolean: #t ならば -O0 でも絶対にスキップ不可 (Lowering/Codegen必須)
       )
     ```
2. **パスレジストリ (`*pass-registry*`)**:
   - 大域レジストリ（cons cell パターン）で全コンパイラパスを一元管理：
     - `(register-pass! descriptor)`: パス記述子の登録（重複 ID は上書き更新）
     - `(lookup-pass id)`: パス記述子の検索（未定義時はエラーまたは類似シンボル提示）
     - `(registered-passes)`: 登録済み全パスのリスト返却
     - `(reset-pass-registry!)`: レジストリの初期化
3. **標準パイプラインパスの全件登録**:
   - `init-default-pass-registry!` において、以下の全パスを公式登録：
     - `pass-010-library` (Frontend, Opt 0, Mandatory)
     - `pass-015-dsl-expander` (Frontend, Opt 0, Mandatory)
     - `pass-020-macro-expander` (Frontend, Opt 0, Mandatory)
     - `pass-025-top-level` (Frontend, Opt 0, Mandatory)
     - `pass-030-desugar` (Frontend, Opt 0, Mandatory, Verifier: `'desugar`)
     - `pass-050-cp0` (Frontend, Opt 1, Prerequisites: `'(pass-030-desugar)`)
     - `pass-060-lvn` (Frontend, Opt 2, Prerequisites: `'(pass-030-desugar)`)
     - `pass-070-anf` (Frontend, Opt 0, Mandatory, Verifier: `'anf`, Prerequisites: `'(pass-030-desugar)`)
     - `pass-080-annotator` (Frontend, Opt 2, Prerequisites: `'(pass-070-anf)`)
     - `pass-090-rtyper` (Frontend, Opt 2, Prerequisites: `'(pass-070-anf)`)
     - `pass-100-contify` (Frontend, Opt 2, Prerequisites: `'(pass-070-anf)`)
     - `pass-110-closure-convert` (Frontend, Opt 0, Mandatory, Verifier: `'closure`, Prerequisites: `'(pass-070-anf)`)
     - `pass-120-alias-escape` (Frontend, Opt 2, Prerequisites: `'(pass-110-closure-convert)`)
     - `pass-130-lir` (Middle, Opt 0, Mandatory, Prerequisites: `'(pass-110-closure-convert)`)
     - `pass-128-lir-branch-fusion` (Middle, Opt 2, Prerequisites: `'(pass-130-lir)`)
     - `pass-133-lir-peephole` (Middle, Opt 1, Verifier: `'lir`, Prerequisites: `'(pass-130-lir)`)

### 6.2 最適化レベルスケジューリング & 依存関係検証
1. **最適化レベル定義**:
   - **`-O0` (Fast Compilation)**:
     - 最小限の脱糖・正規化・低レベル化のみ実行。オプショナルな最適化パス（CP0, LVN, Annotator, RTyper, Contify, Alias-Escape, Branch Fusion, Peephole）をすべてスキップし、超高速コンパイルを実現。
   - **`-O1` (Basic Optimization)**:
     - 構造を大きく変えない軽量最適化（CP0 定数畳み込み・死滅コード削除、LIR ピープホール最適化）を有効化。
   - **`-O2` (Full Optimization - デフォルト)**:
     - LVN（共通部分式除去）、型推論アノテータ、アンボクシング、Contify、エスケープ解析、分岐融合など、すべての最適化パスを全開適用。
2. **依存関係検証アルゴリズム (`validate-pipeline-prerequisites`)**:
   - 構築されたパス順序列を先頭から走査し、各パスの `prerequisites` に含まれるパス ID がそれ以前に実行済み（有効化）されているかを検証。
   - 前提が欠落している場合（例: ユーザーが `pass-070-anf` を無効化したが `pass-110-closure-convert` が有効な場合）、コンパイルを安全に中断し、明解な不変条件エラーを報告。

### 6.3 観測性基盤・プロファイラ・Verifier 自動フック
1. **パス実行時間プロファイラ (`--time-passes`)**:
   - `current-jiffy` / `current-second`（ポータブルタイマーラッパー `get-monotonic-time-ms`）を用いたミリ秒単位の各パス実行時間計測。
   - 各パスごとの実測時間（ms）および全体に占める割合（%）を構造化レポートとして集約・表示。
2. **中間 IR ダンプ機構 (`--dump-ir=<pass>`, `--print-after-all`)**:
   - `--dump-ir=pass-id` で指定されたパスの直後に出力 AST / LIR を標準エラーまたは指定ポートに出力。
   - `--print-after-all` で各パス終了後の AST を連続ダンプ。
3. **AST Diff トレーサ統合 (`--trace-passes`)**:
   - `nanopass-display-ast-diff`（`compiler/nanopass_meta.scm`）と連携し、パス前後の AST 差分をカラー表示。
4. **IR Verifier 自動フック**:
   - パス記述子に `verifier-phase` が定義されている場合、パス実行直後に `(verify-pass-output phase output-ast)` を自動呼び出し。パスと検証ロジックを宣言的に密結合。

### 6.4 ドライバおよび CLI 統合 (`ulisp/compiler/driver.scm`)
1. **ディレクティブ・CLI オプション拡張**:
   - `-O0`, `-O1`, `-O2` および `(!opt 0)`, `(!opt 1)`, `(!opt 2)`
   - `--time-passes` および `(!time-passes)`
   - `--dump-ir=<pass>` および `(!dump-ir <pass>)`
   - `--print-after-all` および `(!print-after-all)`
   - `--disable-pass=<pass>` および `(!disable-pass <pass>)`
2. **`compile-to-lir` のリファクタリング**:
   - ハードコードされた 25 の `let*` 結合を、Pass Manager の実行関数 `(run-pass-pipeline forms pipeline-config)` への委譲に置換。
   - 既存の `--target-lir`、`!target lir`、Direct LIR Ingestion モードとの後方互換性を 100% 保持。

### 6.5 ビルドシステムおよびテストスイート拡充
1. **`ulisp/Makefile`**:
   - `COMPILER_BASE` に `compiler/pass_manager.scm` を追加。
   - `test_pass_manager` ターゲットの新設（`tests/test_pass_manager.scm` の実行）。
   - `make test` スイートへの登録。
2. **`ulisp/tests/test_pass_manager.scm` (新規テストスイート)**:
   - Group 1: パス記述子の生成・レジストリ登録・ルックアップ検証
   - Group 2: `-O0`, `-O1`, `-O2` 各最適化レベルにおけるパス選定リストの整合性テスト
   - Group 3: 前提条件（Prerequisites）欠落時のエラー検知・サイクル検出テスト
   - Group 4: 任意パスの無効化（`disable-pass`）および動的置換テスト
   - Group 5: `--time-passes` プロファイリング計測および `--dump-ir` 観測性テスト
   - Group 6: エンドツーエンドコンパイル比較（同一ソースを -O0, -O1, -O2 でコンパイルし実行結果が一致することの検証）

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/compiler/pass_manager.scm` が新規作成され、Pass Descriptor およびレジストリ基盤が実装されていること
- [x] Frontend から LIR までの主要パスがすべて Pass Descriptor として宣言的に登録されていること
- [x] `-O0`, `-O1`, `-O2` フラグに応じて実行パス群が動的に切り替わり、それぞれのパイプラインが正しく構築・実行されること
- [x] パスの前提条件（Prerequisites）が自動検証され、不正な順序や前提未達が安全に検出・報告されること
- [x] `--time-passes` によってパスごとの実行時間（ms）および構成比率が集計表示されること
- [x] `--dump-ir=<pass>` および `--print-after-all` によって中間 AST が正しく出力されること
- [x] `ulisp/compiler/driver.scm` の `compile-to-lir` が Pass Manager 経由で実行されるようリファクタリングされていること
- [x] 新規テストスイート `ulisp/tests/test_pass_manager.scm` が 100% PASS すること
- [x] 既存のテストスイート群（`make test`, `make test_nanopass`, `make test_passes`, `make test_lir_suite`）が 100% PASS すること
- [x] `make py_compile` および `make static_analysis` がエラー 0 件で通過すること

---

## 8. 作業ログ / Work Log
- 2026-10-25: Issue #598 の精緻化 (polish-issue) 完了。Pass Manager コア設計、最適化レベルスケジューリング、依存関係DAG検証、観測性基盤、CLI統合および DoD を詳細化。ステータスを `Open (In Progress)` に更新。
- 2026-10-25: 統一 Pass Manager 基盤（`ulisp/compiler/pass_manager.scm`）の実装完了。Pass Descriptor、グローバルレジストリ、-O0/-O1/-O2動的スケジューラ、前提条件DAG検証、観測性・プロファイラフック、およびドライバ（`ulisp/compiler/driver.scm`）リファクタリングを完了。新規テストスイート（`ulisp/tests/test_pass_manager.scm`）および仕様書（`ulisp/docs/spec_pipeline.md`）の更新を完了し、全DoD基準を満たしてクローズ。

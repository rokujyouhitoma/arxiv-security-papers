---
ID: 597
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] IR Verifier 基盤の共通化・階層分離と LIR 検証パフォーマンス最適化 (ID: 597)

## 1. 概要 / Summary
ULisp コンパイラにおける各中間表現（Desugar, ANF, Closure, SSA, LIR）の検証ロジック（IR Verifier）を共通基盤として統一・階層分離し、特に LIR 層で顕在化している重複定義・多重走査および $O(N^2)$ 線形探索オーバーヘッドを解消する。

### 背景と課題:
1. **共通検証インフラの欠如とコンテキスト喪失**:
   - 各 IR の Verifier（`compiler/verifier.scm` および `lir/lir_verifier.scm`）で AST 再帰走査ループが個別に重複実装されている。
   - 不変条件違反（Invariant Violation）発生時に、現在処理中の関数名（`%lir-function` 名）やブロック名（`%block` / `%label`）などの文脈情報が失われており、大規模プログラムのデバッグが困難となっている。
2. **LIR 仕様の二重管理と乖離リスク**:
   - Nanopass 言語定義（`L_lir_canonical` in `lir/lir_lang.scm`）と、手書きの巨大な `case` 分岐（`lir/lir_verifier.scm` 約 350 行）で命令構文および引数アリティ定義が重複管理されており、Spec Drift（仕様乖離）の温床となっている。
3. **多重走査による性能劣化**:
   - `validate-lir` 実行時に、同一 LIR プログラム・同一命令列に対して計 5 回以上のフルスキャン（`verify-ssa-ast`, `verify-lir-safepoint`, `lir-collect-labels-and-params`, `lir-valid-inst?`, `lir-verify-cfg-targets`, および `nanopass-ast-valid? 'L_lir_canonical`）が走っている。
4. **$O(N^2)$ 線形探索ボトルネック**:
   - ラベル定義の重複チェックおよびジャンプ先解決が線形リスト探索（`memq` / `assq` / `append`）で行われており、大規模な関数（ラベル数 $N \ge 100$, 命令数 $\ge 1,000$）において二次関数的（$O(N^2)$）な検証遅延が生じている。
   - オペランド検査において `symbol->string` が頻発し、ヒープアロケーション負荷と GC プレッシャーを増大させている。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/spec_pipeline.md)
  - [LIR 命令セット仕様書](../../ulisp/docs/spec_lir.md)
- **関連 Issue**:
  - Issue #576: [軽量 IR Verifier（Pass Checker）フレームワークの導入による中間不変条件の機械的検証](closed/576-implement-lightweight-ir-verifier-framework.md)
  - Issue #586: [Nanopass Framework DSL Phase 4: パイプライン統御・AST Diff トレーサおよび不変条件 Verifier 自動フック統合](closed/586-nanopass-framework-phase4-pipeline-observability-diff-trace-and-verifier-hooks.md)
  - Issue #589: [LIR (Low-level IR) 仕様の厳格化と不変条件バリデータ導入によるフロントエンド・バックエンド境界の確立](closed/589-establish-canonical-lir-specification-and-boundary-validator.md)
  - Issue #593: [LIR層: define-language L_lir_canonical の導入と lir_verifier 宣言的統合](closed/593-define-lir-canonical-language-and-verifier-integration.md)
  - Issue #594: [Frontend層: define-language L_anf / L_lifted の導入と不変条件自動検証](closed/594-define-frontend-anf-and-lifted-languages.md)
  - Issue #598: [統一 Pass Manager の導入によるパイプライン制御・最適化レベルスケジューリング・観測性の一元化](598-implement-unified-compiler-pass-manager.md)
  - Issue #602: [コンパイラ実行時における現在Nanopass・処理中トップレベル式・ソース位置のコンテキスト追跡とエラー診断ダンプの導入](closed/602-track-compiler-context-pass-and-toplevel-form-on-error.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/verifier.scm](../../ulisp/compiler/verifier.scm) (共通 Verifier 基盤・AST Visitor・診断コンテキスト・検証レベル制御の実装)
- [ ] [ulisp/lir/lir_verifier.scm](../../ulisp/lir/lir_verifier.scm) (2層分離・Single-Pass 走査統合・高速ハッシュテーブル探索化・アロケーション削減)
- [ ] [ulisp/lir/lir_lang.scm](../../ulisp/lir/lir_lang.scm) (Nanopass 構文定義との整合性確認・述語同期)
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm) (Makefile 経由のコンパイラバンドル再生成)
- [ ] [ulisp/tests/test_lir_verifier.scm](../../ulisp/tests/test_lir_verifier.scm) (パフォーマンス・診断・不変条件検証テストスイート拡充)
- [ ] [docs/issues/597-unify-ir-verifier-framework-and-optimize-lir-performance.md](597-unify-ir-verifier-framework-and-optimize-lir-performance.md) (本設計書)
- [ ] [docs/issues/README.md](README.md) (Issue 管理台帳のステータス更新)

---

## 3.2 脅威分析とセキュリティ要件 / Threat Modeling & Security Requirements

LIR は高水準 Scheme の安全な抽象構文木からネイティブマシン語生成（x86-64 / AArch64）および C99 バックエンドへの最終境界防壁である。コンパイラ最適化や検証パスにおける脅威を STRIDE / CWE 観点で分析し、防護要件を定義する。

| 脅威分類 (STRIDE / CWE) | 脅威シナリオ | 影響度 | 対策要件 (Mitigation Requirements) |
| :--- | :--- | :---: | :--- |
| **サービス拒否 (DoS / CWE-400 / CWE-770)** | 大規模な自動生成コードやマクロ展開後の巨大関数において、$O(N^2)$ のラベル線形探索により検証処理がハングアップまたは長時間停滞する。 | High | バケットハッシュ探索基盤（`symbol-hash-set` / `symbol-hash-table`）を導入し、ラベル重複判定およびジャンプ先解決を期待値 $O(1)$、全体 $O(N)$ 線形時間に抑制する。 |
| **不正入力検証不備 (CWE-20)** | 形式言語定義（`L_lir_canonical`）と手続き型検証器の判定差異隙間を突き、未定義命令や不正オペランドがコード生成後端にすり抜ける。 | High | Tier 1 (構文・オペランド仕様) と Tier 2 (CFG・セマンティクス) の責務を厳格分離し、構文検証を一元化する。 |
| **メモリ破壊・スタック破壊 (CWE-119 / CWE-787)** | 8バイト非整列の `frame-size` や不正なスタックオフセット、無効なスタックマップが通過し、生成されたネイティブバイナリでスタック破壊・SEGV が生じる。 | Critical | 境界検証において、スタックフレーム 8 バイト境界整列、非負オフセット、および Safepoint スタックマップのビットマップ正当性を厳格に強制する。 |
| **制御フロー不正 (CWE-674 / CWE-843)** | 未定義ラベルへのジャンプや、ブロック引数（arity）の不一致が検出されず、実行時スタック不整合や不正アドレスジャンプが発生する。 | High | Single-Pass 走査後のポストパス解決において、全ジャンプターゲットの定義存在性および `%block` 引数個数の一致を機械的・網羅的に検査する。 |

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/597-unify-ir-verifier-framework-and-optimize-lir-performance`

### 4.1 共通 Verifier 基盤 (Unified IR Verifier Core: `ulisp/compiler/verifier.scm`)
1. **多段階検証レベル制御 (`*verifier-level*`)**:
   - 単純な真偽値フラグ `*verifier-enabled*` に加え、4 段階の検証レベルを導入する：
     - `Level 0 (OFF)`: 検証完全無効（本番ビルド・ベンチマーク用、オーバーヘッド 0）
     - `Level 1 (BOUNDARY)`: フロントエンド・バックエンド境界（LIR 投入直前）のみ検証
     - `Level 2 (STANDARD)`: 各主要パスの出口（Pass 030, 070, 110, 130 等）で検証（デフォルト）
     - `Level 3 (PARANOID)`: Nanopass AST 全走査スキーマ検証 + 深層セマンティクス検査の二重実行
   - 既存 API（`verifier-enabled?`, `enable-verifier!`, `disable-verifier!`, `set-verifier-strict!`）との後方互換性を 100% 維持する。
2. **動的診断コンテキスト追跡 (`current-verifier-context`)**:
   - `with-verifier-context` マクロおよびコンテキストスタック（`*verifier-context-stack*`）を導入。
   - 検証中の Phase 名（`canonical-lir`, `anf`, etc.）、関数名（`current-fn`）、ブロック名（`current-block`）を動的に追跡。
   - 違反発生時に以下のような構造化・文脈付き診断レポートを出力：
     ```
     *** [VERIFIER ERROR] Phase: canonical-lir | Function: .L_compute | Block: .L_loop
         Invariant: Jump argument count does not match %block parameter count
         Expression: (%jump .L_join (%rax))
         Expected arity: 2, Actual arity: 1
     ```
3. **汎用 AST Visitor パターン**:
   - 再帰走査の重複コードを排除するため、共通走査関数 `(ast-walk-expr expr node-handlers default-walker)` を提供する。

### 4.2 高速シンボルハッシュテーブル・セット基盤 (`ulisp/lir/lir_verifier.scm`)
1. **軽量ハッシュセット / テーブルの実装**:
   - `helpers.scm` の `symbol-hash-str` を基盤とし、ベクタによるバケット構造（連想リストの配列）を導入：
     - `(make-symbol-hash-set size)`: 指定サイズのバケットベクタ生成
     - `(symbol-hash-set-add! set sym)`: シンボル登録（$O(1)$）
     - `(symbol-hash-set-contains? set sym)`: 存在判定（$O(1)$）
     - `(make-symbol-hash-table size)`: キー・値バケットテーブル生成
     - `(symbol-hash-table-put! tbl sym val)`: キー・値登録（$O(1)$）
     - `(symbol-hash-table-ref tbl sym default)`: 値参照（$O(1)$）
2. **ラベル・ブロック引数探索の線形化**:
   - ラベル定義の重複判定（`defined-labels`）およびジャンプ先の解決を `memq`（$O(N)$）から `symbol-hash-set-contains?`（$O(1)$）へ置換。
   - ブロック引数 arity 解決を `assq`（$O(N)$）から `symbol-hash-table-ref`（$O(1)$）へ置換。
   - これにより、大規模関数における検証計算量を $O(N^2)$ から $O(N)$ へ削減。

### 4.3 LIR Verifier の 2 層構造化と Single-Pass 統合走査
1. **Tier 1 (構文・オペランド仕様検証)**:
   - レジスタ判定（`*canonical-lir-registers*`）を高速化。
   - `symbol->string` の頻発呼び出しを削減し、シンボル名の先頭文字検査等を局所述語で効率化。
2. **Tier 2 (CFG・セマンティクス不変条件検証)**:
   - 独立して走っていた `verify-ssa-ast`、`lir-collect-labels-and-params`、`lir-valid-inst?`、`lir-verify-cfg-targets` を **Single-Pass 統合走査（`lir-verify-function-single-pass`）** に統合。
3. **Single-Pass 走査アルゴリズム**:
   - **Step 1 (走査・収集)**:
     - 命令列を 1 回のみループ。
     - 各命令の構文（Tier 1）を検証。
     - `%label` / `%block` に遭遇した場合、`label-set` に $O(1)$ で重複確認して登録。重複時は即時エラー報告。
     - `%block` の引数個数を `block-arity-table` に $O(1)$ で登録。
     - `%jump`, `%jump-if`, `%jump-if-false`, `%jump-cond` 等のジャンプ命令に遭遇した場合、ターゲット名と実引数個数のタプルを `pending-jumps` リストへ蓄積。
   - **Step 2 (ポストパス解決)**:
     - 蓄積された `pending-jumps` を 1 回走査。
     - ターゲットラベルが `label-set` または `known-fn-labels-set` に存在するか $O(1)$ で検証。
     - ブロックターゲットの場合、引数個数の一致を `block-arity-table` から $O(1)$ で取得・照合。
4. **多重走査の排除**:
   - `validate-lir` 内で無条件に実行されていた `(nanopass-ast-valid? 'L_lir_canonical prog)` を検証レベル（Level 3: Paranoid）に連動させ、Level 1/2 では Single-Pass 統合検証のみで完結させることで走査オーバーヘッドを大幅に削減。

### 4.4 テストスイート拡充方針 (`ulisp/tests/test_lir_verifier.scm`)
1. **スケーラビリティ / 性能回帰テスト**:
   - 100 以上のラベルと 1,000 以上のジャンプを含む大規模関数を自動生成し、検証時間が線形（$O(N)$）で高速に完了することを検証。
2. **コンテキスト付き診断レポートのテスト**:
   - 関数名・ブロック名がエラーメッセージに含まれていることを確認するテストケースを追加。
3. **検証レベル制御テスト**:
   - Level 0（完全無効化）、Level 1（境界のみ）、Level 2（標準）、Level 3（厳格）の各モードでの動作検証。
4. **既存テストの後方互換性保証**:
   - `test_lir_verifier.scm` に定義された既存の 20 以上のユニットテストがすべて PASS することを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 共通 Verifier 基盤（`compiler/verifier.scm`）に動的コンテキスト追跡（関数名・ブロック名）および検証レベル制御（Level 0〜3）が実装されていること
- [x] 違反発生時の診断メッセージに現在の関数名およびブロック名が正確に表示されること
- [x] 軽量シンボルハッシュテーブル／セットが導入され、ラベル探索・重複判定が $O(1)$（全体 $O(N)$）で動作すること
- [x] LIR 検証において 4〜5 重に分かれていた走査が Single-Pass（1 回の走査 + ポストパス解決）に統合されていること
- [x] `symbol->string` 呼び出し頻発によるアロケーションが抑制されていること
- [x] 大規模関数（100+ ラベル）を用いたベンチマークにおいて、$O(N^2)$ から $O(N)$ への線形スケーラビリティが実証されること
- [x] 既存の `test_lir_verifier.scm` およびコンパイラ全体のテストスイートが 100% PASS すること
- [x] `make py_compile` および `make static_analysis` がエラー 0 件で通過すること

---

## 6. 作業ログ / Work Log
- 2026-10-24: Issue 作成 (ID: 597)
- 2026-10-24: `/polish-issue` により詳細設計・脅威モデリング・Single-Pass アルゴリズム・DoD を策定。ステータスを `Open (In Progress)` に更新。
- 2026-10-24: `compiler/verifier.scm` に `*verifier-level*`、`with-verifier-context`、コンテキスト付き `verifier-error` を実装。
- 2026-10-24: `lir/lir_verifier.scm` に DJB2 ハッシュセット/テーブル基盤および `lir-verify-insts-single-pass` を実装。多重走査を解消し $O(N)$ 線形化を達成。
- 2026-10-24: `test_lir_verifier.scm` に Group 8（レベル制御・コンテキスト・100ブロック連鎖スケーラビリティ）を追加し全 46/46 PASS、全 Verifier テスト 73/73 PASS を確認。ステータスを `Closed` に更新。

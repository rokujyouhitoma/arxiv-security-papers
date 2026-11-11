---
ID: 764
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] verifier.scm の手書き検証ループの define-attopass 化と Nanopass 融合による三重走査の解消 (DSN-33-01 T4.3) (ID: 764)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 8.2 節（課題②）、第 8.4 節、および第 9.2 節タスク **T4.3** に基づき、現在 `ulisp/compiler/verifier.scm` に手書きの再帰ループとして実装されている各フェーズの構文・不変条件検査（`verify-desugared-ast`, `verify-anf-ast`, `verify-closure-ast`, `verify-lir-safepoint`, `verify-ssa-ast`）を **`define-attopass`** 規則群として再定義し、`nanopass_meta.scm` の検証キャッシュと連携させることで、`--verify-ir`（`verifier-level >= 2`）有効時に 1 パスあたり最大 3 回以上発生していた重複全木走査（三重走査）を完全に解消する。

---

## 2. 背景と課題分析 / Background and Problem Analysis

### 2.1 現行実装における三重走査・重複検査の発生メカニズム

現在、ULisp コンパイラにおいて `--verify-ir`（または `(enable-verifier!)`）を有効化してパイプラインを実行すると、同一の AST に対して以下の三重走査・多重検査が発生している：

1. **第 1 走査（パス出口でのスキーマ検証）**:
   `define-pass` の展開コード（`ulisp/compiler/nanopass.scm:610`）において、パス終了時に `(nanopass-verify-ast name l-out res-var 'exit)` が呼ばれ、出力言語 $L_{\text{out}}$ の全構文木を走査する。
2. **第 2 走査（パス管理層での手書き検証 ＋ 重複スキーマ検証）**:
   直後に `ulisp/compiler/pass_manager.scm:481` の `run-single-pass` が `(verify-pass-output vphase output-ast)` を呼ぶ。
   - `verify-anf-ast`（`verifier.scm:116-120`）では、まず `(nanopass-ast-valid? 'L_anf ast)` を呼んで再度スキーマ走査した上で、手書きの `let loop` で 3 番地原子性検査を走査する。
   - `verify-closure-ast`（`verifier.scm:191-193`）でも、まず `(nanopass-ast-valid? 'L_lifted ast)` を呼んで再度スキーマ走査した上で、手書きの `let loop` で未リフト lambda 検査を走査する。
3. **第 3 走査（次パス入口での同一スキーマ重複検証）**:
   次パス $P_{k+1}$（入力言語 $L_{\text{in}} = L_{\text{out}}$）の `define-pass` 入口（`nanopass.scm:604`）において、`(nanopass-verify-ast name l-in ir-var 'entry)` が呼ばれる。入力 AST は直前のパス $P_k$ が出力した AST そのものであるにもかかわらず、全く同一の言語スキーマに対して再度木全体の走査が実行される。
4. **キーワード定義の二重管理**:
   `verifier.scm:85-86` の `*prohibited-desugared-keywords*` は、`L_core`（`frontend/frontend_lang.scm:120-134`）の除去構文リスト `(- ...)` と重複しており、二重管理によるメンテナンス性の低下を招いている。

---

## 3. トレーサビリティ / Traceability

- **関連設計書**:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
    - 第 3.1 節（Picopass 三権分立：Picopass / Femtopass / Attopass 仕様）
    - 第 4.1 節（1ノード訪問時の5ステップ標準融合サイクル：事前 Attopass / 事後 Attopass）
    - 第 8.2 節 課題②（Verifier の三重実装・三重走査）
    - 第 8.4 節（統廃合・再配置マトリクス）
    - 第 9.2 節 タスク **T4.3**（verifier.scm の define-attopass 化と三重走査の単一走査融合）
- **依存関係**:
  - 先行 Issue:
    - [Issue #754 (T1.2: カタモルフィズムのスキーマ駆動化)](closed/754-refactor-catamorphism-to-schema-driven-traversal.md)
    - [Issue #756 (T2.1: 第一級ルール記述子と define-attopass DSL 実装)](closed/756-implement-rule-descriptor-and-picopass-femtopass-attopass-dsl.md)
    - [Issue #758 (T2.3: Pass 015 DSL 先行展開器への attopass 統合)](closed/758-integrate-picopass-dsl-into-pass-015-expander.md)
    - [Issue #760 (T3.2: 5ステップ融合サイクルと局所再ディスパッチ)](closed/760-implement-local-redispatch-and-extends-eliminates-validation.md)
    - [Issue #763 (T4.2: 030_desugar.scm の fuse-rules 置換)](closed/763-replace-desugar-030-duplicate-rules-with-fuse-rules.md)
  - 後続 Issue:
    - [Issue #765 (T5.1: ルール依存 DAG 自動構築・自動 Fusion・Femtopass キャッシュ維持)](765-implement-rule-dependency-dag-and-femtopass-cache-invalidation.md)
    - [Issue #766 (T5.2: HIR/MIR Hash-Consing Term DAG と訪問済みノード O(1) メモ化走査)](766-implement-hash-consing-term-dag-and-memoized-catamorphism.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/verifier.scm](../../ulisp/compiler/verifier.scm)（手書き検証ループの `define-attopass` 化と公開 API の統合）
- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)（AST 検証済みキャッシュ機構 `*nanopass-last-verified-ast*` / `*nanopass-last-verified-lang*` の導入と重複走査の $O(1)$ スキップ）
- [ ] [ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm)（パイプライン開始時の検証キャッシュリセットと `run-single-pass` の軽量ディスパッチ）
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm)（セルフホスト統合コンパイラソース再生成）
- [ ] [ulisp/tests/test_verifier.scm](../../ulisp/tests/test_verifier.scm)（軽量 IR 検証単体テスト全 27 テストの完全互換 PASS 確認）
- [ ] [docs/issues/764-migrate-verifier-to-attopass-and-eliminate-triple-traversal.md](764-migrate-verifier-to-attopass-and-eliminate-triple-traversal.md)
- [ ] [docs/issues/README.md](README.md)

---

## 5. 実装方針 / Implementation Plan

Target Branch: `refactor/764-migrate-verifier-to-attopass`

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Phase 4: Task T4.3 設計詳細                      │
└────────────────────────────────────────────────────────────────────────┘

  [Pass N (Out: L_k)]                    [Pass N+1 (In: L_k)]
         │                                       │
         ▼                                       ▼
  nanopass-verify-ast (L_k)               nanopass-verify-ast (L_k)
         │                                       │
    (初回検証: 走査実行)                   (Cache Hit: eq? val & L_k)
         │                                       │
    [Cache Update]                               ▼
  ast: #<pair...>, lang: L_k            ★ O(1) で即時パス (走査スキップ)
         │
         ▼
  verify-pass-output
         │
         ▼
  define-attopass (不変条件検査のみ実行: スキーマ重複走査なし)
```

### Step 1: Feature ブランチ作成と作業環境準備
- `refactor/764-migrate-verifier-to-attopass` ブランチを作成し、`main` から分岐。

### Step 2: `nanopass_meta.scm` への検証済みキャッシュ機構導入
- `nanopass_meta.scm` に直前検証済み AST と言語を保持するボックスを追加：
  ```scheme
  (define *nanopass-last-verified-ast* (cons #f '()))
  (define *nanopass-last-verified-lang* (cons #f '()))

  (define (reset-nanopass-verification-cache!)
    (set-car! *nanopass-last-verified-ast* #f)
    (set-car! *nanopass-last-verified-lang* #f))
  ```
- `nanopass-verify-ast` において、`val` が `*nanopass-last-verified-ast*` と `eq?` かつ `lang-name` が `*nanopass-last-verified-lang*` と `eq?` の場合は、同一 AST・同一言語に対する重複検証と判定し、全木走査を行わずに即座に `#t` を返す。
- 検証成功時に `*nanopass-last-verified-ast*` と `*nanopass-last-verified-lang*` を更新する。

### Step 3: `verifier.scm` の不変条件検査の `define-attopass` 化
以下の各検証フェーズを手書き再帰ループから `define-attopass` 規則群へと刷新する：

1. **`atto-no-desugar-sugar` (Pass 030 Desugar 出力不変条件)**:
   - 対象非終端記号: `Expr`
   - 残存糖衣構文（`cond`, `case`, `and`, `or`, `let*`, `let-values`, `let*-values`, `guard`, `parameterize`, `do`, `when`, `unless`, `define-values`）および Named-let `(let <sym> ...)` をパターンマッチで捕捉。
   - 違反時は `(verifier-error 'desugar ... ir)` を呼び出し、不一致（正常時）は `#t` を返却。
2. **`atto-anf-invariants` (Pass 070 ANF 出力不変条件)**:
   - 対象非終端記号: `Expr`
   - 非原子的な `if` 条件式 `((if ,test ,then ,else-e) (guard (not (atomic-expr? test))) ...)` を捕捉。
   - 非原子的な `%values` 引数 `((%values ,args ...) (guard (not (all-atomic-expr? args))) ...)` を捕捉。
   - 非特殊形式の関数適用 `(,op ,args ...)` における `op` および各実引数 `args` の原子性を検査。
3. **`atto-closure-invariants` (Pass 110 Closure 出力不変条件)**:
   - 対象非終端記号: `Expr`
   - 未リフト lambda `((lambda (,params ...) ,body ...) ...)` を捕捉。
   - `%make-closure` / `%make-closure-env` におけるラベルのシンボル性および環境変数の原子性を検査。
4. **`atto-safepoint-invariants` (Pass 131 Safepoint 出力不変条件)**:
   - `%lir-program` の `stackmaps` 節の存在、各エントリ `(label frame-size bitmap)` の正整数・8バイト境界・非負ビットマップを検査。
5. **`atto-ssa-invariants` (Pass 132 Braun SSA 出力不変条件)**:
   - `%block` の引数リストのシンボル性および `%jump` のターゲットシンボル・原子引数を検査。

### Step 4: 汎用 Attopass 走査ドライバ `verifier-walk-attopass` の導入
- 木構造を再帰走査しながら各ノードで `(atto-proc node)` を評価し、エラー発生時は即座に `#f` を返す汎用軽量ウォーカーを定義：
  ```scheme
  (define (verifier-walk-attopass atto-proc ast)
    (let loop ((node ast))
      (cond
        ((not (pair? node)) #t)
        ((eq? (car node) 'quote) #t)
        ((not (atto-proc node)) #f)
        (else
         (let rec ((children (cdr node)))
           (if (null? children)
               #t
               (and (loop (car children))
                    (rec (cdr children)))))))))
  ```
- 既存の公開 API（`verify-desugared-ast`, `verify-anf-ast`, `verify-closure-ast`, `verify-lir-safepoint`, `verify-ssa-ast`）を、上記 attopass 規則群とウォーカーを用いた実装へと置換。既存テストスイート（`test_verifier.scm`）との 100% 後方互換性を維持する。
- `verify-anf-ast` および `verify-closure-ast` における重複スキーマ走査 `(nanopass-ast-valid? ...)` は、キャッシュ未ヒット時のみ実行するように最適化。

### Step 5: `pass_manager.scm` パイプライン連携とキャッシュ整合性の確保
- `run-pass-pipeline` 開始時に `(reset-nanopass-verification-cache!)` を呼び出し、前回の実行状態をクリーンアップ。
- `run-single-pass` の検証呼び出しと `define-pass` の出入口検証が連携し、不要な重複全木走査が発生しないことを確認。

### Step 6: 単体テスト・回帰テスト・品質ゲート検証
- `make -C ulisp test_verifier`: 全 27 テストが 100% PASS することを確認。
- `make -C ulisp test_nanopass`: Nanopass フレームワークテスト全件 PASS を確認。
- `make -C ulisp test_passes`: 全 147 パステストが 100% PASS することを確認。
- `make -C ulisp test_all_passes`: 全 39 パスのバッチ単体テストが 0 failures で全件 PASS することを確認。
- `make -C ulisp compiler && make -C ulisp bootstrap`: Stage 1〜3 セルフホスティングが bit-for-bit IDENTICAL で完遂することを確認。
- `make py_compile && make static_analysis`: エラー 0 件を確認。

### Step 7: ブランチマージと台帳クローズ
- Conventional Commit 形式でコミットし、`main` へマージ。
- 本 Issue ファイルを `docs/issues/closed/` へ移動し、`docs/issues/README.md` を更新。

---

## 6. 完了条件 / Success Criteria (DoD)

1. [ ] **Attopass 規則群の正式定義**: `atto-no-desugar-sugar`, `atto-anf-invariants`, `atto-closure-invariants`, `atto-safepoint-invariants`, `atto-ssa-invariants` が `define-attopass` として定義され、第一級ルール記述子として登録されていること。
2. [ ] **手書き検証再帰ループの撤廃**: `verifier.scm` 内の ad-hoc な手書き再帰ロジックが Attopass 規則と汎用ウォーカーへ一本化されていること。
3. [ ] **スキーマ検証キャッシュによる重複走査解消**: パス出口と次パス入口における同一 AST・同一言語に対する重複走査が $O(1)$ でスキップされること。
4. [ ] **Verifier 単体テスト 100% PASS**: `make -C ulisp test_verifier` の全 27 テストが回帰なく完全 PASS すること。
5. [ ] **全 39 パスおよび Nanopass 基盤テスト 100% PASS**: `test_all_passes` および `test_nanopass` が 0 failures で通過すること。
6. [ ] **3-Stage セルフホスティング固定点**: `make -C ulisp bootstrap` が bit-for-bit 完全一致で成功し、スモークテスト（42）が正常完了すること。
7. [ ] **リポジトリ品質ゲート**: `make py_compile`、`make static_analysis` がエラー 0 件で通過し、絶対パスリンクが 0 件であること。

---

## 7. テスト計画と検証手順 / Test Plan and Verification Procedures

### 7.1 Verifier 単体テスト
```bash
make -C ulisp test_verifier
```
- Group 1: Desugar 出力不変条件（`cond`, `let*`, `and`, `or`, `named-let`, `let-values` の拒否、正常形式の受理）
- Group 2: ANF 出力不変条件（非原子 if 条件式、非原子関数の拒否、フラット式の受理）
- Group 3: Closure 出力不変条件（未リフト lambda、非シンボルラベル、非原子環境変数の拒否、`%make-closure` の受理）
- Group 4: Safepoint 出力不変条件（8バイト境界整合、非負ビットマップ）
- Group 5: SSA 出力不変条件（%block 引数、%jump 引数の原子性）
- Group 6: 統合 Verifier ディスパッチャ

### 7.2 全パスおよびセルフホスティング回帰テスト
```bash
make -C ulisp test_all_passes
make -C ulisp test_nanopass
make -C ulisp compiler
make -C ulisp bootstrap
```
- 全 39 パス 1:1 単体テストがすべて PASS すること。
- Stage 2 と Stage 3 の生成コード差分が 0 であること。

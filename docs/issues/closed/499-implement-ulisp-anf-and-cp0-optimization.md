---
ID: 499
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT] Implement ANF Normalization and CP0 Constant Folding Optimizer for ULisp (ID: 499)

## 1. 概要 / Summary
現在、ULisp コンパイラ（Pass 1 脱糖 $\to$ Pass 5 クロージャ変換 $\to$ Pass 7 コード生成）では、深くネストした式（例: `(+ (* x 10) (- y 2))`）がそのまま下流パスに渡されていた。
これにより、コード生成器はネストした式の評価順序を保つためにスタックポインタオフセット `si` を計算しながら中間値をスタックに退避・復元していた。

本 Issue では、Chez Scheme 等の現代的 Scheme コンパイラアーキテクチャに準拠し、以下の 2 つの独立した S式 $\to$ S式 最適化・正規化 Nanopass を導入した：
1. **CP0 最適化パス (`ulisp/passes/03_cp0.scm`)**:
   - 定数畳み込み (Constant Folding): 静的に確定可能な基本演算（四則演算、等値比較、`null?`, `not` 等）の事前評価。
   - 自明な条件分岐剪定 (Dead Branch Pruning): `(if #t ...)` / `(if #f ...)` や静的真偽値に基づく不要分岐の除去。
   - 自明な恒等束縛・コピー伝播 (Copy Propagation) および未使用変数の除去。
2. **ANF 正規化パス (`ulisp/passes/04_anf.scm`)**:
   - A-Normal Form（3番地コード形式）への正規化。すべての非アトミックな部分式（複合式）を明示的な一時変数（`%t0`〜`%t8`）の `let` 束縛に持ち上げ、関数の引数位置をアトミックな値（シンボルまたは即値）のみに正規化。
   - セルフホスティング時のメモリ爆発（ヒープ枯渇）を防ぐため、深さ別の固定シンボルプール（Scoped Temporary Variable Pool: Zero Heap Allocation）方式を採用。
3. **直列パイプライン結合**:
   - `01_desugar.scm` $\to$ `02_analysis.scm` $\to$ `03_cp0.scm` $\to$ `04_anf.scm` $\to$ `05_closure_convert.scm` $\to$ `06_emitter.scm` $\to$ `07_codegen.scm` $\to$ `08_driver.scm`
   - 全パスが完全に独立した直列パイプラインとして接続。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §3 (言語機能と低レイヤコード生成仕様), §4 (フェーズ別コンパイラ設計), §6.1 (セルフホスティングパイプライン)
- **DSN-31**: §3.2 (Backend B: ULisp AOT Native Backend)
- **先行 Issue**: #496 (Modularize Passes), #497 (Serial Nanopass), #498 (Closure Conversion Nanopass)

---

## 3. セキュリティ & 脅威分析 / Security Analysis & Threat Model
1. **未定義動作・ゼロ除算リスク (Compile-Time Division by Zero)**:
   - 定数畳み込み時に `(/ x 0)` や無効な引数型を安易に事前評価すると、コンパイラ自身が実行時例外で異常終了する脅威。
   - **対策**: 安全な演算（ゼロ除算除外、数値型ガード）のみを畳み込み対象とし、疑義がある場合は畳み込みを安全にスキップして実行時コード生成へ委ねる。
2. **副作用脱落の脅威 (Side-Effect Omission)**:
   - 不要コード削除において、I/O（`display`, `write`, `read`）やメモリ破壊等の副作用を伴う式を削除してしまい、プログラムの意味論が破壊される脅威。
   - **対策**: 副作用を持たない純粋な式（純粋プリミティブ、即値、変数参照）のみを DCE (Dead Code Elimination) の対象として厳格に限定。
3. **一時変数名衝突リスク (Temporary Variable Capture)**:
   - ANF 変換で導入される一時変数名が、既存のユーザー定義変数やマクロ生成シンボルと衝突し、変数が不正にシャドウイングされる脅威。
   - **対策**: `%t0`〜`%t8` の予約シンボルプールを深さ管理（Scoped Temporary Variable Pool）で局所的に割り当て、グローバルシンボルやユーザー定義シンボルと完全に分離。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/03_cp0.scm](file:///workspace/arxiv-security-papers/ulisp/passes/03_cp0.scm): 新設した CP0 最適化パス（定数畳み込み・自明分岐剪定・不要束縛削除）
- [x] [ulisp/passes/04_anf.scm](file:///workspace/arxiv-security-papers/ulisp/passes/04_anf.scm): 新設した ANF 正規化パス（Scoped Pool によるゼロアロケーション 3番地コード化）
- [x] [ulisp/passes/05_closure_convert.scm](file:///workspace/arxiv-security-papers/ulisp/passes/05_closure_convert.scm): 旧 `03_closure_convert.scm`（リナンバリングおよび直列結合）
- [x] [ulisp/passes/06_emitter.scm](file:///workspace/arxiv-security-papers/ulisp/passes/06_emitter.scm): 旧 `04_emitter.scm`
- [x] [ulisp/passes/07_codegen.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_codegen.scm): 旧 `05_codegen.scm`
- [x] [ulisp/passes/08_driver.scm](file:///workspace/arxiv-security-papers/ulisp/passes/08_driver.scm): 旧 `06_driver.scm`（新パイプライン直列接続）
- [x] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile): パス構成一覧（`PASSES`）の同期
- [x] [ulisp/bootstrap.sh](file:///workspace/arxiv-security-papers/ulisp/bootstrap.sh): セルフホスティング不動点検証
- [x] [ulisp/test.sh](file:///workspace/arxiv-security-papers/ulisp/test.sh): 既存テストスイート 100% PASS 保証
- [x] [tests/ilisp/test_ulisp_codegen.py](file:///workspace/arxiv-security-papers/tests/ilisp/test_ulisp_codegen.py): ILisp AOT 連携テスト 100% PASS 保証
- [x] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳の更新

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/499-implement-ulisp-anf-and-cp0-optimization`

1. **Pass 3: CP0 最適化パス (`03_cp0.scm`) の実装**:
   - `(cp0-optimize form)` / `(cp0-expr expr)`
   - 即値畳み込み: `(+ 1 2)` $\to$ `3`, `(* 6 7)` $\to$ `42`, 述語 `(not #f)` $\to$ `#t`, `(null? '())` $\to$ `#t`
   - 自明分岐剪定: `(if #t then else)` $\to$ `then`, `(if #f then else)` $\to$ `else`
   - 不要束縛削除: `(let ((unused pure-expr)) body)` で `unused` が `body` 内で参照されない場合の安全な除去
2. **Pass 4: ANF 正規化パス (`04_anf.scm`) の実装**:
   - `(anf-all form)` / `(anf-expr-depth expr depth)`
   - 複合式引数をアトミックなシンボルまたは即値に平坦化。
   - Scoped Temporary Variable Pool（`%t0`〜`%t8`）により、セルフホスティング時の `string->symbol` ヒープアロケーションを完全排除。
3. **パス番号の整理と直列パイプライン結合**:
   - `00_helpers` $\to$ `01_desugar` $\to$ `02_analysis` $\to$ `03_cp0` $\to$ `04_anf` $\to$ `05_closure_convert` $\to$ `06_emitter` $\to$ `07_codegen` $\to$ `08_driver`
4. **検証と品質ゲート**:
   - `cd ulisp && ./test.sh`: Phase 1〜7 テスト 100% PASS。
   - `cd ulisp && ./bootstrap.sh`: Stage 1 $\to$ Stage 2 $\to$ Stage 3 不動点検証（`diff stage2.s stage3.s == 0`）。
   - `.venv/bin/pytest tests/ilisp/test_ulisp_codegen.py`: 全 18 件 PASS。
   - `make check_format` & `make py_compile`: エラー 0 件。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `03_cp0.scm` が定数計算・自明分岐を S式レベルで簡約し、意味論を 100% 保持すること。
- [x] `04_anf.scm` が複合式の引数を一時変数束縛へ平坦化し、関数の引数がすべてアトミックな形に正規化されること。
- [x] `05_closure_convert.scm` が ANF 出力を透過的に受け入れ、フラットな `%function` と `%make-closure` を正しく生成すること。
- [x] `ulisp/test.sh` の全テスト（高階関数、再帰、letrec、TCO 深度テスト含む）が 100% PASS すること。
- [x] `ulisp/bootstrap.sh` の不動点検証（Stage 2 と Stage 3 の bit-for-bit 完全一致）が成立すること。
- [x] `tests/ilisp/test_ulisp_codegen.py` が全 18 件 PASS すること。
- [x] `make check_format` & `make py_compile` をパスすること。

---

## 7. 実装・検証完了報告 / Completion Report
- **新設 Nanopass**:
  - `ulisp/passes/03_cp0.scm`: 定数畳み込み・自明分岐剪定・不要 let 束縛削除（Dead Let Elimination）を実装。
  - `ulisp/passes/04_anf.scm`: 引数の複合式を一時変数へ平坦化する 3 番地コード形式正規化を実装。Scoped Pool 一時変数（`%t0`〜`%t8`）によりヒープ消費を極小化。
- **検証実績**:
  - `ulisp/test.sh`: Phase 1〜Phase 7 全テスト 100% PASS。
  - `ulisp/bootstrap.sh`: 3 段階ブートストラップ検証で Stage 2 と Stage 3 の出力が **bit-for-bit IDENTICAL (diff 0件)** を達成。
  - `tests/ilisp/test_ulisp_codegen.py`: 全 18 テスト PASS (24.96s)。
  - `make check_format && make py_compile`: 正常終了 (exit code 0)。

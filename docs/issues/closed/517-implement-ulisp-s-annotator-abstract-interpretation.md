---
ID: 517
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-10-11
---

# [FEAT/ENH] ULisp コンパイラへの抽象解釈型推論器 (S-Annotator) と型格子 (Lattice) の実装 (ID: 517)

## 1. 概要 / Summary
RPython の Annotator アーキテクチャに倣い、ULisp Nanopass パイプラインの Pass 04 (ANF) 直後に抽象解釈（Abstract Interpretation）に基づく大域的型推論パス（`Pass 04b: S-Annotator`）を導入する。
ANF 変換された Core AST の各変数および式に対し、静的データフロー解析と単調増加型格子（Type Lattice）を用いた不動点計算を行い、変数ごとに型情報（`SomeFixnum`, `SomeBoolean`, `SomePair`, `SomeClosure` 等）および範囲情報を確定・注釈付けする。また、解決不能な型の不整合（多相的型ユニオン）を検知して R-Scheme（Restricted Scheme）規約違反として早期検出する機構を確立する。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (AOT & JIT 統合アーキテクチャ 第2・7章)](file:///workspace/arxiv-security-papers/docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-31: ILISP R7RS Core Architecture Specification](file:///workspace/arxiv-security-papers/docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md)
- **関連先行 Issue**:
  - Issue #499: ULisp コンパイラへの ANF 正規化および CP0 最適化パスの実装
  - Issue #514: ULisp と MLisp の完全統合による統一 RPython スタイル言語基盤の確立

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/04b_annotator.scm](file:///workspace/arxiv-security-papers/ulisp/passes/04b_annotator.scm) (新規作成: S-Annotator 抽象解釈エンジン)
- [x] [ulisp/passes/00_helpers.scm](file:///workspace/arxiv-security-papers/ulisp/passes/00_helpers.scm) (抽象型述語およびヘルパー関数の追加)
- [x] [ulisp/passes/08_driver.scm](file:///workspace/arxiv-security-papers/ulisp/passes/08_driver.scm) (Nanopass 直列パイプラインへの Pass 04b 組み込み)
- [x] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile) (PASSES_LIB 定義への 04b_annotator.scm 追加)
- [x] [ulisp/tests/test_passes.scm](file:///workspace/arxiv-security-papers/ulisp/tests/test_passes.scm) (Pass 04b 単体テストケースの追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/517-ulisp-s-annotator-abstract-interpretation`

### 4.1 抽象値格子 (Abstract Lattice) の定義
`04b_annotator.scm` において、以下の代数型格子を S 式として表現・操作する：
- **格子要素**:
  - `'(%type bot)` : 未評価・非終了（Bottom）
  - `'(%type top)` : 任意・動的 Scheme 値（Top）
  - `'(%type fixnum)` : 64-bit 整数値（Fixnum）
  - `'(%type (fixnum <min> <max>))` : 区間付き整数値
  - `'(%type boolean)` : 真偽値
  - `'(%type (pair <car-type> <cdr-type>))` : ペア / リスト構造
  - `'(%type null)` : 空リスト `'()`
  - `'(%type string)` : 文字列
  - `'(%type (closure <id> <arg-types> <ret-type>))` : クロージャ型
- **最小公倍数（LUB / Join: $\sqcup$）演算 (`type-lub t1 t2`)**:
  - `(type-lub bot T) = T`
  - `(type-lub T bot) = T`
  - `(type-lub fixnum fixnum) = fixnum`
  - `(type-lub (fixnum a b) (fixnum c d)) = (fixnum (min a c) (max b d))`
  - 異なる型（例: `fixnum` と `string`）の合流 $\rightarrow$ 原則 `'(%type top)`、または厳格モード時に警告/エラー。

### 4.2 抽象解釈エンジン (`abstract-eval-expr expr env`)
1. **リテラル・即値**:
   - 整数リテラル $\rightarrow$ `'(%type (fixnum n n))`
   - 真偽値 $\rightarrow$ `'(%type boolean)`
   - 文字列 $\rightarrow$ `'(%type string)`
2. **プリミティブ演算**:
   - 算術演算 (`+`, `-`, `*`): 引数が `fixnum` の場合、戻り値も `fixnum`（区間演算対応）。
   - 比較演算 (`=`, `<`, `>`, `<=`, `>=`): 戻り値 `boolean`。
   - ペア演算 (`cons`, `car`, `cdr`): `car`/`cdr` の型伝播。
3. **制御構文**:
   - `if`: 条件式の抽象評価の後、then 節と else 節を抽象評価し、`type-lub` で合流。
   - `let`: 局所変数を環境 `env` にバインドして body を評価。
   - `begin`: 順次評価し、末尾式の型を返す。
4. **末尾再帰・ループの不動点反復 (`abstract-eval-loop`)**:
   - `named-let` または再帰関数において、引数の初期型からシミュレーションを開始し、再帰呼び出し引数の型と LUB を取り、型環境が変化しなくなる（不動点到達）まで反復計算（最大 10 回で Widening して `top` または `fixnum` へ収束）。

### 4.3 パイプライン連携と透過性
- `annotate-anf-forms forms`:
  - 全トップレベル式および手続きを走査し、各大域定義および局所変数に推論型を注釈。
  - 下流の Pass 05 (Closure Convert) や Pass 06 (LIR) との完全な後方互換性を保つため、`(strip-type-annotations expr)` または型メタデータテーブル提供関数 `(get-annotated-type var)` のデュアルインターフェースを提供。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/passes/04b_annotator.scm` が新規作成され、`PASSES_LIB` に統合されていること。
- [x] 以下の基本パターンについて単体テストが作成され、全件 PASS すること：
  - 整数即値および算術式（`+`, `-`, `*`）の `fixnum` 推論
  - 分岐式（`if`）の `type-lub` マージ
  - 再帰ループ（Fibonacci, Factorial）のループ変数・戻り値の不動点推論
- [x] 既存の全 Nanopass 単体テスト（105 件）および統合テストスイートが 100% グリーン（PASS）を維持すること。
- [x] `make -C ulisp bootstrap` で Stage 2 と Stage 3 の生成コードが完全一致（`diff == 0`）すること。


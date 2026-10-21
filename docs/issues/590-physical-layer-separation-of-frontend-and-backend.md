---
ID: 590
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] ULisp コンパイラ層の物理分離（Frontend/Nanopass メタコンパイラ層と Backend/低レベルコード生成層の分離） (ID: 590)

## 1. 概要 / Summary

現在、`ulisp/passes/` 直下に Pass 010 から Pass 160 までの全 33 パスが平坦に配置され、高水準メタコンパイラ処理と低水準機械語生成処理の境界が曖昧になっている。

本 Issue では、Issue 589 で確立された Canonical LIR 境界を軸に、ULisp コンパイラの内部モジュール構造およびパイプラインを「**Frontend / Middle-End（Nanopass メタコンパイラ層）**」と「**Backend（低レベルマシン語/Cコード生成層）**」の 2 大独立層へ物理的に再編・分離する。

これにより、言語拡張や Nanopass DSL の改良と、ターゲット依存のアーキテクチャ最適化（x86-64 / AArch64 / C99 / GC）が互いに独立して進化できる疎結合アーキテクチャを実現する。

---

## 2. トレーサビリティ / Traceability

- **アーキテクチャ仕様**:
  - DSN-33 コンパイラアーキテクチャ仕様書
  - [ulisp/docs/pipeline_architecture.md](../../ulisp/docs/pipeline_architecture.md)
- **関連 Issue**:
  - Issue 589 (Canonical LIR 仕様とバリデータ)
  - [553-refactor-ulisp-passes-and-compiler-architecture.md](closed/553-refactor-ulisp-passes-and-compiler-architecture.md) (コンパイラモジュール分離)
  - [587-extract-dsl-expansion-pass-before-macro-expander.md](closed/587-extract-dsl-expansion-pass-before-macro-expander.md) (Pass 015 Nanopass DSL 先行展開)
  - Issue 591 (コンパイラドライバおよびテストスイートの階層化)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/frontend/](../../ulisp/frontend/) (新設: Pass 010〜120 までの Nanopass, Macro, Desugar, Analysis, Closure Convert パス群)
- [ ] [ulisp/lir/](../../ulisp/lir/) (新設: LIR 定義, LIR Verifier, Pass 123〜132 SSA/最適化パス群)
- [ ] [ulisp/backend/](../../ulisp/backend/) (新設: Pass 140/141/142 x86-64, Pass 150 AArch64, Pass 160 C99, GC/ランタイム)
- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (2層分離に対応したドライバ呼出構造の再編)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (ディレクトリ再編に伴う依存関係および `compiler.scm` 統合スクリプトの更新)
- [ ] [ulisp/docs/pipeline_architecture.md](../../ulisp/docs/pipeline_architecture.md) (レイヤードアーキテクチャ図の更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/590-physical-layer-separation-of-frontend-and-backend`

1. **ディレクトリと名前空間の階層化**:
   - `ulisp/frontend/`: 高水準言語処理層（Pass 010〜120: Nanopass DSL、マクロ展開、脱糖、型推論、クロージャ変換等）
   - `ulisp/lir/`: 共通中間表現層（LIR 生成・最適化・SSA・検証）
   - `ulisp/backend/`: 低レベルコード生成層（Pass 140〜160: x86-64, AArch64, C99, アロケータ・GC）
2. **モジュール間インターフェースの純化**:
   - Frontend は Scheme ソースコードを入力とし、LIR AST のみを出力する。ターゲットアーキテクチャ固有のアセンブリ構文やレジスタ名に一切依存しない。
   - Backend は LIR AST のみを入力とし、アセンブリ/Cコードを出力する。高水準 Scheme 構文（`lambda`, `letrec`, `syntax-rules` 等）を直接参照しない。
3. **ビルドパイプラインの統合整合性維持**:
   - 単一自己完結ファイル `compiler.scm` への結合処理（Makefile）を更新し、セルフホスティングブートストラップ連鎖（`make bootstrap`）の完全な同一性を維持する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] パスおよびモジュールが `frontend/`, `lir/`, `backend/` に整理・配置されていること。
- [ ] `compiler.scm` の結合およびビルドが正常に完了し、回帰が発生しないこと。
- [ ] `make test`, `make test_c`, `make test_call_cc` が 100% PASS すること。
- [ ] `make bootstrap` による 3 段階ブートストラップ不動点（Fixed-Point）検証が一致（Diff ゼロ）すること。

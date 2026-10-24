---
ID: 597
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] IR Verifier 基盤の共通化・階層分離と LIR 検証パフォーマンス最適化 (ID: 597)

## 1. 概要 / Summary
ULisp コンパイラにおける各中間表現（Desugar, ANF, Closure, SSA, LIR）の検証ロジック（IR Verifier）を共通基盤として統一・階層分離し、特に LIR 層で顕在化している重複定義・多重走査および $O(N^2)$ 線形探索オーバーヘッドを解消する。

### 背景と課題:
1. **共通検証インフラの欠如**: 各 IR の Verifier（`compiler/verifier.scm` および `lir/lir_verifier.scm`）で AST 再帰走査ループが個別に重複実装されており、エラー発生時の文脈（関数名・親ブロック等）を伴う一貫した診断機構が不足している。
2. **LIR 仕様の二重管理**: Nanopass 言語定義（`L_lir_canonical`）と手書きの巨大な `case` 分岐（`lir_verifier.scm`）で命令構文が重複定義されており、保守性・拡張性のリスクとなっている。
3. **性能ボトルネック**: LIR 検証時に同一 AST に対して 4〜5 回のフルスキャンが走っており、さらにラベル解決が線形リスト探索（`memq` / `assq`）であるため大規模関数で二次関数的（$O(N^2)$）な遅延が生じている。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue:
  - Issue #576: [軽量 IR Verifier（Pass Checker）フレームワークの導入による中間不変条件の機械的検証](closed/576-implement-lightweight-ir-verifier-framework.md)
  - Issue #586: [Nanopass Framework DSL Phase 4: パイプライン統御・AST Diff トレーサおよび不変条件 Verifier 自動フック統合](closed/586-nanopass-framework-phase4-pipeline-observability-diff-trace-and-verifier-hooks.md)
  - Issue #589: [LIR (Low-level IR) 仕様の厳格化と不変条件バリデータ導入によるフロントエンド・バックエンド境界の確立](closed/589-establish-canonical-lir-specification-and-boundary-validator.md)
  - Issue #593: [LIR層: define-language L_lir_canonical の導入と lir_verifier 宣言的統合](closed/593-define-lir-canonical-language-and-verifier-integration.md)
- 関連仕様書:
  - [ulisp/docs/spec_lir.md](../../ulisp/docs/spec_lir.md)
  - [ulisp/docs/spec_pipeline.md](../../ulisp/docs/spec_pipeline.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/verifier.scm](../../ulisp/compiler/verifier.scm) (共通 Verifier 基盤・診断エンジン・レベル制御の実装)
- [ ] [ulisp/lir/lir_verifier.scm](../../ulisp/lir/lir_verifier.scm) (2層分離・Single-Pass走査・ハッシュ化最適化)
- [ ] [ulisp/lir/lir_lang.scm](../../ulisp/lir/lir_lang.scm) (Nanopass 構文定義との整合性確認)
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm) (コンパイラドライバおよびパスフック連携)
- [ ] [ulisp/tests/test_lir_verifier.scm](../../ulisp/tests/test_lir_verifier.scm) (パフォーマンス・診断・不変条件検証テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/597-unify-ir-verifier-framework-and-optimize-lir-performance`

1. **共通 Verifier 基盤（Unified IR Verifier Core）の構築**:
   - 共通 AST Visitor / Walker を導入し、走査ボイラープレートの排除とコンテキスト（関数名・ブロック・親ノード）追跡を実現。
   - 診断エンジン（`verifier-diagnostic`）による詳細位置・原因レポートと集約（Lintモード / Strictモード）の提供。
   - 検証レベル制御（Level 0: Off, 1: Boundary/Light, 2: Standard, 3: Strict/Paranoid）の統一導入。

2. **LIR Verifier の 2 層構造化**:
   - **Layer 1 (構文・オペランド仕様検証)**: テーブル駆動または Nanopass 診断によるアリティ・引数型検査への一元化。
   - **Layer 2 (CFG・セマンティクス不変条件検証)**: ラベル解決、重複定義検出、ブロックアリティ整合、スタックフレーム 8 バイト整合、セーフポイント整合などの純粋な意味論検査への特化。

3. **パフォーマンス最適化（$O(N^2) \to O(N)$ & 多重走査統合）**:
   - `validate-lir` 内での `(nanopass-ast-valid? ...)` 重複呼び出しの排除。
   - 命令構文検査とラベル収集・CFG検査を 1 回の走査（Single-Pass）に統合。
   - ラベル集合およびブロック引数の探索をリスト（`memq`/`assq`）からハッシュテーブルへ変更し、$O(N)$ 線形時間に最適化。
   - オペランド検査での `symbol->string` 頻発による文字列アロケーション負荷の低減。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 共通 Verifier 基盤経由で各 IR パス（ANF, SSA, LIR 等）の不変条件が統一的に検証できること
- [ ] LIR 検証において 4〜5 重の重複走査が解消され、単一パス（または最小走査）で完結すること
- [ ] ラベル解決がハッシュテーブル化され、大規模関数における検証時間が線形化されること
- [ ] 検証レベル（Level 0〜3）により、ベンチマークや本番ビルドで検証コストをゼロにできること
- [ ] 既存のテストスイート（`make test`）および `test_lir_verifier.scm` が 100% PASS すること
- [ ] 診断メッセージに違反箇所のコンテキスト（関数名や親ブロック）が正確に表示されること

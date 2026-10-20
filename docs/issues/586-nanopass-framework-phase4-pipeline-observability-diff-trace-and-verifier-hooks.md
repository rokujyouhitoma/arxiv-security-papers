---
ID: 586
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ARCH] Nanopass Framework DSL Phase 4: パイプライン統御・AST Diff トレーサおよび不変条件 Verifier 自動フック統合 (ID: 586)

## 1. 概要 / Summary
Nanopass Framework DSL Phase 1〜3 (Issue #581, #584, #585) により、構文脱糖、サブフォーム・エリップシス操作、および属性文法的解析パスの Nanopass 化基盤が整う。
コンパイラが 30 段以上の Nanopass で構成される大規模パイプラインに発展した際、最大の運用課題となるのは「デバッグ容易性（どのパスで意図しない S 式の変形が発生したかの即座の特定）」と「パイプライン全体の可視化・品質保証」である。

本 Issue（Phase 4）では、Nanopass Framework の完成形として以下の **コンパイラ検証・パイプライン統御プリミティブ** を実装する：
1. **言語メタ情報インスペクタ (`language->s-expression` / `language-declaration`)**:
   - 定義された各言語の生成規則や終端記号のメタ情報をリフレクション・取得し、Markdown ドキュメントや Mermaid 構文遷移図を完全自動生成するメタ API。
2. **AST Diff ステップトレーサ (`trace-define-pass`)**:
   - パスの入力 AST と出力 AST を自動で unparse し、その差分（AST Diff）を実行時にステップ表示するデバッグ専用ラッパー構文。
3. **差分アサーション・不変条件自動検証フック (Invariant Verifier Hook)**:
   - `define-pass` の入口と出口に型検査・スキーマ検査フックを暗黙に挿入し、Issue #576 で構築した軽量 IR Verifier (`compiler/verifier.scm`) と完全連携。デバッグモード（`DEBUG_PASS=1`）時にパス終了直後での構文不変条件の破れを即座に検知・停止するフェイルファスト機構。

---

## 2. トレーサビリティ / Traceability
- 先行研究系譜: Keep & Dybvig, "A Nanopass Framework for Commercial Compiler Development" (ICFP 2013 / Chez Scheme)
- DSN-33 コンパイラアーキテクチャ仕様
- 関連 Issue:
  - [581-implement-nanopass-framework-dsl-and-migrate-compiler-passes.md](581-implement-nanopass-framework-dsl-and-migrate-compiler-passes.md) (Phase 1)
  - [584-nanopass-framework-phase2-ellipsis-subforms-and-normalization.md](584-nanopass-framework-phase2-ellipsis-subforms-and-normalization.md) (Phase 2)
  - [585-nanopass-framework-phase3-catamorphism-extra-values-and-analysis-passes.md](585-nanopass-framework-phase3-catamorphism-extra-values-and-analysis-passes.md) (Phase 3)
  - [closed/576-implement-lightweight-ir-verifier-framework.md](closed/576-implement-lightweight-ir-verifier-framework.md) (IR Verifier)
- 関連ファイル:
  - [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm)
  - [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)
  - [ulisp/compiler/verifier.scm](../../ulisp/compiler/verifier.scm)
  - [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm) (`trace-define-pass`, `language->s-expression`, Verifier Hook の実装)
- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm) (言語リフレクション情報および差分比較器の実装)
- [ ] [ulisp/compiler/verifier.scm](../../ulisp/compiler/verifier.scm) (Nanopass 言語スキーマと verifier の自動連携)
- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (`--trace-passes` オプション配線)
- [ ] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm) (トレーサおよび Verifier Hook のテスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/586-nanopass-framework-phase4-pipeline-observability-diff-trace-and-verifier-hooks`

1. **メタ情報インスペクタの実装**:
   - `(language->s-expression 'L_name)` により、終端記号と全プロダクション規則のリストを S 式として返却。
   - `tools/generate_nanopass_docs.scm` スクリプトを用意し、リポジトリ内の各 IR の仕様書と Mermaid 遷移図を自動生成。
2. **`trace-define-pass` マクロの実装**:
   - `define-pass` をラップし、実行時に ANSI カラーコードを用いて `--- [PASS: pass-name] ---`、入力 S 式、出力 S 式、および変更箇所の Diff を端末へ標準エラー出力。
3. **Verifier Hook の透過的埋め込み**:
   - `define-pass` の展開コード冒頭で `(verify-language L_src ir)`、末尾で `(verify-language L_dst res)` を呼び出すラッパーを生成。
   - 環境変数 `ULISP_VERIFY_PASS=1` またはコンパイルオプションで制御可能にする。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `language->s-expression` により言語メタデータが S 式で正しく取得できること
- [ ] `trace-define-pass` によりパス実行時の AST Diff がカラー表示できること
- [ ] 不正な構文の出力時に Verifier Hook が即座に例外を発生させて停止すること
- [ ] 全パス単体テスト（`make -C ulisp test_all_passes`）および 3-Stage Bootstrap 固定点検証（`make -C ulisp bootstrap_verify`）が 100% PASS すること
- [ ] 相対パスのみを使用し、絶対パスが含まれないこと

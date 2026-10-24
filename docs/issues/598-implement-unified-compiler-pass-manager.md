---
ID: 598
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 統一 Pass Manager の導入によるパイプライン制御・最適化レベルスケジューリング・観測性の一元化 (ID: 598)

## 1. 概要 / Summary
ULisp コンパイラドライバおよびパイプライン実行において、約30におよぶ Nanopass / コンパイラパスが直列にハードコード接続されている現状を解消し、LLVM / GCC 相当の統一 **Pass Manager（パイプライン統御・最適化スケジューラ）** 基盤を導入する。

### 背景と課題:
1. **固定的な直列実行**: パス順序がドライバ関数内で静的に結線されており、`-O0`, `-O1`, `-O2` などの最適化レベルに応じた柔軟なパスの有効化・無効化やパイプラインの組み替えが困難。
2. **パス依存関係の未検証**: 各パスが前提とする中間不変条件（例: 「Pass 070 ANF 変換済みであること」「Pass 110 クロージャ変換済みであること」等）の事前・事後要件が明示的な依存グラフとして管理されていない。
3. **観測性基盤の分散**: パスごとの実行時間・メモリ消費量のプロファイリング、中間 IR のダンプ（`--dump-ir=<pass>`）、パス前後の AST Diff 表示が各所に散在しており、一括制御ができない。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue:
  - Issue #586: [Nanopass Framework DSL Phase 4: パイプライン統御・AST Diff トレーサおよび不変条件 Verifier 自動フック統合](closed/586-nanopass-framework-phase4-pipeline-observability-diff-trace-and-verifier-hooks.md)
  - Issue #591: [コンパイラドライバおよびテストスイートの階層化](closed/591-hierarchical-compiler-driver-and-test-suites.md)
  - Issue #597: [IR Verifier 基盤の共通化・階層分離と LIR 検証パフォーマンス最適化](597-unify-ir-verifier-framework-and-optimize-lir-performance.md)
- 関連仕様書:
  - [ulisp/docs/pipeline_architecture.md](../../ulisp/docs/pipeline_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm) (新規: 統一 Pass Manager 基盤)
- [ ] [ulisp/driver/driver.scm](../../ulisp/driver/driver.scm) (ドライバ連携・パイプライン起動ルーチン)
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm) (コンパイラエントリポイントへの統合)
- [ ] [ulisp/tests/test_pass_manager.scm](../../ulisp/tests/test_pass_manager.scm) (新規: パススケジューラ・依存関係・-Oフラグ検証テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/598-implement-unified-compiler-pass-manager`

1. **Pass Descriptor & Pipeline Registry の定義**:
   - 各パスのメタデータ（ID、名前、カテゴリ: Frontend/Middle/Backend、入力言語、出力言語、要求前提条件、オプトイン/オプトアウト設定）を登録するレジストリを構築。
2. **最適化レベル（-O0 / -O1 / -O2）に応じた動的スケジューリング**:
   - `-O0`: 最小限の脱糖・正規化・低レベル化のみ実行（高速コンパイル）。
   - `-O1`: 基本的なインライン展開、CP0（定数畳み込み）、デッドコード削除。
   - `-O2`: LVN、高度エスケープ解析、スタック割当、分岐融合、SSA 最適化を全開。
3. **パス境界フックの統合**:
   - Issue #597 の IR Verifier と連携し、パス実行直後の自動バリデーションフックを提供。
   - `--time-passes` による各パスのミリ秒・アロケーション量プロファイラ出力。
   - `--dump-ir=<pass>` および `--print-after-all` による中間 AST 観測機構。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] パスが Pass Manager 経由で登録・順序制御・実行できること
- [ ] `-O0`, `-O1`, `-O2` フラグによって実行パス群が動的に切り替わること
- [ ] `--time-passes` で各パスの実行時間プロファイルが集計表示されること
- [ ] `--dump-ir` で任意パスの出力 AST が正しくダンプされること
- [ ] 既存のテストスイート（`make test`）が 100% PASS すること

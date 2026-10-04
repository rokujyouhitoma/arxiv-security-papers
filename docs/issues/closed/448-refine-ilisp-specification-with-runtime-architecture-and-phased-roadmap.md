---
ID: 448
種別: Documentation / Architecture
優先度: High
ステータス: Closed (Completed)
---

# [DOC/ARCH] ILISP 実装前処理系工学仕様精緻化と段階的ロードマップ策定 (ID: 448)

## 1. 概要 / Summary
ILISP (Intelligence LISP) の本格実装着手に先立ち、処理系工学（PLC）専門家視点から洗い出された 6 つの技術的課題・フリクション（ConsセルvsPythonリスト表現、Scope Sets段階移行、set!ボックス化戦略、手書き再帰下降リーダー、call/cc One-shot保証とdynamic-wind、3本柱バックエンドのオプショナル・アクセラレータ構成）に対する具体的解決仕様を `DSN-31` および `ilisp/docs/` に統合・精緻化する。
あわせて、初日に「手書きリーダー + 最小AST + 基本評価器 + REPL」を自律稼働させる「第1期 (Phase 1: 最小構成 Kernel ILISP)」のマイルストーンを定義する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md` (6大課題の解決仕様および段階的ロードマップ統合)
- [x] `ilisp/docs/SPEC_R7RS.md` (データ型仕様、Phase 1 サポート範囲、Lazy View 仕様の追記)
- [x] `ilisp/docs/BOOTSTRAP.md` (Phase 1 手書きリーダー・最小インタプリタからのブートストラップ連鎖詳細化)
- [x] `docs/issues/README.md` (Issue 448 登録)

---

## 3. 実装方針 / Implementation Plan
Target Branch: `docs/448-refine-ilisp-specification-with-runtime-architecture-and-phased-roadmap`

1. **6大技術課題の具体的アーキテクチャ仕様定義**:
   - **データ表現**: `Cons(car, cdr)` を主軸とし、Python リスト走査用 `SequenceView(seq, offset)` と透過的境界アンラッププロトコルを定義。
   - **マクロ段階移行**: Phase 1 は単純構文置換マクロ (`defmacro` / 限定的 `syntax-rules`) でブートストラップを立ち上げ、Phase 2 で本格 Scope Sets マクロ展開器を導入。
   - **レキシカル環境と代入**: `set!` 対象変数を静的解析で `Cell(val)` にボックス化し、Python AST トランスパイル時の `nonlocal` 制約を根本回避。
   - **リーダー方式**: ソースマップ位置追跡・リーダーマクロ拡張・ストリーム処理に最適な手書き再帰下降リーダー（Tokenizer + Reader）を採用。
   - **`call/cc` と `dynamic-wind`**: `invoked: bool` による One-shot 厳格保証、および Python の `try...finally` と等価な `dynamic-wind` スタックフレーム管理。
   - **3本柱バックエンドの段階的導入**: Phase 1 は純粋 Python インタプリタ & AST トランスパイラ（ゼロ依存完結）、Phase 2 に C99 AOT、Phase 3 に Rust VM（オプショナル・アクセラレータ）。
2. **段階的開発マイルストーン (Phased Milestones) の明記**:
   - Phase 1 (Minimal Self-Contained Kernel ILISP): 手書き Reader, 最小 AST, 純粋 Python Eval/Apply, 基本四則演算・リストプリミティブ, REPL
   - Phase 2 (Advanced Macro & Transpiler): Scope Sets 衛生的マクロ, Python AST トランスパイラ, C99 AOT トランスパイラ, S-OKF 連携
   - Phase 3 (Extreme Performance & VM): Rust Standalone Bytecode VM (NaN-Boxing, No-GIL), 完全セルフホスティング
3. **品質管理ゲート検証**:
   - `make check_format` (isort, black, flake8)
   - `make static_analysis` (py_compile, radon, mypy)
   - `make test` (pytest 100% PASS)
   - 相対パスリンクガバナンス (絶対パス 0 件)

---

## 4. 完了条件 / Success Criteria (DoD)
- [x] DSN-31 に 6 つの技術課題の解決仕様および段階的ロードマップが網羅的に反映されていること
- [x] `ilisp/docs/SPEC_R7RS.md` にデータ型仕様および Phase 1 サポート範囲が明記されていること
- [x] `ilisp/docs/BOOTSTRAP.md` に Phase 1 から始まる具体的なブートストラップ手順が定義されていること
- [x] すべての内部リンクが相対パスリンク規約に 100% 準拠していること
- [x] 品質管理ゲート (`make check_format`, `make static_analysis`, `make test`) が 100% PASS すること

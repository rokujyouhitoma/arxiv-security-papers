---
ID: 443
種別: Feature
優先度: High
ステータス: Closed (Resolved)
---

# [FEAT] ILISP (Intelligence LISP) R7RS コアアーキテクチャ設計・包括仕様書策定および受入基盤の初期整備 (ID: 443)

## 1. 概要 / Summary
AI・インテリジェンス（Intelligence / IKE / AI）特化型の次世代Lisp方言 **ILISP (Intelligence LISP)** の公式アーキテクチャ設計書（DSN-31）を策定し、言語仕様・独立ドキュメント体系（`ilisp/docs/`）および将来のセルフホスティングを見据えたStage-0受入基盤を初期整備する。

R7RS-small Scheme世界標準規格をコア仕様とし、Python双方向相互運用（Python Interop）とネイティブC-AOTコンパイル（Native AOT）のデュアルバックエンド、現場復帰型コンディション機構、および3段階自己完結ブートストラップ（Stage-0〜Stage-2）を規定する。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [AGENTS.md](../../.agents/AGENTS.md) (15専門エージェントガバナンス規約)
  - [DSN-25 Pure-Python Packrat PEG Parser Engine](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (自己ホスティング・ブートストラップ先例)
  - [DSN-29 Python-LISP 統合アーキテクチャ設計仕様書 (pylisp)](../designs/DSN-29-python_lisp_integrated_architecture_specification.md) (DynamicVar / Atom / Condition / miniKanren 資産)
  - [Revised^7 Report on the Algorithmic Language Scheme (R7RS-small)](https://small.r7rs.org/)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md](../designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) (包括設計仕様書 新設)
- [ ] [docs/README.md](../README.md) (包括設計書体系 DSN-31 登録)
- [ ] [ilisp/docs/README.md](../../ilisp/docs/README.md) (ILISP言語概要・クイックスタート)
- [ ] [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md) (R7RS準拠マトリクス・文法仕様)
- [ ] [ilisp/docs/BOOTSTRAP.md](../../ilisp/docs/BOOTSTRAP.md) (セルフホスティング・ブートストラップ連鎖仕様)
- [ ] [docs/issues/README.md](README.md) (Issue台帳同期)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/443-design-and-initialize-ilisp-r7rs-core-runtime`

1. **包括設計書 DSN-31 の策定**:
   - `docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md` を作成。
   - 言語哲学（Intelligence + IKE + AI + LISP）、R7RS-small仕様準拠方針、デュアルバックエンド（Python AST & C-AOT）、コンディションシステム、S-OKFドキュメントモデル、3段階セルフホスティング（Stage-0 Pythonホスト → Stage-1 ILISP-in-ILISP → Stage-2 不動点検証）を詳述。
2. **ILISP独立ドキュメント群 (`ilisp/docs/`) の新設**:
   - `ilisp/docs/README.md`: 言語概要、哲学、Hello World、REPL、Python Interopの基本例。
   - `ilisp/docs/SPEC_R7RS.md`: R7RS-small 規格（データ型、式、マクロ、ライブラリ）のサポート計画。
   - `ilisp/docs/BOOTSTRAP.md`: Stage-0（Python）から Stage-2 への自己完結ブートストラップ連鎖および不動点テスト戦略の定義。
3. **プロジェクト統括目次の更新**:
   - `docs/README.md` に DSN-31 を正式登録。
4. **品質ゲートの完全通過検証**:
   - 相対パスリンクの100%整合性確認（デッドリンクゼロ）。
   - `make check_format` および `make static_analysis` のパス確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md` が承認水準で作成されていること。
- [x] `ilisp/docs/` 配下に `README.md`, `SPEC_R7RS.md`, `BOOTSTRAP.md` が作成され、自己完結していること。
- [x] 将来のセルフホスティング（Stage-0〜Stage-2）の道筋とアーキテクチャが明文化されていること。
- [x] `docs/README.md` に DSN-31 が追加・同期されていること。
- [x] リポジトリ内全リンクが相対パスで記載され、404エラーがないこと。
- [x] `make check_format` および `make static_analysis` がエラー 0 件で通過すること。
- [x] [docs/issues/README.md](README.md) に本Issueが反映されていること。

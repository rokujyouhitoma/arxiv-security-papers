---
ID: 444
種別: Feature
優先度: High
ステータス: Closed (Resolved)
---

# [FEAT] ITスペシャリスト（プログラミング言語・コンパイラ処理系 / PLC）エージェントの創設と 16大専門エージェントガバナンスの同期 (ID: 444)

## 1. 概要 / Summary
ILISP (Intelligence LISP) 言語処理系基盤の本格開発（インタプリタ、AOTコンパイラ、PEGパーサ、S式Reader、GC、仮想マシン、セルフホスティング連鎖）に伴い、経済産業省・IPA「ITスキル標準（ITSS V3 2011）」ITスペシャリスト（テクノロジ系）の類型として、言語処理系・コンパイラ工学に特化した **ITスペシャリスト（プログラミング言語・コンパイラ処理系 / PLC: Programming Languages & Compilers Specialist）** エージェントを `.agents/agents/` 配下に新設する。
併せて、[AGENTS.md](../../.agents/AGENTS.md) および [README.md](../../README.md) のガバナンス記述を従来の 15専門エージェントから 16専門エージェント体制へと同期・更新する。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [AGENTS.md](../../.agents/AGENTS.md) (プロジェクトガバナンス & マルチエージェント審議規約)
  - [it-specialist-information-retrieval.agent.md](../../.agents/agents/it-specialist-information-retrieval.agent.md) (ITSS テクノロジ系エージェント類型基準)
  - [DSN-31 ILISP R7RS コアアーキテクチャ設計仕様書](../designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) (対象処理系基盤)
  - 経済産業省・IPA「ITスキル標準（ITSS V3 2011）」ITスペシャリスト（テクノロジ系）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [.agents/agents/it-specialist-programming-languages-and-compilers.agent.md](../../.agents/agents/it-specialist-programming-languages-and-compilers.agent.md) (新規エージェント定義)
- [ ] [.agents/AGENTS.md](../../.agents/AGENTS.md) (16専門エージェントへの同期更新)
- [ ] [README.md](../../README.md) (ガバナンス記述・エージェント数 16 への同期)
- [ ] [docs/issues/README.md](README.md) (Issue台帳同期)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/444-add-programming-languages-and-compilers-specialist-agent`

1. **新専門エージェント定義の作成**:
   - `.agents/agents/it-specialist-programming-languages-and-compilers.agent.md` を作成。
   - インタプリタ、AOT/JITコンパイラ、パーサー、GC、VM、中間表現（CPS/ANF）、衛生的マクロ（syntax-rules）、およびセルフホスティング・ブートストラップ連鎖に関する専門責務、行動規範、機能別応答プロトコル、初期応答を完全網羅。
2. **ガバナンス規約の同期更新**:
   - `.agents/AGENTS.md` の審議体制リストに「16. IT Specialist (Programming Languages & Compilers)」を追加。
   - `README.md` の第8章・第9章（品質管理とガバナンス）におけるエージェント数表記を 16 に更新。
3. **品質ゲートと整合性検証**:
   - `make check_format`
   - `make static_analysis`
   - `make test`

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `.agents/agents/it-specialist-programming-languages-and-compilers.agent.md` が規定フォーマットに準拠して配備されていること。
- [x] `.agents/AGENTS.md` のエージェント一覧が 16 専門エージェントに更新されていること。
- [x] `README.md` のガバナンス記述が 16 専門エージェントに同期されていること。
- [x] 各 Markdown ファイル内の相対パスリンクが 100% 正常であること。
- [x] `make check_format` および `make static_analysis` がエラー 0 件で通過すること。
- [x] [docs/issues/README.md](README.md) の台帳が更新されていること。

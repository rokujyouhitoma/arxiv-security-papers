---
name: strategic-innovation-planning
description: 全 13 大専門エージェントの多角的審議を軸に、8時間=1日AI完遂規模のイノベーション計画を人間介入ゼロで自動策定・検証・完遂する標準プランニング＆品質ゲート統合プロシージャスキル。
---

# strategic-innovation-planning

本スキルは、**全体管理（PM）** の統括のもと、全 13 大専門エージェント（ST, SA, SC, NW, DB, AU, QA, PM, SM, EP, IR, EDU, UIUX）による多角的審議、5大変更影響アセスメント (Quality Gate 1)、データ構造・相対パス設計 (Quality Gate 2)、統合自動検証スキル `verify-quality-gates` のアサート (Quality Gate 3)、およびシステム監査人 (AU) の最終適合判定 (Quality Gate 4) を経て、**人間介入不要で 1 日（8時間）規模のパイプライン拡張計画の策定・実装・検証を自動完遂する** 標準プロシージャスキルです。

---

## 🏛️ 4 大品質ゲート & 13 大エージェント審議体制 (Quality Gates & Architecture)

```
[Quality Gate 1] 企画・変更影響アセスメント (ST / SM / SA / AU)
       ├── 13エージェントヒアリング & イノベーション企画の採択
       └── 5大変更影響アセスメント (パイプライン運用、データ構造、セキュリティ、品質、サマリーUX)
       ↓
[Quality Gate 2] 多段階設計・データ構造・相対パスガバナンス (SA / 指名スペシャリスト)
       ↓
[Quality Gate 3] 統合全自動品質検証ゲート (`verify-quality-gates` スキル適用)
       ├── ① Python 構文コンパイル (py_compile エラー 0件)
       ├── ② Google OKF v0.2 仕様適合 (YAML フロントマター 8大必須キー検証)
       ├── ③ 相対パスガバナンス (絶対パス違反: 完全 0 件)
       ├── ④ 5階層サマリー構造 & 100% 日本語化アサーション
       └── ⑤ 冪等性 & Rawデータトレーサビリティ検証
       ↓
[Quality Gate 4] AU 最終適合監査 & PM マージ統合承認 (AU / PM)
```

| ID | エージェント名称 | 専門領域と審議ロール |
|:---:|---|---|
| **ST** | `information-technology-strategist` | 企画統括・サマリー層別トレンド分析価値定義 |
| **SA** | `systems-architect` | パイプラインアーキテクチャ・モジュール構造・データフロー設計 |
| **SC** | `information-security-specialist` | arXiv `cs.CR` セキュリティドメイン分類・OKF trustアテスト |
| **NW** | `network-specialist` | arXiv API / RSS フォールバック通信・レート制御 |
| **DB** | `database-specialist` | Raw保存構造・`processed_papers.json` 冪等性管理 |
| **AU** | `systems-auditor` | 監査・ガバナンス・DoD最終評価 [Quality Gate 4] |
| **QA** | `software-quality-assurance-specialist` | 全自動品質管理ゲートアサート [Quality Gate 3] |
| **PM** | `project-manager` | プロジェクト統括・WBS・DoD達成評価・マージ統合 |
| **SM** | `information-technology-service-manager` | 1日4回定期バッチ運用管理・ログ監視・影響評価 [Quality Gate 1] |
| **EP** | `embedded-systems-specialist` | 組込み/IoTセキュリティ論文タグ分類サポート |
| **IR** | `it-specialist-information-retrieval` | `pdftotext` 全文抽出・要約テキスト抽出・日本語定訳統一 |
| **EDU** | `education-specialist` | 専門用語可読性・要約文章の厳密性検証 |
| **UIUX** | `ui-ux-designer` | Markdown 表形式視視認性・レイアウト構成 |

---

## 📋 実行手順 (Execution Instructions)

### Step 1: 全 13 エージェント多角的要件聴取 & 最優良施策選定
1. 全 13 大専門エージェントの観点から現状の課題、パイプラインのボトルネック、OKFデータの利便性を洗い出す。
2. データ品質・フェッチ堅牢性・サマリー視認性の向上に直結する改善項目を選定する。

### Step 2: [Quality Gate 1: 企画・5大変更影響アセスメント]
1. 採択された施策に対し、**SM (ITサービスマネージャ) & SA (システムアーキテクト)** 主導で以下の 5 大観点の影響アセスメントを行う：
   - **① パイプライン運用・可用性**: API/RSS通信、バックオフ、バッチ処理時間への影響。
   - **② アーキテクチャ・データ構造**: JSON/Markdownフォーマット、OKF v0.2互換性への影響。
   - **③ セキュリティ・ガバナンス**: 通信信頼性、アテストステーション、データ完全性。
   - **④ 品質・回帰テスト**: 既存データ保持、`processed_papers.json` 重複排除への影響。
   - **⑤ サマリー表現・UX**: 5階層サマリーの可読性、日本語表形式の品質。
2. Gate 1 レビューをクリア後、SA が指名スペシャリストを設定。

### Step 3: Issue 起票・`polish-issue` & [Quality Gate 2: 設計レビュー]
1. `create-issue` により Issue ファイルを作成し、`docs/issues/README.md` を更新。
2. `polish-issue` スキルを適用し、要件定義・DoD・変更手順を磨き上げる。
3. OKFデータ構造、相対パス設計のアサーションを行う [Quality Gate 2]。

### Step 4: 設計・実装 & [Quality Gate 3: 統合自動検証] & [Quality Gate 4: AU 監査]
1. Pythonコード、テンプレート、ドキュメントを実装・更新。
2. `verify-quality-gates` スキルを実行し、すべての品質管理ゲートを 100% クリアアサートする [Quality Gate 3]。
3. システム監査人 (AU) が全 DoD 達成状況を監査し【適合 (PASS)】を宣言する [Quality Gate 4]。

### Step 5: Issue クローズ & 自動コミット・統合
1. Issue の状態を `Closed` に更新し、`docs/issues/closed/` へ移動。
2. `docs/issues/README.md` の完了台帳を更新。
3. conventional commit メッセージでコミットを生成し、`main` ブランチへマージ統合。

---
ID: 166
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/UIUX] /dashboard tab=graph における Glassmorphic ツールチップ・操作ガイド基盤および UI/UX 認知的負荷軽減の実装 (ID: 166)

## 1. 概要 / Summary
`/dashboard.html?tab=graph`（Knowledge & CTI Graph ワークスペース）において、グラフモード切替（Context Mesh / CTI Graph）、エンティティフィルタ、確信度（Confidence Tier）フィルタ、推論ルール（EIROM）選択、最小次数（Min Degree）フィルタ、孤立ノード除外、クエリコンソール（`gaps`, `cwe:`, `ego:`, `match:`, `path:`）、および各種プリセットなど、高度なセキュリティ分析機能が急速に拡充された。

これに伴い、UI上のコントロール要素・略語・パラメータが過密化し、開発者やセキュリティアナリストであっても「各ボタンやパラメータが何を意味し、何を実行するものなのか」の認知負荷が極めて高くなっている。

本 Issue では、**UI/UX & Documentation Designer** エージェント主導のもと、以下の機能群を導入し、直感的で迷わない Graph UX を実現する：
1. **Glassmorphic リッチツールチップ基盤（`data-tooltip` / `tooltip-engine`）の実装**:
   - 各ボタン、セレクトボックス、入力フィールド、バッジ、トグルスイッチに対し、ホバー・フォーカス時に即時表示される統一デザインの洗練されたツールチップ（機能概要、操作時の効果、入力例・ショートカット）を配備。
2. **コントロールデッキ用インラインヘルプバッジ（`ⓘ` アイコン）**:
   - 複雑な概念（`CONFIDENCE`, `RULE`, `MIN DEGREE`, `GRAPH MODE`）のラベル脇に情報アイコンを配置し、タップ・ホバーで詳細解説ポップオーバーを展開。
3. **Graph 操作ガイド & 用語チートシートドロワー（Quick Guide Drawer）**:
   - ツールバー右上に `❓ ガイド (Help)` ボタンを新設。クリックで右側からスライドインするグラスモルフィックな「Graph 機能 & クエリ操作ガイド」ドロワーを展開。
   - モード別特徴、確信度ティアの判定根拠、クエリ構文のチートシート、マウス・キーボード操作（パン、ズーム、クリックフォーカス、`H` キー等）を完全日本語で一覧化。
4. **Canvas 内ホバーカードの視認性・説明力向上**:
   - ノードホバー時およびエッジホバー時の情報カードに、「クリックすると何が起こるか（例: クリックで2ホップエゴネットワークにフォーカス）」などのマイクロガイダンスを付与。

---

## 2. トレーサビリティ / Traceability
- ユーザーフィードバック: 「UIUXが主導でツールチップの実装を検討してほしい。特に http://localhost:8000/dashboard.html?tab=graph において、機能が複雑なので、もはや私でも機能がどういうものなのかわからなくなり始めている。」
- 関連 Issue:
  - Issue 138: `/dashboard` 専用 Knowledge & CTI Graph 画面（`tab=graph`）の独立実装
  - Issue 139: レイアウト再設計と要素重なり解消
  - Issue 140: ノード半径の次数スケーリング
  - Issue 143: 孤立ノード非表示トグル
  - Issue 144: 最小次数フィルタ（Min Degree）
  - Issue 145: エゴネットワーク（フォーカス）モード
  - Issue 164: エッジ確信度＆推論ルール絞り込みとエビデンス表示
  - Issue 165: 全量 OKF アーカイブへの推論ルール適用と確信度付与

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/dashboard.html](file:///workspace/arxiv-security-papers/site/dashboard.html): Graph タブ HTML 構造、コントロールデッキ、ヘルプドロワー、ツールチップ CSS / JS
- [ ] [site/style.css](file:///workspace/arxiv-security-papers/site/style.css): グラスモルフィックツールチップ、アニメーション、ヘルプドロワー用スタイル
- [ ] [tests/web/test_dashboard_graph_tab.py](file:///workspace/arxiv-security-papers/tests/web/test_dashboard_graph_tab.py): ツールチップ属性およびヘルプドロワー要素の DOM 構造検証テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/166-graph-tooltips-and-quick-guide`

1. **デザインシステム・CSS 仕様設計（UI/UX & Documentation Designer）**:
   - ガラスモルフィズム（`backdrop-filter: blur(16px)`, 微細な境界線 `border: 1px solid rgba(255,255,255,0.15)`, 高コントラストシャドウ）に準拠したツールチップ CSS クラス（`.glass-tooltip`, `[data-tooltip]`）の定義。
   - スムーズなフェードイン・スケールイン微細アニメーション（`transition: opacity 0.15s ease, transform 0.15s ease`）。
   - 画面端での見切れを防止するスマートな自動位置調整（`top`, `bottom`, `left`, `right`）。
2. **Graph コントロールデッキ全要素へのツールチップ配置**:
   - `GRAPH MODE`: Context Mesh（論文間の意味的類似クラスタ網）と CTI Graph（MITRE ATT&CK / CWE / 論文の脅威インテリジェンス網）の違いと切り替え。
   - `FILTER`: Paper（論文ノード）、ATT&CK（攻撃手法）、CWE（脆弱性弱点）、Gaps（未研究領域）。
   - `CONFIDENCE`: All（全件）、Med+（確信度0.5以上）、High Only（確信度0.8以上の厳格ルール合致エッジ）。
   - `RULE`: 直接正規表現一致（Conf=1.0）、タイトル手法名合致（0.8）、タイトルキーフレーズ合致（0.5）、アブストラクト意味語彙（0.4）の各推論アルゴリズム。
   - `MIN DEGREE`: 次数（接続エッジ数）によるハブノード抽出フィルタ。
   - `孤立ノード除外`: 接続エッジを持たないノードの一括非表示。
   - `全画面 / ヘッダー切替`: ワークスペース最大化トグル（ショートカット: `H`）。
   - `探索クエリ入力欄 & 実行・リセット`: 構文ヒントと使用例。
   - `シナリオプリセットボタン群`: 各プリセットが何を抽出しハイライトするかの詳細解説。
3. **Graph 操作ガイド & 用語チートシートドロワー（Quick Guide Drawer）の実装**:
   - コントロールデッキ右端に `❓ ヘルプ (Help)` ボタンを追加。
   - クリックで開閉するスライドインパネル（閉じるボタン `✕` または `Esc` キーで閉じる）。
   - 内容：
     - ① 基本操作（ドラッグパン、ホイールズーム、ノードクリックでフォーカス、背景ダブルクリックでリセット）
     - ② グラフモード解説（Context Mesh vs CTI Graph）
     - ③ 確信度ティア（HIGH/MED/LOW）と EIROM 推論ルールの意味
     - ④ CTI クエリ構文チートシート（`gaps`, `cwe: <ID>`, `ego: <ID> <hops>`, `match: <term>`, `path: <from>-><to>`）
4. **Canvas ノード・エッジホバーカードへのガイダンス追記**:
   - ノードホバー時: 下部に「💡 クリックでこのノード中心のエゴネットワークを表示」のヒントを付与。
   - エッジホバー時: ルール名・確信度・エビデンススニペットに加え、「確信度と推論ルールに基づき結合」の明示。
5. **テストと検証**:
   - pytest による DOM 要素・属性（`data-tooltip`, ヘルプドロワー ID, アイコン等）の検証。
   - Xenon Rank A、Mypy `--strict`、Flake8 / Black フォーマットチェック。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `site/dashboard.html` 内の Graph コントロールデッキ上の全ボタン、入力欄、セレクト、トグルに分かりやすい日本語ツールチップが付与されていること。
- [ ] 複雑な概念（`CONFIDENCE`, `RULE`, `MIN DEGREE` 等）に情報アイコン（`ⓘ`）が配置され、機能解説が表示されること。
- [ ] ツールバーに `❓ ヘルプ` ボタンが配置され、クリックで「Graph 操作ガイド & 用語チートシート」ドロワーが開閉できること。
- [ ] ドロワー内にマウス操作、クエリ構文例、各フィルタの意味が明瞭に整理されていること。
- [ ] Canvas 内ノードホバー時に操作誘導ヒント（クリックでフォーカス）が表示されること。
- [ ] `tests/web/test_dashboard_graph_tab.py` にツールチップおよびヘルプドロワーの構造検証テストが追加されパスすること。
- [ ] `make py_compile`, `make check_format`, `make static_analysis` がすべて 100% PASS すること。

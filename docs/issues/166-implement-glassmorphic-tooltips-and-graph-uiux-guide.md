---
ID: 166
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/UIUX] /dashboard tab=graph における Glassmorphic ツールチップ・操作ガイド基盤および UI/UX 認知的負荷軽減の実装 (ID: 166)

## 1. 概要 / Summary
`/dashboard.html?tab=graph`（Knowledge & CTI Graph ワークスペース）において、グラフモード切替（Context Mesh / CTI Graph）、エンティティフィルタ、確信度（Confidence Tier）フィルタ、推論ルール（EIROM）選択、最小次数（Min Degree）フィルタ、孤立ノード除外、クエリコンソール（`gaps`, `cwe:`, `ego:`, `match:`, `path:`）、および各種プリセットなど、高度なセキュリティ分析機能が急速に拡充された。

これに伴い、UI上のコントロール要素・略語・パラメータが過密化し、開発者やセキュリティアナリストであっても「各ボタンやパラメータが何を意味し、何を実行するものなのか」の認知負荷が極めて高くなっている（ユーザー報告:「機能が複雑なので、もはや私でも機能がどういうものなのかわからなくなり始めている」）。

本 Issue では、**UI/UX & Documentation Designer** エージェント主導のもと、以下の機能群を導入し、直感的で迷わない Graph UX を実現する：
1. **Glassmorphic リッチツールチップ基盤（`data-tooltip` / CSS & JS ポジショニング）の実装**:
   - 各ボタン、セレクトボックス、入力フィールド、バッジ、トグルスイッチに対し、ホバー・フォーカス時に即時表示される統一デザインの洗練されたツールチップ（機能概要、操作時の効果、入力例・ショートカット）を配備。
2. **コントロールデッキ用インライン情報バッジ（`ⓘ` アイコン）**:
   - 複雑な概念（`CONFIDENCE`, `RULE`, `MIN DEGREE`, `GRAPH MODE`）のラベル脇に `ⓘ` 情報アイコンを配置し、ホバー・タップで詳細解説ポップオーバーを展開。
3. **Graph 操作ガイド & 用語チートシートドロワー（Quick Guide Drawer）**:
   - ツールバー右端に `❓ ガイド (Help)` ボタンを新設。クリックで右側からスライドインするグラスモルフィックな「Graph 機能 & クエリ操作ガイド」ドロワーを展開。
   - モード別特徴、確信度ティアの判定根拠、クエリ構文のチートシート、マウス・キーボード操作（パン、ズーム、クリックフォーカス、`H` キー等）を完全日本語で一覧化。
4. **Canvas 内ホバーカードの視認性・説明力向上**:
   - ノードホバー時およびエッジホバー時の情報カードに、「クリックすると何が起こるか（例: 💡 クリックでこのノード中心のエゴネットワークを表示）」などのマイクロガイダンスを付与。

---

## 2. トレーサビリティ / Traceability
- **ユーザー要求**: 「UIUXが主導でツールチップの実装を検討してほしい。特に http://localhost:8000/dashboard.html?tab=graph において、機能が複雑なので、もはや私でも機能がどういうものなのかわからなくなり始めている。」
- **関連 Issue**:
  - Issue 138: `/dashboard` 専用 Knowledge & CTI Graph 画面（`tab=graph`）の独立実装
  - Issue 139: レイアウト再設計と要素重なり解消
  - Issue 140: ノード半径の次数スケーリング（`R ∝ √(1+k)`）
  - Issue 143: 孤立ノード（degree=0）非表示トグル機能の実装
  - Issue 144: 最小次数フィルタ（Min-Degree / Hub Filter）の実装
  - Issue 145: 特定ノードのフォーカス・エゴネットワーク抽出機能の実装
  - Issue 162: グラフ Edge への判断ルール・推論機構・確信度・エビデンス属性の統合付与
  - Issue 163: Vertex紐付け推論判定ルール（EIROM）のマスターデータ化
  - Issue 164: エッジ確信度＆推論ルール絞り込みフィルタとエビデンス表示
  - Issue 165: 全量 OKF 論文アーカイブへの推論ルール適用と確信度付与バッチ

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/dashboard.html](file:///workspace/arxiv-security-papers/site/dashboard.html):
  - コントロールデッキ全要素（18箇所以上）への `data-tooltip` 属性およびインライン `ⓘ` ヘルプバッジの付与
  - Glassmorphic ツールチップスタイル定義（`.glass-tooltip`, `[data-tooltip]`）
  - クイック操作ガイドドロワー（`#graphHelpDrawer`）の HTML 構造およびトグル JS スクリプト
  - Canvas ノードホバーカード（`#nodeCallout`）およびエッジツールチップへのガイダンス追記
- [ ] [site/style.css](file:///workspace/arxiv-security-papers/site/style.css):
  - グラスモルフィックツールチップの共通変数、アニメーション、ドロワー用スタイル
- [ ] [tests/web/test_dashboard_graph_tab.py](file:///workspace/arxiv-security-papers/tests/web/test_dashboard_graph_tab.py):
  - `data-tooltip` 属性、ヘルプドロワー要素、インライン情報バッジの DOM 構造検証テストの追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/166-graph-tooltips-and-quick-guide`

### 4.1 脅威分析とセキュリティ設計（Anti-XSS & Performance）
- **脅威ベクトル**: ツールチップやドロワーにおける動的 DOM 挿入時の XSS（クロスサイトスクリプティング）。
- **防御策**:
  - 静的 UI コントロールに対するツールチップは、純粋な CSS 疑似要素（`::before`, `::after` + `attr(data-tooltip)`）をベースにし、JavaScript を介した `innerHTML` の注入を一切排除する（Zero-XSS アーキテクチャ）。
  - ヘルプドロワーおよびポップオーバーは静的 HTML コンポーネントとしてレンダリングし、ユーザー入力（クエリ文字列等）を直接 HTML 展開しない。

### 4.2 デザインシステム・CSS 仕様設計（UI/UX & Documentation Designer）
- **Glassmorphism トークン**:
  - 背景: `rgba(15, 23, 42, 0.92)`
  - ぼかし: `backdrop-filter: blur(16px)`
  - 境界線: `border: 1px solid rgba(255, 255, 255, 0.15)`
  - シャドウ: `box-shadow: 0 8px 32px rgba(0, 0, 0, 0.45), inset 0 1px 0 rgba(255, 255, 255, 0.1)`
  - フォント: `font-size: 11px`, `line-height: 1.45`, `color: #F1F5F9`
  - 微細アニメーション: `transition: opacity 0.15s cubic-bezier(0.16, 1, 0.3, 1), transform 0.15s cubic-bezier(0.16, 1, 0.3, 1)`
- **`[data-tooltip]` CSS 実装**:
  - ホバー時およびキーボードフォーカス（`:focus-visible`）時に微小な上方向スライドとともにフェードイン。
  - `white-space: normal`, `max-width: 260px` で長文の日本語説明も読みやすく折り返し表示。

### 4.3 コントロールデッキ全要素へのツールチップ付与設計
1. **モード切替**:
   - `btnModeMesh`: `論文間の意味的類似度・クラスタリングに基づく Context Mesh グラフを表示`
   - `btnModeCti`: `MITRE ATT&CK 攻撃手法、CWE 脆弱性、論文を結ぶ脅威インテリジェンスグラフを表示`
2. **エンティティ種別フィルタ**:
   - `filterAll`: `すべてのノード（論文・ATT&CK・CWE）を表示します`
   - `filterPaper`: `論文ノード（青）のみを表示します`
   - `filterAttack`: `ATT&CK 攻撃テクニックノード（赤）のみを表示します`
   - `filterCwe`: `CWE 脆弱性ノード（橙）のみを表示します`
   - `btnToggleGaps`: `論文による研究・対策が未カバーの攻撃テクニック（リサーチギャップ）を赤く点滅強調します`
3. **確信度（CONFIDENCE）フィルタ**:
   - `btnConfAll`: `推論ルールに関係なく、すべての確信度エッジを表示します`
   - `btnConfMed`: `確信度 MEDIUM 以上 (スコア ≥ 0.5) の信頼できるエッジのみ表示します`
   - `btnConfHigh`: `確信度 HIGH のみ (スコア ≥ 0.8: 直接正規表現やタイトル名合致) の厳格エッジを表示します`
4. **推論ルール（RULE）セレクタ**:
   - `selectEdgeRule`: `エッジ結合を導出した推論ルール（EIROM）種別（正規表現/タイトル/語彙等）で絞り込みます`
5. **最小次数（MIN DEGREE）フィルタ**:
   - `btnDegAll`: `全ノードを表示`
   - `btnDeg1`: `次数1以上（孤立ノードを除外）`
   - `btnDeg2`: `次数2以上（コアネットワーク接続）`
   - `btnDeg3`: `次数3以上（重要ハブノードのみ抽出）`
6. **ユーティリティボタン**:
   - `btnToggleIsolated`: `エッジ接続を持たない孤立ノード（degree=0）を一括非表示にします`
   - `btnToggleHeaderQuick`: `ダッシュボード上部ヘッダーを折りたたみ、グラフ領域を全画面化します (ショートカット: H)`
7. **クエリコンソール & プリセット**:
   - `graphQueryInput`: `CTI グラフ探索クエリを入力（例: gaps, cwe: CWE-20, ego: AML.T0054 2, match: quantum）`
   - `btnRunGraphQuery`: `入力したクエリを実行し、該当するサブグラフを抽出・ハイライトします`
   - `btnClearGraphQuery`: `クエリ条件をクリアし、全域グラフ表示に戻します`
   - プリセット各ボタン（`🚨 Research Gaps`, `🛡️ CWE-20 Multi-hop`, `🤖 Prompt Injection Ego`, `🔐 Post-Quantum Crypto`, `⚡ Side-Channel Leakage`）に用途・抽出範囲のツールチップを追加。

### 4.4 Graph 操作ガイド & 用語チートシートドロワー（Quick Guide Drawer）の実装
- **配置**: コントロールデッキ右端に `❓ ガイド (Help)` ボタンを追加。
- **UI 構造**:
  ```html
  <div id="graphHelpDrawer" class="graph-help-drawer">
    <div class="drawer-header">
      <h3>🕸️ Graph 操作ガイド & 用語解説</h3>
      <button class="btn-drawer-close" onclick="toggleGraphHelpDrawer()">✕</button>
    </div>
    <div class="drawer-body">
      <!-- 1. マウス・キーボード操作 -->
      <!-- 2. 2つのグラフモードの違い -->
      <!-- 3. 確信度ティア (HIGH/MED/LOW) と推論ルール (EIROM) -->
      <!-- 4. クエリ構文チートシートと活用例 -->
    </div>
  </div>
  ```
- **インタラクション**:
  - `Escape` キー押下または外側クリック（オーバーレイ）でスムーズに閉じる。
  - アニメーション: `transform: translateX(100%)` -> `translateX(0)`。

### 4.5 Canvas ノード・エッジホバーカードのマイクロガイダンス追記
- ノードホバー時（`#nodeCallout`）:
  - カード下部に「💡 クリックでこのノード中心のエゴネットワークを表示」の案内テキストを追加。
- エッジホバー時:
  - 「確信度: HIGH (0.80) | ルール: RULE-EDGE-PAPER-TECH-TITLE-02 | タイトル手法名合致」のフォーマットに加え、スニペットの引用元を明瞭に表示。

### 4.6 テストと品質ゲート
- `tests/web/test_dashboard_graph_tab.py`:
  - 全対象コントロール（`btnModeMesh`, `btnModeCti`, `filterAll`, `btnConfAll`, `btnDegAll`, `btnToggleIsolated`, `btnOpenGraphHelp` 等）に `data-tooltip` が設定されていることのテスト。
  - `#graphHelpDrawer` が存在し、必要なヘルプセクション（操作、モード、確信度、クエリ構文）を含んでいることのテスト。
- `make check_format`, `make static_analysis`, `make test` の完全合格。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `site/dashboard.html` 内の Graph コントロールデッキ上の全ボタン、入力欄、セレクト、トグルに分かりやすい日本語の `data-tooltip` が付与されていること。
- [ ] 複雑な概念（`CONFIDENCE`, `RULE`, `MIN DEGREE` 等）に情報アイコン（`ⓘ`）が配置され、機能解説が表示されること。
- [ ] ツールバーに `❓ ガイド (Help)` ボタンが配置され、クリックで「Graph 操作ガイド & 用語チートシート」ドロワーが開閉できること（`Esc` キーでの終了にも対応）。
- [ ] ドロワー内にマウス・キーボード操作、2つのグラフモードの違い、確信度ティア、およびクエリ構文例が整理されていること。
- [ ] Canvas 内ノードホバー時に操作誘導ヒント（「クリックでフォーカス」）が表示されること。
- [ ] `tests/web/test_dashboard_graph_tab.py` にツールチップおよびヘルプドロワーの構造検証テストが追加されパスすること。
- [ ] `# noqa: E402` を一切使用せず、Xenon Rank A、Mypy `--strict`、Flake8 / Black フォーマットチェックがすべて 100% PASS すること。

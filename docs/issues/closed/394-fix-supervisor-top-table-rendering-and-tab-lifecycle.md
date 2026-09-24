---
ID: 394
種別: Bug
優先度: High
ステータス: Closed (Complete)
---

# [BUG] Supervisor Top Workers Table の描画例外防止およびタブライフサイクル同期の修正 (ID: 394)

## 1. 概要 / Summary
Web UI の Supervisor タブ（`#/supervisor`）において、上部バッジ `badgeTotalWorkers` が `8 Processes` と更新されているにもかかわらず、テーブル本体（`supervisorWorkersTableBody`）が初期プレースホルダー `Connecting to Supervisor Top telemetry...` のまま固まり、リアルタイム更新されない不具合が発生した。

### 再現手順 / Steps to Reproduce
1. `outputs/supervisor/control.sock` を起動し、Arbiter およびワーカーを動作させる。
2. Enterprise Console（`site/index.html`）を開き、`#/supervisor` タブに遷移する。
3. `badgeTotalWorkers` が `8 Processes` になるが、ワーカー一覧テーブルが `Connecting to Supervisor Top telemetry...` のまま更新されない。

### 再現環境 / Environment
- OS: Linux
- Component: Enterprise Cloud Console Web UI (`site/app.js`, `site/app-min.js`, `site/index.html`)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [site/app.js](../../site/app.js): `updateSupervisorFromStream` の防護的コーディング、`switchToTab` および `appSceneDirector` の Supervisor タブライフサイクル統合、`escapeHtml` の型安全化
- [site/app-min.js](../../site/app-min.js): Closure Compiler によるプロダクションバンドル再生成
- [site/js/dashboard.js](../../site/js/dashboard.js): ワーカー一覧描画の防護的コーディング
- [site/dashboard-min.js](../../site/dashboard-min.js): Closure Compiler によるダッシュボードバンドル再生成
- [tests/web/test_enterprise_console_ui.py](../../tests/web/test_enterprise_console_ui.py): ライフサイクルおよび描画関数の契約テスト

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **`tbody.innerHTML` 代入直前の例外発生による中断**:
   `updateSupervisorFromStream` において、`wBadge.textContent = `${wEntries.length} Processes`;` の実行直後に `tbody.innerHTML = wEntries.map(...).join('')` を実行していた。この `map()` 評価の内部で未捕捉例外（`escapeHtml` への非文字列渡し、または `toFixed` の文字列呼び出し）が発生すると、`tbody.innerHTML` への代入が中断され、HTML 初期値 `Connecting to Supervisor Top telemetry...` がそのまま残っていた。
2. **例外のサイレント握り潰し**:
   呼び出し元の `syncConsoleTelemetry()` 内で `try ... catch` され `console.warn` で握り潰されるため、UI にエラーが表示されず静止していた。
3. **タブライフサイクル（`SceneDirector` / `switchToTab`）の欠落**:
   `appSceneDirector` に `supervisorTab` が登録されておらず、タブクリック時に即時テレメトリ同期（`syncConsoleTelemetry`）がトリガーされないため、初期ロード時に更新が失敗すると復帰しなかった。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: ページをハードリロードし、バックグラウンド SSE の再接続を待つ。
* **恒久対策 (Permanent Fix)**:
  1. `escapeHtml` を `String(str ?? '')` で完全防護。
  2. `updateSupervisorFromStream` の各行マッピングで `Number(w['idle_seconds'] || 0).toFixed(1)`、`Number(w['memory_mb'] || 0)`、`w` の存在チェックを適用し、安全な行ごとの try-catch フォールバックを配備。
  3. `appSceneDirector.register('supervisorTab', ...)` および `switchToTab` に `syncConsoleTelemetry()` を追加し、タブ表示時に即座に最新データを取得・再描画。
  4. `make build_js` により `site/app-min.js` および `site/dashboard-min.js` を再生成。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/394-supervisor-top-table-rendering-and-tab-lifecycle`

1. `site/app.js`:
   - `escapeHtml`: 引数を明示的に文字列化。
   - `updateSupervisorFromStream`: 防護的プロパティアクセス、数値変換の明示化、各行評価エラー時の安全スキップ。
   - `appSceneDirector` & `switchToTab`: `supervisorTab` のエントリを追加し `syncConsoleTelemetry()` を即時発火。
2. `site/js/dashboard.js`: 同様に防護的コーディングを適用。
3. `make build_js`:
   - `site/app-min.js` および `site/dashboard-min.js` を再生成。
4. テスト実行と品質ゲート確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `updateSupervisorFromStream` が不正な値や欠損プロパティに対しても例外を投げず、正常に `tbody.innerHTML` を更新できること。
- [x] `#/supervisor` タブへの切り替え時に即座に `syncConsoleTelemetry()` が実行されること。
- [x] `make build_js` が 0 エラーで完了し、`site/app-min.js` が同期されること。
- [x] `make check` / 関連テストがすべて PASS すること。

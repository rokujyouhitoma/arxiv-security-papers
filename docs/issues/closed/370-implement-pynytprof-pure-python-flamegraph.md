---
ID: 370
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] PyNYTProf Pure-Python インタラクティブ Flame Graph SVG 生成器の実装 (ID: 370)

## 1. 概要 / Summary
DSN-28（Python版NYTProf統合スイート設計仕様書）の Phase 2 として、外部 Perl スクリプト（`flamegraph.pl`）を一切使用せず、純粋 Python のみでコールスタック階層からインタラクティブな SVG Flame Graph を生成する `FlameGraphGenerator`（`src/core/profiler/flamegraph.py`）を実装する。
各ブロックは消費時間に応じた幅で描画され、ホバー時のツールチップ情報（サブルーチン名、呼出回数、消費時間、比率）およびクリックによる詳細 HTML レポートへの直接画面遷移（SVG ハイパーリンク）を備える。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-28-python_nytprof_profiler_and_visualization_suite.md](../designs/DSN-28-python_nytprof_profiler_and_visualization_suite.md) Section 5.1 (インタラクティブ Flame Graph 生成)
- 関連仕様: Brendan Gregg FlameGraph Visual Spec
- 関連設計: `DSN-21` (Enterprise Design System), `DSN-27` (Modular Frontend Framework)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/core/profiler/flamegraph.py](../../src/core/profiler/flamegraph.py) (新規: Pure-Python SVG Flame Graph 生成器)
- [x] [src/core/profiler/__init__.py](../../src/core/profiler/__init__.py) (更新: `FlameGraphGenerator` エクスポート)
- [x] [tests/core/test_pynytprof_flamegraph.py](../../tests/core/test_pynytprof_flamegraph.py) (新規: Flame Graph 生成・パース検証テスト)
- [x] [docs/issues/README.md](README.md) (Issue台帳の同期)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/370-pynytprof-flamegraph`

1. **スタックツリー構築データ構造 (`FlameNode`)**:
   - `name: str` (関数名)
   - `total_time_ns: int` (累積時間)
   - `children: Dict[str, FlameNode]` (子ノードマップ)
   - `depth: int` (スタック深度)
   - `x: float`, `y: float`, `width: float`, `height: float` (描画座標)

2. **SVG 生成アルゴリズム (`flamegraph.py`)**:
   - `parse_calls(calls_data: Union[Dict[str, int], str])`: セミコロン区切りスタックを集計してプレフィックスツリーを構築。
   - 各ノードの幅 $W = \frac{\text{total\_time\_ns}}{\text{root\_time\_ns}} \times \text{canvas\_width}$ を算出。
   - 暖色系ハッシュカラー計算関数 `get_hash_color(name)`: 関数名ハッシュ値から一貫性のある赤・橙・黄パレットを動的生成。
   - クリック可能ハイパーリンク: `<a xlink:href="source_{file}.html#{func}" target="_top">`
   - インライン JavaScript によるズーム・検索・ツールチップ（自己完結型 SVG）。

3. **単体テストスイート (`test_pynytprof_flamegraph.py`)**:
   - サンプルコールデータからの SVG 生成、XML 妥当性検証。
   - 再帰呼び出しを含むスタックの幅・階層整合性検証。
   - クリック可能リンクおよびカラー属性の存在確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 外部依存ゼロ（標準ライブラリ `xml.etree.ElementTree` または文字列構築）でスタンドアロンの有効な SVG を生成できること。
- [ ] SVG 内に各サブルーチンの時間比率に応じた階層ブロック（`<rect>`, `<text>`）が正しく配置されること。
- [ ] クリック可能リンク（`<a xlink:href="...">`）およびツールチップ（`<title>`）が含まれること。
- [ ] `tests/core/test_pynytprof_flamegraph.py` が 100% パスすること。
- [ ] `make py_compile` を完全パスすること。

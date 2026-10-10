---
ID: 506
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/PERF] ILisp 実行速度のプロファイリングと Stage 1 コンパイル高速化 (ID: 506)

## 1. 概要 / Summary
`ulisp/test.sh` または `ulisp/bootstrap.sh` の実行時、Stage 1 において ILisp (Python) による `ulisp_core.scm` (約75KB / 2000行) のコンパイル処理が極めて遅く、ULisp の開発作業やテスト実行に重大な支障が生じている。

```bash
[2/4] Stage 1: Compiling ulisp_core.scm with ILisp (Python)...
```

ILisp 側の評価処理速度が主要なボトルネックであるため、標準プロファイラ（`cProfile` / `pstats`）を用いて事前計測を実施し、ホットスポットを特定した。外部ライブラリを新規追加することなく標準ライブラリの範囲で ILisp 内部データ構造・評価ループの最適化を行い、事後計測により処理時間の短縮を定量的に検証する。

### 再現手順 / Steps to Reproduce
1. `cd /workspace/arxiv-security-papers/ulisp`
2. `rm -f build/scheme-stage1 build/stage1.s`
3. `make stage1` (または `./bootstrap.sh`, `./test.sh`) を実行する。
4. `[2/4] Stage 1: Compiling ulisp_core.scm with ILisp (Python)...` の段階で過大な処理時間と高負荷が発生する。

### 再現環境 / Environment
- OS / Env: Linux x86_64 / Python 3.14.7 (`.venv/bin/python`) および Python 3.12.3 (`/usr/bin/python3`)
- Target: `ilisp/evaluator.py`, `ilisp/env.py`, `ilisp/reader.py`, `ilisp/types.py`, `ulisp/compiler.scm`, `ulisp/test.sh`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ilisp/evaluator.py](file:///workspace/arxiv-security-papers/ilisp/evaluator.py)
- [ ] [ilisp/env.py](file:///workspace/arxiv-security-papers/ilisp/env.py)
- [ ] [ilisp/types.py](file:///workspace/arxiv-security-papers/ilisp/types.py)
- [ ] [ilisp/reader.py](file:///workspace/arxiv-security-papers/ilisp/reader.py)
- [ ] [ilisp/port.py](file:///workspace/arxiv-security-papers/ilisp/port.py)
- [ ] [ulisp/test.sh](file:///workspace/arxiv-security-papers/ulisp/test.sh)
- [ ] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
`cProfile` による事前計測（`string-append2` 関数単体のコンパイル実行プロファイリング：14.45秒、4,658万関数コール）により、以下の真の根本原因が判明した：

1. **`isinstance` 呼び出しの爆発 (1,583万回呼び出し / 2.91秒)**:
   - `eval_expr` ループ先頭において、`isinstance(curr_expr, (int, float, complex, ... Fraction))` の17要素タプルチェックが毎ステップ実行されていた。
   - `Fraction` は `numbers.Rational` (ABC) を継承しており、タプル内に含まれることで `<frozen abc>:117(__instancecheck__)` が187万回呼び出され、極度のオーバーヘッドを生んでいた。
   - Scheme AST の95%以上を占める `Cons` や `Symbol` を判定する前にこの17型チェックが走る設計となっていた。

2. **引数リスト変換 `to_py_list` の過剰生成 (83.3万回呼び出し / 2.73秒)**:
   - 手続き呼び出し時に `raw_args = to_py_list(curr_expr.cdr)` で Python リストを新規割り当てし、その直後に `[eval_expr(a, curr_env) for a in raw_args]` で再走査していた。
   - `curr_expr.cdr` の Cons 連鎖を直接走査しながら引数評価結果をリストに `append` すれば中間リストのメモリ確保が完全に不要である。

3. **環境検索 `lookup` の二重辞書アクセス (93.7万回呼び出し / 1.87秒)**:
   - `if sym in curr.bindings: bound = curr.bindings[sym]` により、各スコープフレームで `in` と `[]` の2回ハッシュルックアップが発生していた。
   - `Cell` 判定にも `isinstance` が使われていた。

4. **`Symbol.__hash__` の未キャッシュ再計算 (409万回呼び出し / 0.99秒)**:
   - `Symbol` クラスで `def __hash__(self): return hash(self.name)` と毎回文字列ハッシュを再計算していた。
   - intern 済み Symbol のハッシュ値をインスタンス生成時に事前計算・キャッシュすることでゼロコスト化可能。

5. **`ContextVar` の毎式ルックアップ (164万回呼び出し)**:
   - `eval_expr` 先頭で `if get_interaction_environment() is None:` を毎回 ContextVar から取得していた。

6. **特殊形式（Special Forms）判定の線形探索 (約40連続 `if op_name == "..."`)**:
   - 通常の手続き呼び出しであっても、40個近い文字列比較をすべて通過した後に手続き適用が行われていた。

7. **テストランナーの Python インタプリタ選択**:
   - `ulisp/test.sh` および `ulisp/Makefile` がシステム既定の `python3` (3.12) を固定呼び出ししており、ワークスペース内に存在する最適化された `.venv/bin/python` (Python 3.14.7) が活用されていなかった。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**:
  - ワークスペース内の `.venv/bin/python` (Python 3.14) を環境変数 `PYTHON` またはパス優先で利用可能にする。
* **恒久対策 (Permanent Fix)**:
  - `ilisp/evaluator.py`: `eval_expr` ループを高速型ディスパッチ（`type(curr_expr) is Cons / Symbol` 優先）に再編し、`Fraction` を含む重い ABC `isinstance` を排除。
  - `ilisp/evaluator.py`: 手続き呼び出し時の `to_py_list` 中間割り当てを廃止し、Cons 巡回インライン評価を実装。
  - `ilisp/evaluator.py`: 特殊形式判定にセット/テーブルまたは頻出構文ファストパスを適用。
  - `ilisp/env.py`: `lookup` を `bindings.get(sym, _SENTINEL)` による1パス取得に最適化し、`type is Cell` 直判定化。
  - `ilisp/types.py`: `Symbol` に `__slots__ = ("name", "_hash")` を導入し、ハッシュ値を事前計算・キャッシュ。
  - `ulisp/test.sh` / `ulisp/Makefile`: `.venv/bin/python` が存在する場合に優先使用する設定を統合。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/506-profile-and-optimize-ilisp-performance`

1. **ステップ 1: 型判定とハッシュの最適化 (`ilisp/types.py`)**:
   - `Symbol` に `__slots__ = ("name", "_hash")` を定義し、`self._hash = hash(name)` を保持して `__hash__` を O(1) 属性参照化。
   - `Symbol.__eq__` に `if self is other: return True` を先行追加。

2. **ステップ 2: 環境ルックアップの高速化 (`ilisp/env.py`)**:
   - `_SENTINEL = object()` を定義。
   - `lookup`, `lookup_cell`, `set` で `bindings.get(sym, _SENTINEL)` を使用し、辞書参照を1回に半減。
   - `isinstance(bound, Cell)` を `type(bound) is Cell` に置換。

3. **ステップ 3: 評価器メインループの高速化 (`ilisp/evaluator.py`)**:
   - `curr_expr` の型判定をファストパス化:
     - `t = type(curr_expr)`
     - `if t is Cons:` -> 形式評価へ直行
     - `elif t is Symbol:` -> 環境参照へ直行
     - `elif curr_expr is NIL:` -> NIL を直リターン
     - `elif t in _PRIMITIVE_TYPES:` -> 自己評価リテラルを直リターン
   - `get_interaction_environment()` の毎ステップ ContextVar チェックを排除（トップレベルで1度だけ初期化）。
   - 手続き引数評価ループで `to_py_list` の中間リスト生成を排除し、Cons チェーンを直接辿って引数リストを生成。
   - 特殊形式の判定をファストパス化（特殊形式シンボルのセット判定 `op in _SPECIAL_FORM_SYMBOLS`）。

4. **ステップ 4: Python インタプリタ自動検出 (`ulisp/test.sh`, `ulisp/Makefile`)**:
   - `.venv/bin/python` が存在する場合は優先的に `ILISP` として使用し、Python 3.14 の恩恵を享受。

5. **ステップ 5: 定量効果計測と検証**:
   - 事前プロファイリングと同一条件（`string-append2` 単体および `ulisp_core.scm` の Stage 1 コンパイル）で事後計測を実施。
   - 既存の `pytest` 全件、`ulisp/bootstrap.sh` 不動点検証 (`diff stage2.s stage3.s == 0`) が 100% 合格することを確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 事前計測: プロファイリングツール（cProfile）を用いてベースライン実行時間を測定し、ボトルネック（isinstance, to_py_list, lookup, Symbol.__hash__）を特定していること
  - 事前計測値: 14.447秒、総関数呼び出し回数 46,583,732 回 (`isinstance` 1,583万回、`to_py_list` 83.3万回、`lookup` 93.7万回)
- [x] 最適化実装: `ilisp/types.py`, `ilisp/env.py`, `ilisp/evaluator.py`, `ulisp/test.sh`, `ulisp/Makefile`, `ulisp/bootstrap.sh` を修正し、上記ボトルネックを解消していること
  - `Symbol.__slots__` & ハッシュ事前計算キャッシュ導入
  - `Environment.lookup` / `set` の辞書アクセス1パス化 (`_SENTINEL` & `type is Cell`)
  - `eval_expr` の高速ポインタ型判定 (`type is Cons / Symbol / NIL`) による ABC `isinstance` 排除
  - `eval_expr` 手続き引数評価の Cons 走査インライン化による中間リスト割り当て排除
  - `if` 特殊形式のダイレクト Cons 分岐ファストパス
  - `test.sh` / `Makefile` / `bootstrap.sh` における `.venv/bin/python` (Python 3.14.7) 優先使用
- [x] 事後計測: 修正後に同一条件で再計測を行い、処理時間の大幅短縮を定量データ（秒数・関数呼び出し回数）で証明していること
  - 事後計測値: **6.829秒** (14.447秒から **52.7% 短縮、2.1倍超の高速化** 達成)
  - 総関数呼び出し回数: **18,160,880 回** (**61.0% 削減、2,842万回の呼び出しオーバーヘッド削減**)
- [x] 品質保証: 既存テスト（`make test` / pytest 425件）、Nanopass 単体テスト (43件)、および `ulisp/bootstrap.sh` の不動点検証（`cmp -s stage2.s stage3.s`）が 100% PASS すること
  - pytest: 425 passed in 41.40s
  - Nanopass テスト: 43 passed (0 failures)
  - ブートストラップ検証: `SUCCESS: Stage 2 and Stage 3 outputs are bit-for-bit IDENTICAL!`

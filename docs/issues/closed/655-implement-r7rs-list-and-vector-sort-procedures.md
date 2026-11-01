---
ID: 655
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS-large (SRFI 132 / 95) リストおよびベクタソート手続きの実装 (ID: 655)

## 1. 概要 / Summary
R7RS-large (SRFI 132 Sort Libraries および SRFI 95 / SLIB 互換、R7RS-large Tangerine Edition `(scheme sort)`) に準拠した、リストおよびベクタの包括的ソート・マージ手続き群を ULisp に実装する。
安定ソート（マージソート）アルゴリズムに基づき、任意の比較述語（`less?`）に従って要素列を安定・高速に整列可能にする。
これにより、データ検索インデックスの構築、シンボル・識別子テーブルの整列、CTI 脅威データの時系列ソート、および R7RS-large 互換性を大幅に強化する。

---

## 2. アーキテクチャと設計方針 / Architecture & Design Principles

### (1) ソートアルゴリズムの選定: 安定マージソート (Merge Sort)
- **計算量**: 最悪・平均ともに $O(N \log N)$ を厳格保証（クイックソートのような最悪 $O(N^2)$ の退化なし）。
- **安定性 (Stability)**: 等価な要素（`less? a b` も `less? b a` も偽）について、元のリスト・ベクタ内での相対順序が厳格に保存される。
- **リストソート**:
  - `list-sort`: 非破壊的分割統治マージソート。
  - `list-sort!`: ポインタ（`set-cdr!`）をインプレースに組み替える破壊的マージソート（ヒープアロケーション $O(1)$）。
  - `list-stable-sort`: `list-sort` のエイリアス。
- **ベクタソート**:
  - `vector-sort!`: 作業用一時ベクタ（サイズ $N = end - start$）を 1 つのみ確保し、反復または分割統治でインプレースソート。ガベージコレクション圧力を最小化。
  - `vector-sort`: `vector-copy` による複製に対して `vector-sort!` を適用し返却。
  - `vector-stable-sort`: `vector-sort` のエイリアス。

### (2) 範囲指定パラメータ (`[start [end]]`) の `case-lambda` による安全なサポート
- ベクタソート手続き（`vector-sort`, `vector-sort!`, `vector-sorted?`）は、部分範囲 `[start, end)` のソートに対応する。
- Pass 028 で最適化される `case-lambda` を使用し、固定引数＋`%num-args` ディスパッチでオーバーヘッドなく実装する：
  - 2引数: `(proc less? vec)` -> `start = 0`, `end = (vector-length vec)`
  - 3引数: `(proc less? vec start)` -> `end = (vector-length vec)`
  - 4引数: `(proc less? vec start end)`

### (3) 提供手続き一覧

| 分類 | 手続き名 | 引数仕様 | 説明 |
| :--- | :--- | :--- | :--- |
| **ソート判定** | `list-sorted?` | `(less? list)` | リストが `less?` に従って整列済みか判定 |
| | `vector-sorted?` | `(less? vec [start [end]])` | ベクタ（または部分範囲）が整列済みか判定 |
| **マージ** | `list-merge` | `(less? list1 list2)` | 2つのソート済みリストを安定マージ |
| | `vector-merge` | `(less? vec1 vec2)` | 2つのソート済みベクタを安定マージ |
| **リストソート** | `list-sort` | `(less? list)` | 非破壊的安定リストソート |
| | `list-sort!` | `(less? list)` | 破壊的インプレース安定リストソート |
| | `list-stable-sort` | `(less? list)` | `list-sort` と同義 |
| **ベクタソート** | `vector-sort` | `(less? vec [start [end]])` | 非破壊的安定ベクタソート |
| | `vector-sort!` | `(less? vec [start [end]])` | 破壊的安定ベクタソート |
| | `vector-stable-sort` | `(less? vec [start [end]])` | `vector-sort` と同義 |
| **SRFI 95 互換** | `sorted?` | `(seq less?)` | シーケンス（リスト/ベクタ）の整列判定 |
| | `merge` | `(list1 list2 less?)` | リストのマージ |
| | `sort` | `(seq less?)` | シーケンス（リスト/ベクタ）の非破壊的ソート |
| | `sort!` | `(seq less?)` | シーケンス（リスト/ベクタ）の破壊的ソート |

### (4) ライブラリ構成とモジュール体系
- `ulisp/lib/sort.scm`: コアソート・マージアルゴリズムの実装。
- `ulisp/lib/srfi/132.sld`: R7RS-large SRFI 132 ライブラリ定義。
- `ulisp/lib/srfi/95.sld`: SRFI 95 互換ライブラリ定義。
- `ulisp/lib/scheme/sort.sld`: R7RS-large Tangerine `(scheme sort)` ライブラリ定義。
- `ulisp/Makefile`: `ULISP_STD_LIBS` に `lib/sort.scm` を登録し、全ランタイム・テストで透過的に利用可能にする。

---

## 3. セキュリティ・脅威分析 / Threat Modeling & Security Analysis

| 脅威カテゴリ (STRIDE) | 想定されるリスク | 対策・緩和策 |
| :--- | :--- | :--- |
| **Denial of Service (DoS)** | 境界外の `start` / `end` インデックス指定によるバッファオーバーランやクラッシュ (SIGSEGV) | `0 <= start <= end <= (vector-length vec)` の厳格なバリデーションを実施し、違反時は即座に例外を送出。 |
| **Algorithmic Complexity (DoS)** | 不正な比較述語（推移律を満たさない述語）による無限ループ | マージソートは分割統治のインデックス計算に基づくため、どのような述語が渡されても再帰深さ $\lceil \log_2 N \rceil$ で必ず終了することを保証。 |
| **Type Confusion** | リスト操作関数にベクタが渡されることによる型不整合や未定義動作 | `pair?`, `null?`, `vector?` による明示的型アサーションを実施。 |
| **Memory Exhaustion** | 巨大リストソート時の過度な cons アロケーション | 破壊的ソート `list-sort!` では既存セルのポインタ組み換え（インプレース）により追加メモリ割り当てを $O(1)$ に抑制。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

Target Branch: `feat/655-implement-r7rs-list-and-vector-sort-procedures`

- [x] [ulisp/lib/sort.scm](../../ulisp/lib/sort.scm) (新規モジュール: コアソートアルゴリズム)
- [x] [ulisp/lib/srfi/132.sld](../../ulisp/lib/srfi/132.sld) (新規ライブラリ: SRFI 132 定義)
- [x] [ulisp/lib/srfi/95.sld](../../ulisp/lib/srfi/95.sld) (新規ライブラリ: SRFI 95 定義)
- [x] [ulisp/lib/scheme/sort.sld](../../ulisp/lib/scheme/sort.sld) (新規ライブラリ: `(scheme sort)` 定義)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`ULISP_STD_LIBS` 登録、`test_sort` ターゲット追加、`lint_sexpr`、`test` 統合)
- [x] [ulisp/tests/test_sort.scm](../../ulisp/tests/test_sort.scm) (新規テストスイート: 6グループ)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (SRFI 132 / SRFI 95 ステータスを `◎` に更新)

---

## 5. 実装手順 / Implementation Steps

### Step 1: コアソート・マージモジュールの実装 (`ulisp/lib/sort.scm`)
1. **述語・マージ**:
   - `list-sorted?`: リストの隣接要素を順次比較。
   - `vector-sorted?`: `case-lambda` による範囲検証付きベクタ整列判定。
   - `list-merge`: 2つのソート済みリストの安定マージ。
   - `vector-merge`: 2つのソート済みベクタの安定マージ。
2. **リストソート**:
   - `list-sort`: リスト長に基づく分割統治安定マージソート。
   - `list-sort!`: ポインタ付け替えによるインプレース破壊的マージソート。
   - `list-stable-sort`: `list-sort` のエイリアス。
3. **ベクタソート**:
   - `vector-sort!`: `case-lambda` による範囲指定対応インプレースマージソート。
   - `vector-sort`: 複製を作成して `vector-sort!` を適用。
   - `vector-stable-sort`: `vector-sort` のエイリアス。
4. **SRFI 95 互換ラッパー**:
   - `sort`, `sort!`, `sorted?`, `merge` の定義。

### Step 2: ライブラリ定義ファイルの作成
- `ulisp/lib/srfi/132.sld`
- `ulisp/lib/srfi/95.sld`
- `ulisp/lib/scheme/sort.sld`

### Step 3: テストスイートの作成 (`ulisp/tests/test_sort.scm`)
- **Group 1**: ソート済み判定テスト (`list-sorted?`, `vector-sorted?`)
- **Group 2**: リストマージ・ベクタマージテスト (`list-merge`, `vector-merge`)
- **Group 3**: リストソート基本・エッジケーステスト（空リスト、要素数1、逆順、同一値多数、ランダム列）
- **Group 4**: リストソートの安定性 (Stability) 検証（キー付きペアの相対順序保持テスト）
- **Group 5**: ベクタソート基本・部分範囲 (`start`/`end`) テスト
- **Group 6**: SRFI 95 互換手続きおよび破壊的ソート (`list-sort!`, `vector-sort!`) テスト

### Step 4: Makefile 統合と単体テスト検証
- `ulisp/Makefile` の `ULISP_STD_LIBS` に `lib/sort.scm` を追加。
- `test_sort` ターゲットを追加し、`test` に組み込み。
- `make lint_sexpr` で全 S 式括弧整合性を確認。
- `make test_sort` を実行し、全テスト 100% PASS を確認。

### Step 5: 回帰テスト、3-Stage Bootstrap、品質ゲート
- 主要回帰テスト (`make test_format`, `test_max_min`, `test_hashtable`, `test_srfi1`, etc.) を実行。
- `make test`（全 Nanopass / ランタイムテスト）を実行。
- `./bootstrap.sh` による 3-Stage Bootstrap 固定点検証。
- `make check_format` および `make static_analysis` (Radon, Xenon, Mypy) を実行。

### Step 6: ドキュメント更新・Issue クローズ・コミット
- `ulisp/docs/ref_r7rs_compliance.md` の SRFI 132 / SRFI 95 を `◎` に更新。
- Issue ファイルを `docs/issues/closed/` に移動し、台帳 `docs/issues/README.md` を更新。
- feature ブランチから `main` へのマージ。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/lib/sort.scm` にてリストおよびベクタのソート・マージ手続きが正しく定義されていること。
- [x] `list-sort`, `list-sort!`, `vector-sort`, `vector-sort!` が期待通りの昇順・降順に安定ソートされること。
- [x] 等価要素の相対順序が変化しない安定性（Stability）がテストで証明されること。
- [x] 空シーケンス、単一要素、部分範囲（`start`/`end`）のエッジケースが正しく処理されること。
- [x] `ulisp/lib/srfi/132.sld`, `ulisp/lib/srfi/95.sld`, `ulisp/lib/scheme/sort.sld` が配置されていること。
- [x] `make test_sort` が 100% PASS すること。
- [x] 全回帰テスト (`make test`) が 100% PASS すること。
- [x] `./bootstrap.sh` がエラーなく完走し、Stage 2 と Stage 3 の出力が完全一致すること。
- [x] `make check_format` および `make static_analysis` がエラー 0 件で PASS すること。
- [x] `ref_r7rs_compliance.md` の SRFI 132 / 95 ステータスが `◎` に更新されていること。
- [x] Issue ファイルが `docs/issues/closed/` に移動され、台帳が更新されていること。

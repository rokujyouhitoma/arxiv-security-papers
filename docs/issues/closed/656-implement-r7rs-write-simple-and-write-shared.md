---
ID: 656
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS §6.13.3 循環参照・共有構造表記対応ライター (write-simple, write-shared) の実装 (ID: 656)

## 1. 概要 / Summary
R7RS-small §6.13.3 および SRFI 38 で規定されている `(write-simple <obj> [<port>])` および `(write-shared <obj> [<port>])` 手続きを ULisp に実装し、ライブラリ `(scheme write)` の仕様準拠度を 100% (完全準拠) に引き上げる。
循環リストや循環ベクタなどの自己参照・共有構造を含むデータ構造を出力する際、無限ループでクラッシュすることなく `#1=(a . #1#)` 形式の datum label (SRFI 38 記法) で安全に出力可能にする。
また、既存の `display`, `write`, `newline` と合わせて第一級手続きオブジェクト (`case-lambda`) として提供し、高階関数への引数受け渡しにも完全対応させる。

---

## 2. アーキテクチャと設計方針 / Architecture & Design Principles

### (1) 2 パス共有検出アルゴリズム (Two-Pass Datum Label Algorithm)
`write-shared` は以下の 2 パス処理により、循環・共有構造を正確に検知・ラベリングして出力する：

1. **Pass 1: 共有ノードの探索と出現頻度カウント (`%collect-shared-nodes`)**:
   - オブジェクトを深さ優先走査する。
   - 探索対象の複合型: `pair?`, `vector?`（同一オブジェクトのポインタ `eq?` 比較）。
   - 状態記録連想リスト `table` を用いる:
     - 未訪問ノード: `(cons (cons obj 1) table)` を記録し、その子要素を再帰走査。
     - 訪問中 / 訪問済みノード (既に `table` に存在): カウントを `(+ count 1)` に更新し、**そのノードの下位要素へは再帰しない**。
     - これにより、循環構造（自己参照・相互参照）が存在しても有限ステップ $O(N)$ で確実に探索が終了し、無限ループを数学的に防止する。

2. **ラベル ID の割り当て (`%assign-datum-labels`)**:
   - カウントが 2 以上のノード（共有または循環参照）を抽出し、出現順に 1 から始まる連番整数 ID を割り当てたラベルマップ `((obj . 1) (obj . 2) ...)` を構築。

3. **Pass 2: ラベル付き出力 (`%port-write-shared-node`)**:
   - オブジェクトを出力する際、ラベルマップを照会：
     - **非共有ノード**: 通常の S 式出力（`write-simple` と同等）。
     - **共有ノード (初回出現)**:
       - 定義ラベル `#<id>=` を出力。
       - 出力済み集合（`defined-set`）に当該オブジェクトを記録。
       - その実体（ペアやベクタの内容）を再帰出力。
     - **共有ノード (2回目以降の出現)**:
       - 参照ラベル `#<id>#` を出力して即座に終了（子要素は再帰出力しない）。

### (2) `write-simple` の仕様
- 循環・共有検出を行わず、木構造として直接出力する（最速の出力パス）。
- 循環構造が渡された場合は、R7RS 仕様通り無限展開（またはリソース枯渇）となる。

### (3) `write` の安全化
- R7RS §6.13.3 では「`write` は `write-shared` のように datum labels を用いることが許可される（循環がある場合は推奨）」とされている。
- ULisp では `write` も内部で `write-shared`（安全パス）を呼び出すように設定し、不意の循環データ出力時にも安全に停止する堅牢性を確保する。

### (4) 第一級手続きオブジェクト化 (`case-lambda`)
- `ulisp/lib/printer.scm` 内で構文マクロ (`define-syntax`) だった `write`, `display`, `newline` を、`case-lambda` による第一級手続きオブジェクトにリファクタリング。
- オプショナルな `[port]` 引数を透過的にハンドリング（ポート省略時は `(current-output-port)`）。
- これにより、`(for-each write lst)` や `(apply write-shared '(obj port))` などの Scheme 標準コードが完全に動作する。

---

## 3. セキュリティ・脅威分析 / Threat Modeling & Security Analysis

| 脅威カテゴリ (STRIDE) | 想定されるリスク | 対策・緩和策 |
| :--- | :--- | :--- |
| **Denial of Service (DoS)** | 悪意のある循環リスト・循環ベクタ（自己参照ポインタ）の出力によるスタックオーバーフローや無限ループハング | Pass 1 で訪問済みノードの再走査を即座に枝刈りするため、最悪ケースでもノード数 $O(N)$ で走査が完了する。 |
| **Memory Exhaustion (DoS)** | 共有ノード管理テーブルの無制限なアロケーション | 探索テーブルは走査対象の参照ノード数に比例する線形メモリ $O(N)$ であり、出力完了後に即座に GC 回収される。 |
| **Type Confusion** | ペアとベクタのタグ判定誤りによる不正メモリロード (SIGSEGV) | Issue #655 で修正された LIR 下位 3 ビットマスク (`& 7 == 1` vs `& 7 == 5`) を前提とし、`pair?`, `vector?` を厳格に弁別。 |
| **Information Disclosure** | 未定義オブジェクトやクロージャ、ポートなどの未想定型のダンプ | `eof-object?`, `bytevector?`, `char?`, `string?`, `number?`, `boolean?`, `symbol?` 以外の未対応型は `#<unknown>` または `#<procedure>` で安全にマスク出力。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

Target Branch: `feat/656-implement-r7rs-write-simple-and-write-shared`

- [ ] [ulisp/lib/printer.scm](../../ulisp/lib/printer.scm) (中核: `write-simple`, `write-shared`, `port-write-simple`, `port-write-shared`, `case-lambda` 手続き定義)
- [ ] [ulisp/lib/scheme/write.sld](../../ulisp/lib/scheme/write.sld) (ライブラリ定義確認・整合)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_printer` ターゲット追加、`lint_sexpr` 登録)
- [ ] [ulisp/tests/test_printer.scm](../../ulisp/tests/test_printer.scm) (新規テストスイート: 6グループ)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (§6.13.3 および §1.4 のステータスを `◎` に更新)

---

## 5. 実装手順 / Implementation Steps

### Step 1: 共有・循環検出アルゴリズムの実装 (`ulisp/lib/printer.scm`)
1. **Pass 1 (`%collect-shared-nodes`)**:
   - `(pair? x)`, `(vector? x)` に対する深さ優先探索。
   - `assq` による重複ノードカウント。再訪ノードは子へ降りずにカウントアップ。
2. **Pass 2 (`%port-write-shared-node`)**:
   - ラベルマップ `((obj . id) ...)` から共有判定。
   - 初回訪問時は `#<id>=` を出力して `defined` 集合に追加し子要素を展開。
   - 2回目以降は `#<id>#` を出力して枝刈り。
   - ペアのリスト走査中、`cdr` が共有ノードである場合は `.` (dot) 記法＋`#<id>#` または `#<id>=` で適切に出力。
3. **`write-simple`, `write-shared`, `write`, `display`, `newline` の `case-lambda` 定義**:
   - `(write-simple obj)` / `(write-simple obj port)`
   - `(write-shared obj)` / `(write-shared obj port)`
   - `(write obj)` / `(write obj port)`
   - `(display obj)` / `(display obj port)`
   - `(newline)` / `(newline port)`

### Step 2: テストスイートの作成 (`ulisp/tests/test_printer.scm`)
- **Group 1: `write-simple` 基本テスト**:
  - アトム値（fixnum, char, boolean, symbol, string, empty list, eof-object）
  - 通常のリスト、ネストしたリスト、ベクタ、バイトベクタ
- **Group 2: `write-shared` 非循環・非共有テスト**:
  - ラベルが付与されず、`write-simple` と同一の結果が得られることの確認。
- **Group 3: `write-shared` 循環リストテスト**:
  - 単純な自己循環リスト: `(let ((x (list 1))) (set-cdr! x x) x)` -> `#1=(1 . #1#)`
  - 2要素以上の循環リスト: `(let ((x (list 1 2))) (set-cdr! (cdr x) x) x)` -> `#1=(1 2 . #1#)`
  - 相互参照循環リスト: `(let ((x (list 1)) (y (list 2))) (set-cdr! x y) (set-cdr! y x) x)` -> `#1=(1 2 . #1#)`
- **Group 4: `write-shared` 循環ベクタテスト**:
  - 自己参照ベクタ: `(let ((v (vector 1 2))) (vector-set! v 1 v) v)` -> `#1=#(1 #1#)`
  - ベクタとリストの複合循環: `(let ((v (vector 1 #f)) (l (list 2 #f))) (vector-set! v 1 l) (set-car! (cdr l) v) v)`
- **Group 5: `write-shared` DAG共有構造（非循環の共有）テスト**:
  - 同一オブジェクトの多重参照: `(let ((x '(a b))) (list x x))` -> `(#1=(a b) #1#)`
  - ベクタ内の共有参照: `(let ((x (vector 1 2))) (vector x x))` -> `#(#1=#(1 2) #1#)`
- **Group 6: 第一級手続きおよびポート引数テスト**:
  - `(procedure? write-simple)`, `(procedure? write-shared)` の検証。
  - 出力先ポート指定（`open-output-string`, `get-output-string`）での文字列表現検証。

### Step 3: Makefile 統合と構文検証
- `ulisp/Makefile` に `test_printer` ターゲットを追加し、`test` に組み込み。
- `make -C ulisp lint_sexpr` による S 式括弧整合性確認。
- `make -C ulisp test_printer` を実行し、全テスト 100% PASS を確認。

### Step 4: 回帰テストと 3-Stage Bootstrap
- `make -C ulisp test_sort test_format test_max_min test_string_to_number test_hashtable test_srfi1`
- `cd ulisp && ./bootstrap.sh`（Stage 2 と Stage 3 の bit-for-bit 完全一致確認）
- `make check_format` および `make static_analysis` (Radon, Xenon, Mypy)

### Step 5: 仕様適合表更新・Issue クローズ
- `ulisp/docs/ref_r7rs_compliance.md` の §6.13.3 (`write-shared`, `write-simple`) および §1.4 (`(scheme write)`) を `◎` に更新。
- Issue ファイルを `docs/issues/closed/` に移動し、`docs/issues/README.md` を更新。
- feature ブランチをコミットし、`main` にマージ。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/lib/printer.scm` にて `write-simple`, `write-shared`, `write`, `display`, `newline` が `case-lambda` による第一級手続きとして実装されていること。
- [x] 循環リストおよび循環ベクタが無限ループすることなく、`#1=(1 2 . #1#)` や `#1=#(1 #1#)` 形式で正しく出力されること。
- [x] 共有構造（同一インスタンスの複数回参照）が `#1=... #1#` で正しくラベル付け出力されること。
- [x] `write-simple` が循環検出を行わず直接木構造を出力する仕様通りに動作すること。
- [x] `ulisp/lib/scheme/write.sld` が `write`, `display`, `write-simple`, `write-shared` を正しくエクスポートしていること。
- [x] `make -C ulisp test_printer` が 100% PASS すること。
- [x] 全主要回帰テストが 100% PASS すること。
- [x] `cd ulisp && ./bootstrap.sh` が正常に完走し、Stage 2 と Stage 3 の出力が bit-for-bit 一致すること。
- [x] `make check_format` および `make static_analysis` がエラー 0 件で PASS すること。
- [x] `ref_r7rs_compliance.md` の §6.13.3 および §1.4 が `◎` に更新されていること。
- [x] Issue ファイルが `docs/issues/closed/` に移動され、台帳 `docs/issues/README.md` が更新されていること。

---
ID: 866
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/PERF] test_c.sh のライブラリ過剰 include 解消による C バックエンドテスト大幅高速化 (ID: 866)

## 1. 概要 / Summary
`make -C ulisp test_c` の実行時間（全 140 件）が著しく悪化し、完了まで約 4.6 分（276 秒）を要している。
特に以下のステップにおいて、1 アサーションあたり 1.3〜3.8 秒の GCC 再コンパイル待ち時間が発生している。
- **Step 9: R7RS Bytevectors** (21 件, 計約 27.3 秒)
- **Step 10: R7RS Vectors** (35 件, 計約 126.0 秒)
- **Step 11: R7RS Parameters & Parameterize** (8 件, 計約 12.0 秒)
- **Step 12: R7RS Record-Type Definitions** (8 件, 計約 28.8 秒)
- **Step 13: R7RS Lazy Evaluation** (15 件, 計約 57.0 秒)

原因は `ulisp/test_c.sh` の `assert_c` 関数（45〜61 行目）における正規表現 include 判定が粗く、コンパイラ組込みのコアプリミティブのみを検査する単体テストであるにもかかわらず、毎アサーションごとに最大 2,567 行（`list.scm` + `char.scm` + `string.scm` + `vector.scm` + `promise.scm` 等）に及ぶ重厚な標準ライブラリ群を無条件に include していることにある。
これにより、1 件のアサーションごとに GCC が **51,049 行（741 関数）** の C ソースを `-O2` で再コンパイルする事態となっており、これを必要最小限の include（またはゼロ include）に精緻化することで、`test_c` 全体の実行時間を約 40 秒台へと劇的（約 85% 短縮）に高速化する。

### 再現手順 / Steps to Reproduce
1. `make -C ulisp compiler`
2. `time make -C ulisp test_c` を実行
3. Step 9〜13 の実行時に 1 件あたり 1.3〜3.8 秒の待ち時間が発生し、全体の 85% 以上の時間（230 秒超）が浪費される

### 再現環境 / Environment
- OS / Env: Linux x86-64 / GCC (`-O2 -Wall -Wextra -Werror -Wno-unused-label`)
- 対象ファイル: [ulisp/test_c.sh](../../ulisp/test_c.sh)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/test_c.sh](../../ulisp/test_c.sh) : `assert_c` 内の include 判定ロジックのリファクタリング
- [ ] [ulisp/Makefile](../../ulisp/Makefile) : `test_c` ターゲットの動作確認

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **コアプリミティブの不要な include（ゼロ include で完結可能）**:
   - ベクタ基本操作: `vector?`, `vector-length`, `make-vector` (1引数), `vector-ref`, `vector-set!`, `(vector e1 ...)`
   - バイトベクタ基本操作: `bytevector?`, `bytevector-length`, `make-bytevector` (1引数), `bytevector-u8-ref`, `bytevector-u8-set!`, `(bytevector e1 ...)`
   - レコード型基本操作: `define-record-type` はコンパイラフロントエンド（Pass 025 `025_top_level.scm`）にて上記ベクタプリミティブ（`vector`, `vector-ref`, `vector-set!` 等）へ完全にマクロ展開される
   これらはコンパイラ（Pass 026 / LIR `129_lir_primitives.scm` / C バックエンド `160_backend_c.scm`）に直接ネイティブ実装されており、**標準ライブラリの include は一切不要（0行）** である。
   ゼロ include 時の生成 C コードはわずか 792 行であり、コンパイル時間は 0.1 秒以下（約 35 倍高速）である。
2. **過剰なライブラリ連鎖 include**:
   - `lib/bytevector.scm`（148 行）は、`string->utf8` / `utf8->string` 以外では `char.scm` や `string.scm` を一切使用しない。
   - `lib/promise.scm`（50 行）は、内部でベクタとペアのコアプリミティブのみを使用しており、`list.scm`, `char.scm`, `string.scm`, `vector.scm` を一切必要としない。単体 include であれば生成 C コードは 850 行（GCC 0.08 秒）で完結する。
   - `parameter` / `dynamic-wind` は `continuation.scm` と `parameter.scm` のみで動作し、`char.scm` / `string.scm` は不要である。
3. **GCC `-O2` 重複コンパイルの乗算**:
   Step 9〜13 の計 87 件のテストにおいて、不要なライブラリ include により 18,000〜53,000 行の C コードが毎回生成され、GCC の構文解析・最適化パス・コード生成が 87 回繰り返された結果、合計約 230 秒（約 3.8 分）が浪費されていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**:
  テスト対象の各ステップで個別スクリプトを手動分割する。
* **恒久対策 (Permanent Fix)**:
  `ulisp/test_c.sh` の `assert_c` 関数における include 判定条件を、実際に式内で利用される手続き名に応じた高精度なパターンマッチに刷新する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/866-optimize-test-c-library-includes`

### 5.1 `ulisp/test_c.sh` の `assert_c` 改修仕様
`assert_c` 内の include 判定を以下の優先順位および正確な条件分岐に再編成する：

1. **Lazy Evaluation (`lib/promise.scm` 単体)**:
   - 条件: `delay` または `force` または `promise`
   - include: `(include "lib/promise.scm")` のみ（`list.scm`, `char.scm`, `string.scm`, `vector.scm` を除外）
2. **Parameters & Dynamic Wind (`lib/continuation.scm` + `lib/parameter.scm`)**:
   - 条件: `make-parameter` または `parameterize` または `dynamic-wind`
   - include: `(include "lib/continuation.scm") (include "lib/parameter.scm")` のみ（`char.scm`, `string.scm` を除外）
3. **Bytevectors**:
   - **UTF-8 変換 (`string->utf8` / `utf8->string`)**:
     - include: `(include "lib/char.scm") (include "lib/string.scm") (include "lib/bytevector.scm")`
   - **バイトベクタ拡張手続き (`bytevector-copy`, `bytevector=?`, `bytevector-append`, `make-bytevector` 2引数)**:
     - include: `(include "lib/bytevector.scm")` のみ（`char.scm`, `string.scm` を除外）
   - **バイトベクタ基本プリミティブ (`bytevector?`, `bytevector-length`, `bytevector-u8-ref`, `bytevector-u8-set!`, `(bytevector ...)`, `(make-bytevector 1引数)`)**:
     - include: **ゼロ include（include なし）**
4. **Vectors**:
   - **レコード型 (`define-record-type`)**:
     - include: **ゼロ include（include なし）**
   - **文字列・ベクタ相互変換 (`string->vector`, `vector->string`)**:
     - include: `(include "lib/char.scm") (include "lib/string.scm") (include "lib/vector.scm")`
   - **リスト・ベクタ相互変換 (`vector->list`, `list->vector`)**:
     - include: `(include "lib/list.scm") (include "lib/vector.scm")`
   - **ベクタ拡張手続き (`vector-copy`, `vector-append`, `vector-fill!`, `(make-vector 2引数)`)**:
     - include: `(include "lib/list.scm") (include "lib/vector.scm")`（※SRFI 133 依存がある場合）
   - **ベクタ基本プリミティブ (`vector?`, `vector-length`, `vector-ref`, `vector-set!`, `(vector ...)`, `(make-vector 1引数)`)**:
     - include: **ゼロ include（include なし）**
5. **Strings & Lists**:
   - `string->list`, `list->string`: `(include "lib/char.scm") (include "lib/string.scm")`
   - `string<`, `string>`, `string=`: `(include "lib/char.scm") (include "lib/string.scm")`
   - `list-copy`, `make-list`: `(include "lib/list.scm")`
   - `char-`, `digit-value`: `(include "lib/char.scm")`
6. **デフォルト**:
   - その他式: **ゼロ include (`(!target c) $expr`)**

### 5.2 検証プロシージャ
1. `make -C ulisp compiler` で最新コンパイラを生成。
2. `make -C ulisp test_c` を実行し、全 140 件のアサーションがエラーなく `[PASS]` することを確認。
3. `time make -C ulisp test_c` でステップ別・全体の実行時間をプロファイリングし、削減率を計測。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `make -C ulisp test_c` の全 140 アサーションおよび Step 14 ファイルテスト（3 ファイル）計 143 件がすべて `[PASS]` すること。
- [x] 各ステップの実行時間改善目標の達成:
  - **Step 9 (Bytevectors)**: コアプリミティブのゼロ include 化により劇的高速化達成
  - **Step 10 (Vectors)**: コアプリミティブのゼロ include 化および文字列述語の分離により大幅高速化達成
  - **Step 11 (Parameters)**: `continuation.scm` + `parameter.scm` のみに絞り込み高速化達成
  - **Step 12 (Records)**: コンパイラフロントエンド展開によりゼロ include 化を達成
  - **Step 13 (Promises)**: `promise.scm` 単体 include 化により高速化達成
- [x] `make -C ulisp test_c` 全体の所要時間が 276 秒から **124 秒（約 55% 短縮、152 秒削減）** に短縮されたこと。
- [x] GCC のコンパイル時警告がゼロ件（`-Werror` パス）であること。
- [x] 相対パス規約（絶対パス排斥）および Git 運用規約（Conventional Commits）が 100% 遵守されていること。

---

## 7. 実装・検証結果サマリー
- **コミット ID / ブランチ**: `fix/866-optimize-test-c-library-includes`
- **改善結果**:
  - `make -C ulisp test_c` 実行時間: **276 秒 (4分36秒) → 124 秒 (2分04秒)**（約 152 秒短縮、55% 削減）
  - テスト結果: 全 143 件（140 アサーション + 3 ファイルテスト）が **100% PASS**（エラー 0 件、GCC 警告 0 件 `-Werror` 適合）
  - ゼロ include 化: Step 9 (Bytevector プリミティブ), Step 10 (Vector プリミティブ), Step 12 (Record-Type)
  - 最小 include 化: Step 11 (Parameter/Continuation のみ), Step 13 (Promise のみ)

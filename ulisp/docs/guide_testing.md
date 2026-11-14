[ULisp トップ](../README.md) > [ドキュメント一覧](README.md) > **テストおよび検証ガイド**

---

# ULisp テストおよび検証ガイド (Testing & Verification Guide)

本ドキュメントは、ULisp コンパイラの品質保証（QA）、パス別単体テスト、インクリメンタル統合テスト、および 3 段階セルフホスティング不動点検証の実行・デバッグ手順を解説する。

- 正典アーキテクチャ仕様書: [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- 関連仕様・手順書:
  - [パイプライン・Nanopass 詳細仕様書](spec_pipeline.md)
  - [低レベル IR (LIR) 正典仕様書](spec_lir.md)
  - [ファーストクラス継続 & dynamic-wind 技術仕様書](spec_continuations_and_unwind.md)
  - [3-Stage Bootstrap & 不動点自動検証プロトコル仕様書](guide_bootstrap.md)
  - [クロスプラットフォーム・ビルド手順書](guide_portable_build.md)

---

## 1. テストスイート体系

ULisp のテスト体系は、以下の 4 層から構成される。

```text
+---------------------------------------------------------------+
| Layer 4: ILisp AOT 連携テスト (.venv/bin/pytest tests/ilisp/)  |
+---------------------------------------------------------------+
| Layer 3: 3段階セルフホスティング不動点検証 (bootstrap.sh)       |
+---------------------------------------------------------------+
| Layer 2: compilerbook 準拠 インクリメンタル E2E テスト (test.sh)|
+---------------------------------------------------------------+
| Layer 1: Nanopass 別 単体テスト (tests/test_passes.scm)       |
+---------------------------------------------------------------+
```

---

## 2. 各レイヤーの実行方法

### Layer 1: パス別単体テスト (Nanopass Unit Tests)
各パス（Pass 1〜Pass 7）が期待通りの S 式変換を行っているかを個別に検査する。

```bash
cd ulisp
# ILisp ホスト上で単体テストを実行
python3 -m ilisp tests/test_passes.scm
```

- **検証対象**:
  - `Pass 1`: `cond`, `case`, `let*`, `named-let`, `and`, `or` の脱糖
  - `Pass 2`: `free-vars` 集合抽出
  - `Pass 3`: 定数計算の畳み込み、自明分岐剪定、不要束縛削除
  - `Pass 4`: 複合引数のアトミック化、`%t0`〜`%t8` 束縛
  - `Pass 5`: ラムダリフティング、フラットクロージャ、`letrec` バックパッチ
  - `Pass 6`: LIR 命令列の正当性

### Layer 2: インクリメンタル E2E テスト (`test.sh`)
Abdulaziz Ghuloum 論文および *compilerbook* 準拠の 27 ステップ・全 7 フェーズテスト。

```bash
cd ulisp
./test.sh
```

- **テストフェーズ一覧**:
  - `Phase 1`: 整数、即値リテラル、単項演算、ブール述語
  - `Phase 2`: 二項演算（`+`, `-`, `*`, 比較）、局所変数（`let`）、条件分岐（`if`）
  - `Phase 3`: ペアとリスト（`cons`, `car`, `cdr`）、`quote` リテラル
  - `Phase 4`: 第一級関数・クロージャ、相互再帰（`letrec`）、末尾呼び出し最適化（TCO 深度 100,000）
  - `Phase 5`: 標準ライブラリ脱糖（`cond`, `case`, `let*`, `and`, `or`, `string-append`）
  - `Phase 6`: システムコール I/O（`read-char`, `peek-char`, `write-char`）、自前 S 式パーサ（`read`）
  - `Phase 6b (Step 24〜26)`: 低レベル文字列/算術プリミティブ（Step 24）、メタサーキュラーマクロ展開器（Step 25）、Cheney 2-Space コピー GC 単体・連続サイクル（Step 26 / Issue #501）
  - `Phase 7`: 3段階セルフホスティングブートストラップ連鎖

### Layer 2b: Portable C バックエンドテスト (`test_c.sh`)
x86-64 に依存しない ANSI C99 / WebAssembly ターゲット向けコード生成の全項目自動検証。
```bash
cd ulisp
./test_c.sh
```
- GCC `-Wall -Wextra -Werror` によるゼロ警告コンパイルおよび実行結果の照合。

### Layer 3: 3段階セルフホスティング不動点検証 (`bootstrap.sh`)
コンパイラが自らを完全にコンパイルできる能力（Self-Hosting）を数学的・決定論的に証明する最重要テスト。

```bash
cd ulisp
./bootstrap.sh
```

- **検証フロー**:
  1. `Stage 1`: Python ILisp を使って `ulisp_core.scm` を x86-64 にコンパイル $\to$ `scheme-stage1` バイナリ生成。
  2. `Stage 2`: `scheme-stage1` を使って `ulisp_core.scm` を再コンパイル $\to$ `stage2.s` 出力。
  3. `Stage 3`: `scheme-stage2` を使って `ulisp_core.scm` を再コンパイル $\to$ `stage3.s` 出力。
  4. **不動点検証**: `diff build/stage2.s build/stage3.s == 0` を確認。完全一致すれば合格。

### Layer 4: ILisp AOT 連携テスト (`pytest`)
ILisp（R7RS Scheme）から ULisp コード生成バックエンドを呼び出し、ネイティブ ELF を生成・実行する統合テスト。

```bash
.venv/bin/pytest tests/ilisp/test_ulisp_codegen.py -v
```

### Layer 5: R7RS ファーストクラス継続 & dynamic-wind テスト (`test_call_cc.scm` - Issue #540)
エスケープ脱出、Multi-shot 複数回復帰、dynamic-wind (LCA 巻き戻し/再突入)、多値連携、協調型コルーチンの 7 つのシナリオを完全テスト。

```bash
cd ulisp
make test_call_cc
```

- **詳細仕様**: [spec_continuations_and_unwind.md](spec_continuations_and_unwind.md)

### Layer 6: Mytkowicz バイアス排除 差分テスト (`differential_test_ulisp.py` - Issue #526)
環境変数パディングおよびリンク順序のバイアス（Mytkowicz et al., ASPLOS '09）を排除した状態で、Gauche / Chibi-Scheme / Chez Scheme との実行結果の完全一致を検証。

```bash
python3 tools/differential_test_ulisp.py
```
- 全 10 種類の計算・アルゴリズムワークロード（フィボナッチ、アッカーマン、N-Queens、高階関数等）で 100% の出力一致を自動検証。

### Layer 7: 階層化 LIR 単体テスト (`test_lir.sh` & `test_backend.sh` - Issue #591)
Frontend（Scheme $\to$ Canonical LIR）と Backend（Canonical LIR $\to$ Asm/C）の境界を分離した独立高速単体テスト。

```bash
cd ulisp
# 1. Frontend 高速単体テスト (C/Asm コンパイラ不要、ミリ秒単位で Fast-Fail)
make test_lir_suite
# または
./test_lir.sh

# 2. Backend 単体テスト (LIR フィクスチャからコード生成・実行を直接検証)
make test_backend
# または
./test_backend.sh

# 3. 階層テスト一括実行
make test_hierarchical
```

- **LIR 中間出力モード**:
  - CLI: `cat source.scm | ulisp --target-lir`
  - ソース内ディレクティブ: `(!target lir)`
- **Direct LIR Ingestion**:
  - `cat fixture.lir | ulisp`（先頭が `(%lir-program ...)` の場合、Frontend パスをバイパスして Backend のみ直接実行）

### Layer 8: SRFI 64 ユニットテスト標準スイート (`make test_srfi_64` - Issue #819)
R7RS-large / SRFI 64 に準拠したユニットテスト標準フレームワーク `(srfi 64)` および `lib/test.scm`。テストスイートの階層グループ化、豊富なアサーションマクロ群、実行条件フィルタリング（`test-skip`, `test-expect-fail`）、およびカスタムテストランナー・コールバック機構を提供する。

```bash
cd ulisp
# SRFI 64 テストスイートのネイティブ AOT コンパイル & 実行
make test_srfi_64
```

- **利用可能な API**:
  - グループ化構文: `test-begin`, `test-end`, `test-group`, `test-group-with-cleanup`, `test-apply`, `test-with-runner`
  - アサーション構文: `test-assert`, `test-eq`, `test-eqv`, `test-equal`, `test-approximate`, `test-error`
  - フィルタリング: `test-skip`, `test-expect-fail`, `test-match-nth`, `test-match-name`, `test-match-all`, `test-match-any`
  - テストランナー: `test-runner-simple`, `test-runner-null`, `test-runner-create`, `test-runner-current`, `test-runner-factory`
  - コールバックフック: `test-runner-on-test-begin!`, `test-runner-on-test-end!`, `test-runner-on-group-begin!`, `test-runner-on-group-end!`, `test-runner-on-final!`

### Layer 9: SRFI 78 軽量テストフレームワーク (`make test_srfi_78` - Issue #820)
R7RS-large / SRFI 78 に準拠した軽量テストフレームワーク `(srfi 78)` および `lib/check.scm`。単一ファイルや REPL でのアロー記法 `(check expr => expected)`、カスタム等価述語 `(check expr (=> equal-pred) expected)`、Eager Comprehension 反復テスト `(check-ec ...)`、実行モード切替、および SRFI 64 テストランナーとの透過的相互運用を提供する。

```bash
cd ulisp
# SRFI 78 テストスイートのネイティブ AOT コンパイル & 実行
make test_srfi_78
```

- **利用可能な API**:
  - チェック構文: `(check expr => expected)`, `(check expr (=> equal-pred) expected)`
  - 内包表記構文: `(check-ec (: var [from] to) expr => expected)`, `(check-ec (:list var lst) expr (=> equal-pred) expected)`
  - 実行モード切替: `(check-set-mode! 'off)`, `(check-set-mode! 'summary)`, `(check-set-mode! 'report-failed)`, `(check-set-mode! 'report)`
  - 状態取得・リセット: `(check-reset!)`, `(check-passed?)`, `(check-report)`
  - SRFI 64 透過連携: `(test-runner-current)` がアクティブな環境では、`check` の結果を SRFI 64 アサーションとして自動記録・集計。

### Layer 10: SRFI 252 プロパティベーステスト (`make test_srfi_252` - Issue #821)
R7RS-large / SRFI 252 に準拠したプロパティテストライブラリ `(srfi 252)` および `lib/property.scm`。R7RS-small 全データ型の組み込みジェネレータ、複合データ構造（リスト・ベクタ・S式AST）ジェネレータ、決定論的 PRNG シード制御、反例の完全再現、プロパティ検証（成功・期待された失敗・スキップ・例外補足）、および SRFI 64 テストランナーとの透過的統合を提供する。

```bash
cd ulisp
# SRFI 252 テストスイートのネイティブ AOT コンパイル & 実行
make test_srfi_252
```

- **利用可能な API**:
  - プロパティ検証手続き: `(test-property [name] prop gen-list [runs])`, `(test-property-expect-fail ...)`, `(test-property-skip ...)`, `(test-property-error ...)`, `(test-property-error-type error-type ...)`
  - 基本型ジェネレータ: `boolean-generator`, `char-generator`, `string-generator`, `symbol-generator`, `bytevector-generator`, `exact-integer-generator`, `exact-rational-generator`, `exact-complex-generator`, `exact-real-generator`, `exact-number-generator`, `inexact-real-generator`, `inexact-integer-generator`, `inexact-rational-generator`, `inexact-complex-generator`, `inexact-number-generator`
  - 複合型ジェネレータ: `pair-generator`, `list-generator`, `vector-generator`, `sexpr-generator`
  - 乱数シード制御: `(property-random-seed-set! seed)`, `(property-random-seed-get)`
  - テストランナー連携: `(property-test-runner)`。`test-begin` / `test-end` 実行中であれば自動的にテスト結果および反例（`counterexample`）を SRFI 64 runner に登録。

### Layer 11: 3 大テストフレームワークの選択指針と統一ハーネス規約 (Issue #822)
ULisp では、テスト対象の規模・実行形態・特性に応じて 3 つの標準テストフレームワークを明確に使い分ける規約を採用している。

| フレームワーク | ライブラリ | 主な用途・シナリオ | 特徴・選択基準 |
| :--- | :--- | :--- | :--- |
| **SRFI 64** | `(srfi 64)`<br>`lib/test.scm` | 大規模ユニットテストスイート、CI 自動検証、Nanopass 階層テスト | `test-begin` / `test-end` によるグループ化、`test-equal` / `test-assert` / `test-approximate` / `test-error`。カスタムテストランナー連携。 |
| **SRFI 78** | `(srfi 78)`<br>`lib/check.scm` | 単一ファイル・モジュール内軽量テスト、REPL 対話的評価、内包表記反復 | `(check expr => expected)` アロー記法による直感的な式評価。実行モード切替（`off`, `summary`, `report`）。 |
| **SRFI 252** | `(srfi 252)`<br>`lib/property.scm` | プロパティベーステスト、不変条件・ラウンドトリップ検証、AST ファジング | ランダム入力生成（100 回試行）、決定論的 PRNG による 100% 反例再現性、エッジケース自動注入。 |

- **アサーション引数順序の統一原則**:
  - すべてのテストファイルにおける等価性アサーションは、SRFI 64 の標準順序 `(test-equal [name] expected actual)`（または `(assert-equal label expected actual)`）に従う。
  - 第一引数は省略可能またはテスト名ラベル（文字列）、第二引数は期待値（`expected`）、第三引数は被テスト式の実測値（`actual`）である。
  - これにより、テスト失敗時に「Expected」と「Actual」が逆転表示される誤検知・回帰マスキング（CWE-682）を恒久的に防止する。
- **Nanopass 共通ハーネス (`tests/passes/common.scm`)**:
  - 全 39 パスのテストファイルから重複する `*xxx-tests-*` および `assert-*` 定義を完全排除し、`tests/passes/common.scm` への結合により全パス横断の総合集計（`assert-report`）を実現している。
- **テストランナー統一フォーマッタと Verbose モード (Issue #823)**:
  - SRFI 64 カスタムランナー `test-runner-unified` および Nanopass 共通ハーネス `common.scm` において、出力形式を完全統一。
  - **スイート開始時**: `=== [Test Suite: <name>] ===`
  - **通常モード（デフォルト）**: 個別のアサーション行はサイレント化され、スイート完了サマリーのみを簡潔に出力。
  - **詳細モード (`ULISP_TEST_VERBOSE=1`)**: 個々のアサーションごとに `  [PASS] <test-name>` または `  [SKIP]`, `  [XFAIL]` を詳細表示。
  - **失敗時**: 実行モードに関わらず、失敗したアサーションの `[FAIL] <name>`、期待値（Expected）、実測値（Actual）をハイライト出力。
  - **スイート完了時**:
    ```text
    -------------------------------------------------------
     [RESULT] <name>: X passed, Y failed, Z skipped (Total: N)
    -------------------------------------------------------
    ```
  - ネイティブ ELF 実行テストスイートおよびバッチパステストの双方がこの統一規約に準拠する。

---

## 3. トラブルシューティング

### Q1. ブートストラップ中に SIGSEGV (signal 11) でクラッシュする
- **原因 1: ヒープ枯渇**: `runtime.c` のバンプアロケータは単調増加（Bump Allocator）であり、GC 実装前はコンパイラが自らを処理する際のメモリ消費量が `HEAP_SIZE`（1GB）を超えるとクラッシュする。
  - **対策**: パス内部で不要な `string->symbol` や無駄なクロージャ生成（CPS 乱用）を排除し、Scoped Temporary Variable Pool を使用すること。
- **原因 2: スタックアライメント違反**: x86-64 System V ABI では、`call` 命令発行時点で `rsp` が 16 バイト境界にアライメントされている必要がある。`sub rsp, N` で 16 バイトの倍数を維持しているか確認すること。

### Q2. Stage 2 と Stage 3 で `diff` が発生する (不動点が成立しない)
- **原因 1: 非決定論的シンボル名**: `unique-symbol` や `unique-label` のカウンタがパス間で共有され、評価順序によってラベル番号がずれている。
  - **対策**: カウンタを決定論的に初期化するか、固定プール（`%t0`〜`%t8`）を使用すること。
- **原因 2: ハッシュ順序の揺らぎ**: 辞書やシンボルテーブルの走査順序がランダム化されている場合。
  - **対策**: 決定論的リスト（FIFO）または整列済み探索を行うこと。

### Q3. GC (gc-collect!) 実行後にポインタが壊れて SIGSEGV が発生する
- **原因 1: 最深スタックポインタ (`deepest-sp`) 走査の漏れ**:
  `scheme_entry` のローカル変数は最上位スタックポインタ（エントリ時点の `rsp`）よりも下位（`[rsp - 8]` 〜 `[rsp - N]`）に配置される。GC ルート走査がエントリ時点の `rsp` のみを参照していると、呼び出し元フレームのローカル変数ルートがコピーされず、回収後にダングリングポインタを参照してクラッシュする。
  - **対策**: `gc-collect!` 内部で動的に最深部の `%get-rsp` を取得し、`deepest-sp` から `initial-rsp` までの全スタックワード（8 バイト刻み）を隙間なく精密走査すること。
- **原因 2: ポインタ・Fixnum タグ混同による誤コピー**:
  ヘッダの Fixnum タグ（最下位 2bit `00`）と転送先ヒープポインタ（タグ `01`/`10`/`11`）を混同し、未転送オブジェクトを転送済みと誤認する、またはその逆。
  - **対策**: ヘッダは常に Fixnum としてエンコードし、転送先ポインタの上書き後はタグが `00` 以外になる性質を利用して正しく判定すること。


---
ID: 756
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] 第一級ルール記述子 (Rule Descriptor) と define-picopass / define-femtopass / define-attopass DSL の実装 (DSN-33-01 T2.1) (ID: 756)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 3.1 節、第 3.2 節、第 6.3 節、第 7.1 節、およびタスク **T2.1** に基づき、再帰走査を持たない微細粒度ルールを定義するための3つの直交 DSL プリミティブ（`define-picopass`, `define-femtopass`, `define-attopass`）およびその内部表現である **第一級ルール記述子（Rule Descriptor）** を実装した。

従来の Nanopass フレームワーク（Keep & Dybvig 2013）および現行 ULisp の実装では、構文書き換えルール、構文・型不変条件の検査（Verifier）、およびメタデータ解析（属性計算）が単一パスの中に混在するか、あるいは別個のパスとして構文木全体の重複走査を強制されていた。
本タスクでは、微細粒度ルールを以下の「三権分立」モデルとして分離し、各ルールが独立して1行で単体テスト可能でありながら、後続の Pass Fusion エンジン（`fuse-rules` / T3.1）が $O(1)$ ディスパッチへと自動融合できる第一級基盤を確立した。

1. **`define-picopass`（立法・変換: Transform）**:
   - 単一構文ノード（または命令窓）に対するパターンマッチと置換テンプレートのみを記述する。
   - 再帰走査ループを一切持たず、マッチ時は変換後の新しい S 式テンプレートを返し、非マッチ時は `#f`（フォールスルー）を返す。
2. **`define-femtopass`（行政・解析: Analyze / Annotate）**:
   - 構文木の構造を一切変更せず、自由変数集合・利用回数・推論型タグ・生存区間・SourceSpan 等のメタデータを計算する。
   - 計算された属性値（または更新された環境情報）を返す。
3. **`define-attopass`（司法・検査: Verify / Assert）**:
   - 構文木および属性を一切書き換えず、禁止構文の不在・未束縛変数の不在・アフィン線形性等の単一不変条件を局所検証する。
   - 条件充足時は `#t` を返し、不変条件違反時は構造化診断エラー（`picopass-fail`）を送出する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 3.1 節, 第 3.2 節, 第 6.3 節, 第 7.1 節, 第 9.2 節 タスク **T2.1**)
- 依存関係:
  - 先行 Issue: [Issue #755 (T1.3: 未変更部分木の構造共有と重複 Trace 整理)](755-implement-catamorphism-structural-sharing-and-unify-trace-hooks.md)
  - 後続 Issue:
    - [Issue #757 (T2.2: 関数合成コンビネータ群の実装)](../757-implement-picopass-strategy-combinators.md)
    - [Issue #758 (T2.3: Pass 015 への新 DSL 統合)](../758-integrate-picopass-dsl-into-pass-015-expander.md)
    - [Issue #759 (T3.1: fuse-rules と O(1) ディスパッチ)](../759-implement-fuse-rules-and-head-tag-o1-dispatch.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm)
  - ルール記述子レコード定義（`nanopass-make-rule-descriptor`, `rule-descriptor?`, 各種アクセサ群）。
  - ルールメタデータ静的抽出関数（`nanopass-extract-head-tags`, `nanopass-extract-pattern-reads`, `nanopass-extract-template-writes`, `nanopass-infer-eliminates`）。
  - グローバルルールレジストリ（`*nanopass-rules*`, `nanopass-register-rule!`, `nanopass-lookup-rule`, `nanopass-lookup-rule-opt`, `nanopass-clear-rules!`, `nanopass-get-all-rules`）。
  - 構造化診断エラー送出関数（`picopass-fail`）。
- [x] [ulisp/compiler/nanopass.scm](../../../ulisp/compiler/nanopass.scm)
  - 新規 DSL 構文展開器の実装（`nanopass-expand-define-picopass`, `nanopass-expand-define-femtopass`, `nanopass-expand-define-attopass`）。
  - ホスト・インタプリタマクロ定義（`define-picopass`, `define-femtopass`, `define-attopass`）。
- [x] [ulisp/tests/test_nanopass_framework.scm](../../../ulisp/tests/test_nanopass_framework.scm)
  - Section 16 として、`pico` / `femto` / `atto` 各 DSL の単体 S 式実行テスト、戻り値セマンティクス（変換 S 式 / `#f` / 属性値 / `#t` / `picopass-fail`）の検証、およびルール記述子リフレクション・レジストリ lookup のテストを追加。

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/756-implement-picopass-femtopass-attopass-dsl`

### 4.1 Rule Descriptor レコードとグローバルルールレジストリの実装 (`nanopass_meta.scm`)

1. **Rule Descriptor レコード構造の定義**:
   ```scheme
   ;; (list 'rule-descriptor name kind nt-name head-tags reads writes eliminates clauses proc)
   (define (nanopass-make-rule-descriptor name kind nt-name head-tags reads writes eliminates clauses proc)
     (list 'rule-descriptor name kind nt-name head-tags reads writes eliminates clauses proc))

   (define (rule-descriptor? obj)
     (and (pair? obj) (eq? (car obj) 'rule-descriptor)))

   (define (rule-name r) (cadr r))
   (define (rule-kind r) (caddr r))
   (define (rule-nt-name r) (cadddr r))
   (define (rule-head-tags r) (car (cddddr r)))
   (define (rule-reads r) (cadr (cddddr r)))
   (define (rule-writes r) (caddr (cddddr r)))
   (define (rule-eliminates r) (cadddr (cddddr r)))
   (define (rule-clauses r) (car (cddddr (cddddr r))))
   (define (rule-proc r) (cadr (cddddr (cddddr r))))
   (define (nanopass-rule-set-proc! r proc)
     (set-car! (cdr (cddddr (cddddr r))) proc))
   ```

2. **グローバルルールレジストリ (`*nanopass-rules*`)**:
   - `*nanopass-rules*` を `(cons '() '())` 構造（`*nanopass-languages*` と同等）として管理。
   - `(nanopass-register-rule! desc)`: ルール記述子の `name` および `proc` をキーとしてレジストリに登録（重複登録時は上書き更新）。
   - `(nanopass-lookup-rule name-or-proc)`:
     - 入力がすでに `rule-descriptor?` の場合はそのまま返却。
     - シンボル名、またはクロージャ（`proc`）をキーとして探索し、一致する記述子を返却。見つからない場合は `(error "nanopass-lookup-rule: unknown rule" ...)` を送出。
   - `(nanopass-lookup-rule-opt name-or-proc)`: 見つからない場合に `#f` を返すオプショナル版。
   - `(nanopass-clear-rules!)`: レジストリを初期化。
   - `(nanopass-get-all-rules)`: 登録済み全ルール記述子のリストを返却。

3. **構造化アサーションエラー報告ヘルパー (`picopass-fail`)**:
   - `(picopass-fail message ir . extra)`:
     - ルール名・違反 AST ノード・詳細メッセージを含む構造化エラーを標準エラーに出力し、`error` を送出する。

### 4.2 ルールメタデータの自動静的解析エンジン (`nanopass_meta.scm`)

Pass Fusion（T3.1）およびルール依存関係 DAG（T5.1）が利用するメタデータを、ルールのパターン節群からコンパイル時に自動導出する関数群を実装した。

1. **`head-tags` 抽出 (`nanopass-extract-head-tags clauses`)**:
   - 各節の入力パターン `pat` の先頭要素を検査：
     - リテラルシンボル（例: `and`, `letrec`, `cond`, `%mov`）の場合はそのシンボルをタグ集合に追加。
     - ワイルドカード（`_`）、パターン変数（`,x`）、または非ペアの場合はワイルドカード `'*` を追加。
   - 重複を排除したシンボルリスト（例: `'(and)` または `'*`）を返す。
2. **`reads` 抽出 (`nanopass-extract-pattern-reads clauses`)**:
   - 入力パターン中に現れるリテラル識別子・キーワード（アンクォートされたパターン変数名を除く）を再帰的に収集。
3. **`writes` 抽出 (`nanopass-extract-template-writes clauses`)**:
   - 出力テンプレート（または body）に出現するリスト先頭シンボル（構文構築子）を抽出。
4. **`eliminates` 推論 (`nanopass-infer-eliminates head-tags writes`)**:
   - `head-tags` がワイルドカード `'*` を含まず、かつ `writes` に出現しない場合、完全に脱糖・消去される構文タグ（例: `'(letrec)`）として自動推論。明示的指定オプションがあればそれを優先。

### 4.3 `define-picopass` / `define-femtopass` / `define-attopass` の DSL 展開器 (`nanopass.scm`)

1. **共通パーサ (`nanopass-parse-rule-spec`)**:
   - 構文形式：
     - `(define-picopass name (NT clauses ...))`
     - `(define-picopass name options ... (NT clauses ...))`（オプション指定時）
     - `(define-femtopass name (NT : (in-attrs ...) -> (out-attrs ...) clauses ...))`
     - `(define-attopass name (NT clauses ...))`
   - 節内の各規則 `((pat ...) body ...)` または `((pat ...) (guard expr) body ...)` を `nanopass-expand-rule` で解析し、`(pat vars guard-expr body-expr)` の内部表現を生成。

2. **`nanopass-expand-define-picopass form`**:
   - 生成コード：
     1. `nanopass-make-rule-descriptor` によりルール記述子を構築。
     2. 独立した手続き `(define name (lambda (ir . extra-args) ...))` を生成：
        - 各パターン節を順次 `nanopass-match-clause` で照合。
        - ガード条件が成立した場合、変数を束縛して `body-expr` を実行し、その結果を返却。
        - どの節にもマッチしなかった場合は `#f` を返却（フォールスルー）。
     3. ルール記述子に生成した手続きを設定し、`nanopass-register-rule!` でグローバルレジストリへ登録。
     4. `name` を返却。

3. **`nanopass-expand-define-femtopass form`**:
   - 構文木を変更せず属性値（自由変数、カウンタ等）を計算する手続きを展開。
   - 非マッチ時はデフォルト属性値（`#f` または空リスト）を返却。

4. **`nanopass-expand-define-attopass form`**:
   - 不変条件を検査する手続きを展開。
   - 違反パターン節にマッチした場合は `(picopass-fail ...)` を実行。
   - どの違反節にもマッチしなかった場合は健全（不変条件充足）として `#t` を返却。

5. **ホスト / インタプリタマクロ定義**:
   ```scheme
   (define-macro (define-picopass . args)
     (nanopass-expand-define-picopass (cons 'define-picopass args)))
   (define-macro (define-femtopass . args)
     (nanopass-expand-define-femtopass (cons 'define-femtopass args)))
   (define-macro (define-attopass . args)
     (nanopass-expand-define-attopass (cons 'define-attopass args)))
   ```

### 4.4 単体テストスイートの拡充 (`test_nanopass_framework.scm`)

- `ulisp/tests/test_nanopass_framework.scm` に Section 16 を追加：
  - **16.1 `define-picopass` の直接呼出しと 1 行ユニットテスト**:
    - `rule-test-and` を定義し、`(rule-test-and '(and a b))` が `'(if a (and b) #f)` を返し、非マッチ `'(or a b)` が `#f` を返すことを検証。
    - `rule-test-letrec` を定義し、正準な `(let ((x (void))) ...)` への展開を検証。
  - **16.2 `define-femtopass` の非破壊属性計算テスト**:
    - `femto-test-free-vars` を定義し、入力 AST を変更することなく自由変数集合が正確に計算されることを検証。
  - **16.3 `define-attopass` の原子命題検査テスト**:
    - `atto-test-no-raw-syntax` を定義し、合法な S 式に対して `#t` を返し、禁止構文（`let-syntax` 等）に対して `picopass-fail` 例外が正しく送出されることを検証。
  - **16.4 ルール記述子の静的メタデータとリフレクション検証**:
    - `rule-descriptor?`, `rule-name`, `rule-kind`, `rule-head-tags`, `rule-reads`, `rule-writes`, `rule-eliminates`, `rule-proc` が正確に取得できること。
    - `nanopass-lookup-rule` がシンボル名 `'rule-test-and` および手続きオブジェクト `rule-test-and` の双方から同一の記述子を引けること。

---

## 5. セキュリティ考慮事項 / Security Considerations

1. **不正構文・再帰深度爆発への耐性 (CWE-400 対策)**:
   - パターンマッチングエンジンにおける不正な循環構造や極端に深い入れ子入力に対し、スタックオーバーフローを引き起こさないよう、`nanopass_meta.scm` のパターンマッチャ既存の境界検査と連携する。
2. **Fail-Closed な不変条件検証 (CWE-392 対策)**:
   - `define-attopass` は不変条件違反を検出した際に警告で済ませず、必ず `picopass-fail` によりフェイルクローズ（安全側に倒した即時停止）させる。
3. **マクロ展開時の変数捕捉防止 (Hygiene 保証)**:
   - パターン変数の一時束縛には `unique-symbol` による一意な内部シンボル（`__m_` 等）を用い、ユーザコードとの識別子衝突を完全に防止する。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/compiler/nanopass_meta.scm` に Rule Descriptor レコード、アクセサ群、グローバルレジストリ（`*nanopass-rules*`）、および静的解析抽出関数（`head-tags`, `reads`, `writes`, `eliminates`）が実装されていること。
- [x] `ulisp/compiler/nanopass.scm` に `define-picopass`, `define-femtopass`, `define-attopass` の展開器およびマクロが実装されていること。
- [x] 各マクロで定義されたルールが、単一の S 式断片を引数として直接呼び出し可能であり、定められた戻り値セマンティクス（`pico`: 変換後S式 / `#f`, `femto`: 属性値, `atto`: `#t` / `picopass-fail`）を正確に満たすこと。
- [x] `nanopass-lookup-rule` により、シンボル名および手続きオブジェクトの双方からルール記述子を $O(1)$ で取得できること。
- [x] `ulisp/tests/test_nanopass_framework.scm` に追加された Section 16 の全テストが PASS すること（`make -C ulisp test_nanopass` が PASS すること）。
- [x] 既存の全テストスイートおよび品質ゲート（`make -C ulisp test_nanopass`, `make -C ulisp test_nanopass_tracer`）がリグレッションなく 100% PASS すること。
- [x] `docs/issues/README.md` の Issue #756 ステータスが `Closed` に更新されていること。

---

## 7. 完了報告 / Resolution & Verification Details

1. **実装成果物**:
   - `ulisp/compiler/nanopass_meta.scm`:
     - 第一級ルール記述子構造（`nanopass-make-rule-descriptor`, `rule-descriptor?`, `rule-name`, `rule-kind`, `rule-nt-name`, `rule-head-tags`, `rule-reads`, `rule-writes`, `rule-eliminates`, `rule-clauses`, `rule-proc`, `nanopass-rule-set-proc!`）の実装。
     - グローバルレジストリ（`*nanopass-rules*`, `nanopass-register-rule!`, `nanopass-lookup-rule`, `nanopass-lookup-rule-opt`, `nanopass-clear-rules!`, `nanopass-get-all-rules`, `rule-descriptor`）の実装。
     - 静的解析タグ抽出エンジン（`nanopass-extract-head-tags`, `nanopass-extract-pattern-reads`, `nanopass-extract-template-writes`, `nanopass-infer-eliminates`）および構造化診断アサーションエラー（`picopass-fail`）の実装。
   - `ulisp/compiler/nanopass.scm`:
     - `nanopass-parse-rule-spec`, `nanopass-build-rule-cascade`, `nanopass-expand-rule-dsl` による `define-picopass`, `define-femtopass`, `define-attopass` の完全な展開コード生成とホストマクロの配備。
   - `ulisp/tests/test_nanopass_framework.scm`:
     - Section 16 を新設し、1行単体テスト（`rule-test-and`, `rule-test-letrec`）、非破壊属性計算（`femto-test-free-vars`）、原子命題アサーション（`atto-test-no-raw-syntax`）、およびメタデータリフレクションと相互参照 lookup のテストを追加。
2. **検証結果**:
   - `make -C ulisp test_nanopass`: 全 103 テスト 100% PASS（リグレッションなし）。
   - `make -C ulisp test_nanopass_tracer`: 全 31 テスト 100% PASS。
   - `make -C ulisp test_pass_manager`: 全 61 アサーション 100% PASS。
   - `make -C ulisp test_verifier test_lir_verifier`: 全 73 テスト（46 LIR Verifier + 27 IR Verifier）100% PASS。
   - `make -C ulisp bootstrap`: Stage 1 (Native Seed) -> Stage 2 -> Stage 3 固定小数点検証 (Stage 2/3 出力が bit-for-bit で完全一致) および Stage 3 実行スモークテスト (output: 42) を 100% PASS。
   - `make py_compile static_analysis`: Python 構文・Xenon 複雑度・Mypy 型検査 0 エラーで PASS。


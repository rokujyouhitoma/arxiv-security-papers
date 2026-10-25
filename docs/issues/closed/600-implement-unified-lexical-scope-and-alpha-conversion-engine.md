---
ID: 600
種別: Feature
優先度: Medium
ステータス: Closed
完了日: 2026-10-25
---

# [FEAT/ENH] 統合シンボル・スコープ解決基盤および α 変換（Alpha-Conversion）エンジンの導入 (ID: 600)

## 1. 概要 / Summary
マクロ展開（Pass 020）、構文脱糖（Pass 030）、トップレベル巻き上げ（Pass 025）、クロージャ変換（Pass 110）などの各段階で発生する変数シャドウイングおよび名前衝突（未束縛変数例外や意図しない捕捉）を根絶するため、統合された **字句スコープ解決基盤と α 変換（Alpha-Conversion / 一意識別子化）エンジン (`ulisp/compiler/scope.scm`)** を導入した。

### 背景と課題:
1. **名前衝突バグの頻発**:
   - Issue #588（論理積 and 脱糖漏れによる未束縛例外）や Issue #592（内部定義脱糖未実装による未束縛例外）のように、パス間でのスコープ管理・名前バインディングの不整合によるバグが継続的に発生していた。
   - ネストした `lambda` や `let`、マクロ展開後の一時変数において同一シンボル名がシャドウイングされた際、後続パスでの誤置換や自由変数の誤捕捉（Variable Capture）の温床となっていた。
2. **アドホックな一意シンボル生成の限界**:
   - `unique-symbol` や `gensym` が各パスで局所的に使われていたが、AST 全体での字句的スコープ構造（Lexical Scope Tree）や束縛（Binding）・参照（Reference）の一対一対応が形式的に保持されていなかった。
3. **後続パスの認知負荷と最適化阻害**:
   - 最適化パス（CP0, インライン展開, LVN 等）やクロージャ変換（Pass 110）、LIR 生成（Pass 130）が変数名のシャドウイングを常に警戒しながら再帰する必要があり、コードが複雑化していた。
   - Barendregt の変数規約（Barendregt Variable Convention: すべての束縛変数がプログラム全体で一意）が保証されていなかったため、安全な式置換（Substitution）や移動（Code Motion）が制限されていた。
4. **セルフホスティング制約との両立**:
   - ULisp 自らをコンパイルするセルフホスティングコンパイラとして、可変長引数（dot/rest-arg lambda）の不使用、トップレベル `set!` の抑制（cons cell パターン）、およびポータブル Scheme（Gauche, ILisp/Python, ULisp AOT）で決定論的かつ高速に動作する要件を満たす必要があった。

---

## 2. ガバナンス・専門エージェント多角レビュー / Governance & Reviews

本 Issue は、16専門エージェントフレームワークに基づき、以下の重点専門領域からの設計レビューを統合して策定・実施された。

- **Project Manager (PM) (Chair / Governance)**:
  - 後続 Issue（Issue #606 include構文・ソース位置追跡、Issue #607 externシンボル解決、Issue #608 分割コンパイル）の前提となる強固なシンボル・スコープ解決基盤として本機能を最優先位置付け。
- **IT Specialist (Programming Languages & Compilers / PLC)**:
  - Barendregt Variable Convention を形式化し、脱糖直後（Pass 030 完了時）の Canonical Core AST (`L_core`) に対し完全な α 変換（$\alpha$-Conversion）を先行適用するパイプライン順序を設計。
  - レキシカル環境を静的木構造（Lexical Scope Contour Tree）としてモデル化し、スコープの開始・終了・親子関係・自由変数・局所束縛変数を正確に追跡。
- **Systems Architect**:
  - `ulisp/compiler/scope.scm` を `COMPILER_BASE`（Pass Manager, IR Verifier, Dataflow と同列）に配置し、Frontend（AST）の独立パス（Pass 035）として登録。
  - トップレベル大域定義（`define`, `define-values`, `define-record-type`）およびランタイム・プリミティブ組込みシンボルと、ローカル束縛変数（`lambda` 引数, `let`, `letrec`, `%cont-fun`）の境界を明確化。
- **Software Quality Assurance Specialist (SQA)**:
  - 多重ネストシャドウイング、同名変数の交差参照、letrec 相互再帰、内部定義展開後の変数解決、および未束縛変数の早期確定検出に関する単体テストスイート `ulisp/tests/test_scope.scm` を規定・全テスト通過を検証。
  - セマンティクス同値性（Alpha-Equivalence）検証を必須 DoD に設定。
- **Information Security Specialist**:
  - 変数名の衝突や意図しない捕捉による秘密情報の漏洩、未初期化変数参照（CWE-457）、および誤った置換による権限昇格・認証バイパス等の脆弱性を STRIDE/CWE 観点で評価・防止。

---

## 3. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/spec_pipeline.md)
  - [LIR 命令セット仕様書](../../ulisp/docs/spec_lir.md)
- **関連 Issue**:
  - Issue #588: [論理積構文 (and) の脱糖漏れによる LIR 未束縛変数例外の解消](588-fix-and-syntax-desugaring-unbound-variable-in-lir.md)
  - Issue #592: [手続き本体および内部定義の脱糖未実装による未束縛変数例外](592-implement-r7rs-internal-definition-desugaring.md)
  - Issue #594: [Frontend層: define-language L_anf / L_lifted の導入と不変条件自動検証](594-define-frontend-anf-and-lifted-languages.md)
  - Issue #598: [統一 Pass Manager の導入によるパイプライン制御・最適化レベルスケジューリング・観測性の一元化](598-implement-unified-compiler-pass-manager.md)
  - Issue #599: [汎用データフロー解析フレームワークの導入](599-implement-generic-dataflow-analysis-framework.md)
  - Issue #606: [ビルド時 cat 結合の廃止と R7RS include 構文によるソース位置追跡基盤の導入](../606-replace-cat-bundle-with-r7rs-include-and-source-tracking.md)
  - Issue #607: [外部シンボル（extern）参照解決と標準ライブラリ・コンパイラの2分割 .o 静的リンク基盤の導入](../607-support-extern-symbols-and-split-stdlib-compiler-linking.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/scope.scm](../../../ulisp/compiler/scope.scm) (新規: 字句スコープ木構築、未束縛変数静的検出、および α 変換エンジン)
- [x] [ulisp/compiler/pass_manager.scm](../../../ulisp/compiler/pass_manager.scm) (Pass 035: `pass-035-scope-resolve` の登録と依存関係解決)
- [x] [ulisp/Makefile](../../../ulisp/Makefile) (`COMPILER_BASE` への `compiler/scope.scm` 追加およびテストターゲット定義)
- [x] [ulisp/compiler.scm](../../../ulisp/compiler.scm) (Makefile 結合ターゲット自動再生成)
- [x] [ulisp/tests/test_pass_manager.scm](../../../ulisp/tests/test_pass_manager.scm) (Pass 035 登録確認テストの追加)
- [x] [ulisp/tests/test_scope.scm](../../../ulisp/tests/test_scope.scm) (新規: スコープ木・α 変換・シャドウイング・未束縛変数検出テスト)
- [x] [docs/issues/closed/600-implement-unified-lexical-scope-and-alpha-conversion-engine.md](600-implement-unified-lexical-scope-and-alpha-conversion-engine.md) (本設計書)
- [x] [docs/issues/README.md](../README.md) (Issue 管理台帳のステータス更新)

---

## 5. 脅威分析とセキュリティ要件 / Threat Modeling & Security Requirements

コンパイラフロントエンドにおけるシンボル解決および変数置換の不整合は、変数の誤捕捉による不正な値の注入、機密データのスコープ外流出、およびコンパイルクラッシュを引き起こす。STRIDE および CWE 観点での脅威分析を実施し、防護要件を策定した。

| 脅威分類 (STRIDE / CWE) | 脅威シナリオ | 影響度 | 対策要件 (Mitigation Requirements) |
| :--- | :--- | :---: | :--- |
| **なりすまし / 変数誤捕捉 (Spoofing / CWE-697)** | マクロ展開や最適化インライン展開で生成された変数が、既存のユーザー定義変数と同名衝突し、意図しない束縛を捕捉（Variable Capture）して変数の値が改ざんされる。 | High | Barendregt Variable Convention に従い、全ローカル束縛変数を一意なサフィックス付き識別子（`v$123`）へ α 変換。プログラム全体で同名変数が二度と重複しない不変条件を保証する。 |
| **未初期化変数参照 (CWE-457 / Unbound Variable)** | 脱糖漏れやスペルミス、スコープ外参照による未定義変数がフロントエンドを通過し、Pass 130（LIR 生成）まで検知されず、最終段階で突然例外終了または異常コード生成を招く。 | High | Pass 035（Scope Resolve）において、ローカルスコープ、トップレベル定義、およびランタイム・プリミティブの全記号表を照合し、未束縛変数をコンパイル初期段階で 100% 決定論的に検出し、明瞭なエラー診断を発出する。 |
| **サービス拒否 (DoS / CWE-400 / CWE-674)** | 循環参照や再帰的スコープ探索、巨大なシンボル辞書検索によるコンパイル時間爆発・スタックオーバーフロー。 | Medium | スコープ解決環境を軽量連想リスト（Alist）およびハッシュ/ツリー探索で効率化し、スタック深度を AST 深さ $O(D)$ に抑制。過度なシンボル文字列表列結合を抑止する。 |
| **型・表現不整合 (CWE-704)** | α 変換時にシンボル以外のトークン（リテラル定数、quote された識別子、キーワード）を誤ってリネームし、プログラムのセマンティクスを破壊する。 | Critical | AST の文脈（Binding position vs Reference position vs Literal quote position）を Nanopass/AST 走査時に厳格分離。`(quote x)` 内部のシンボルは絶対に α 変換の対象外とする。 |

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/600-implement-unified-lexical-scope-and-alpha-conversion-engine`

### 6.1 字句スコープ木（Scope Tree）データ構造の設計 (`ulisp/compiler/scope.scm`)
1. **Scope Node レコード**:
   ```scheme
   ;; スコープ種別: 'top-level | 'lambda | 'let | 'letrec | 'cont-fun
   (make-scope-node parent kind)
   (scope-node? obj)
   (scope-node-parent node)        ; 親スコープノード (top-level の場合は #f)
   (scope-node-kind node)          ; スコープ種別
   (scope-node-bindings node)      ; ((orig-sym . alpha-sym) ...)
   (scope-node-free-vars node)     ; 自由変数リストの参照ボックス
   (scope-node-children node)      ; 子スコープノードリスト
   ```
2. **スコープ操作 API**:
   - `(scope-enter parent kind)`: 子スコープノードを生成
   - `(scope-bind! node orig-sym alpha-sym)`: スコープに束縛を追加
   - `(scope-lookup-local node orig-sym)`: ローカルスコープ内の束縛を探索
   - `(scope-lookup node sym)`: 現在スコープから親スコープへ向かってシンボルを探索し、`alpha-sym` を返却（見つからなければ `#f`）
   - `(scope-record-free-var! node sym)`: スコープ境界を跨いで参照された自由変数を記録

### 6.2 決定論的 α 変換（Alpha-Conversion）エンジン
1. **一意識別子生成規則**:
   - ローカル束縛変数 `v` に対し、グローバル決定論的カウンタを用いて `v$N`（例: `x$0`, `x$1`, `loop$2`）を生成。
   - セルフホスティング対応: `string-append`, `number->string`, `string->symbol` によるポータブル実装。
2. **対象 AST 構文（L_core）**:
   - `(lambda (param ...) body)`: パラメータを新一意シンボルに置換し、新スコープで body を走査。
   - `(let ((var expr) ...) body)`: 各 `expr` は外側スコープで走査し、`var` を新一意シンボルに置換して body を新スコープで走査。
   - `(letrec ((var expr) ...) body)`: 全 `var` を先に新一意シンボルに置換した新スコープを作成し、各 `expr` および `body` をその新スコープで走査。
   - `(%cont-fun f-name (param ...) f-body in-body)`: 継続関数名およびパラメータを一意シンボルへ置換。
   - `(quote datum)`: 内部のシンボルはセマンティクスデータであるため **置換せずそのまま保持**。
   - 変数参照 `x`: 現在のスコープ木を検索し、ローカル束縛が見つかれば `alpha-sym` に置換。見つからなければ大域シンボル表および既知プリミティブ表と照合。

### 6.3 トップレベル環境との境界および未束縛変数の確定早期検出
1. **大域シンボル表の収集**:
   - `%program` 構造における全 `(define name ...)` を走査し、大域エクスポート/トップレベルシンボル集合を事前構築。
   - ランタイム組込み関数・プリミティブ（`ulisp/compiler/primitives.scm` の `pure-prim?`, `closure-prim?`, `binop-prim?` 等）を大域既知シンボルとして登録。
2. **静的スコープ検証 (`detect-unbound-variables`, `scope-check-unbound!`)**:
   - 参照されたシンボルがローカル束縛、トップレベル定義、既知プリミティブのいずれにも該当しない場合、未束縛変数として確定検出。

### 6.4 パイプライン統合と Pass Manager 登録
1. **Pass 035: `pass-035-scope-resolve`**:
   - `ulisp/compiler/pass_manager.scm` に登録。
   - 前提パス: `pass-030-desugar`
   - 入力言語: `L_core`
   - 出力言語: `L_core` (Alpha-Converted & Scope-Verified)
   - 必須フラグ: `#t` (全最適化レベル -O0, -O1, -O2 で常時実行)
2. **ビルド設定統合**:
   - `ulisp/Makefile` の `COMPILER_BASE` に `compiler/scope.scm` を追加。
   - `make compiler` による `ulisp/compiler.scm` への自動結合。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] 字句スコープ木および α 変換エンジン `ulisp/compiler/scope.scm` が新規実装され、`COMPILER_BASE` に統合されていること
- [x] `pass-035-scope-resolve` が `pass_manager.scm` に登録され、Pass 030 の直後に全最適化レベル（-O0, -O1, -O2）で自動実行されること
- [x] ネストした同名変数（シャドウイング）が、重複のない一意なシンボル（例: `x$0`, `x$1`）へ完全に α 変換されること
- [x] `(quote ...)` 構文内のシンボル定数が α 変換によって書き換えられず、リテラル同一性が保持されること
- [x] トップレベル大域定義名および既知プリミティブ名がローカル α 変換で破壊されないこと
- [x] スコープ外の未束縛変数が Pass 035 の段階で 100% 確定的に静的エラーとして検出されること
- [x] 単体テストスイート `ulisp/tests/test_scope.scm` が新規作成され、全37テストケースが PASS すること
- [x] 既存の全テストスイート（`test_scope`, `test_pass_manager`, `test_dataflow`, 全37個の Nanopass 単体テスト群 `test_passes` 147件）が 100% PASS すること
- [x] 相対パス規則およびリポジトリ品質ゲートが 100% 適合すること

---

## 8. 実装成果と品質検証結果 / Implementation Results & Quality Verification

### 8.1 実装成果物一覧
1. **字句スコープ解決 & α 変換エンジン (`ulisp/compiler/scope.scm`)**:
   - スコープノードレコード構造（`make-scope-node`, `scope-enter`, `scope-bind!`, `scope-lookup`, `scope-record-free-var!`）の実装
   - 決定論的一意シンボル生成ルーチン（`reset-alpha-symbol-counter!`, `make-alpha-symbol`）
   - 大域定義およびプリミティブ記号レジストリ（`scope-primitive-symbol?`, `collect-top-level-defines`）
   - Barendregt 変数規約正規化パス (`alpha-convert-expr`, `alpha-convert-program-node`, `scope-resolve-all`)
   - 静的未束縛変数検出 API (`detect-unbound-variables`, `scope-check-unbound!`)
2. **統一 Pass Manager 登録 (`ulisp/compiler/pass_manager.scm`)**:
   - `pass-035-scope-resolve` を必須（Mandatory / Opt-level 0）パスとして登録
   - 入出力言語制約 `L_core -> L_core`、前提パス `(pass-030-desugar)` を定義
3. **ビルド基盤統合 (`ulisp/Makefile`)**:
   - `COMPILER_BASE` に `compiler/scope.scm` を統合
   - `test_scope` ターゲットの新設および `test` ターゲットへの連動
4. **単体テストスイート (`ulisp/tests/test_scope.scm`)**:
   - スコープ木ノード階層・探索、シャドウイング解決、決定論的シンボル生成、ラムダ／let／letrec α 変換、quote リテラル不変性、%program 大域定義保持、未束縛変数確定検出、および Pass Manager パイプライン連携の全 37 アサーション網羅
5. **テスト追従更新 (`ulisp/tests/test_pass_manager.scm`)**:
   - Pass 035 のデフォルトパイプライン登録検証アサーションを追加

### 8.2 品質ゲート検証結果
- **`make -C ulisp test_scope`**: 37 / 37 PASS (100%)
- **`make -C ulisp test_pass_manager`**: 47 / 47 PASS (100%)
- **`make -C ulisp test_dataflow`**: 58 / 58 PASS (100%)
- **`make -C ulisp test_passes`**: 全 37 個の 1:1 Nanopass テストおよび全 147 単体テスト PASS (100%)
- **`make -C ulisp compiler.scm`**: 自動結合正常完了

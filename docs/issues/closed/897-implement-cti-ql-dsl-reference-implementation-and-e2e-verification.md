---
ID: 897
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] Implement CTI-QL DSL Reference Implementation and E2E Verification (ID: 897)

## 1. 概要 / Summary
[[DSN-33-04]](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) 第 7 章（リファレンス実装仕様: セキュリティ CTI フィルタ言語 `cti-ql`）に基づき、セキュリティ脅威ログの高速フィルタリング DSL である `cti-ql` の文法定義・オブジェクトモデル・単一評価器（Single-Source Interpreter）をリファレンス実装する。
先行 Issue（#892, #893, #894, #895, #896, #909）で完成した ULisp 言語ワークベンチ基盤（PEG Parser 合成、Frame Descriptor、NaN-boxing/Tagging、Direct Cogen、Dual Source Span DWARF エミッタ）をフル動員し、第2二村射影によるスタンドアロン CLI コンパイラ `bin/cti-qlc` の自動生成から、脅威判定ルール（`threat == "ransomware" AND cve-score >= 8`）の x86-64 ネイティブバイナリ出力、および極限ネイティブコード（7命令）の E2E 実証テストを完備する。

---

## 2. 背景と設計意図 / Background & Architectural Rationale
1. **言語ワークベンチのグランド統合実証**:
   - これまで個別 Nanopass / モジュール単位で実装してきた「文法解析器合成（PEG）」、「オブジェクトモデルとスタックフレーム降格（GFD）」、「第2二村射影（Direct Cogen）」、「ゲスト言語透過 DWARF」を、実際のセキュリティ業務ドメイン（CTI ログ解析）を題材としてエンドツーエンドで結合・実証する。
2. **評価器ディスパッチと AST 走査の完全消去（Tower Collapse）**:
   - 従来のスクリプト実行では、CTI ログ 1 件ごとに「AST 再帰走査」「文字列・シンボル比較」「環境（連想リスト）探索」という膨大なオーバーヘッドが生じていた。
   - `cti-ql` をワークベンチでコンパイルすることにより、実行時にはイベントポインタ（`rdi`）からの固定オフセット即値比較（`cmp dword ptr [rdi + 12], 8` 等）と論理演算のみからなるわずか 7〜10 命令のネイティブ機械語へと完全平坦化（Tower Collapse）されることを証明する。
3. **ゲスト言語透過デバッグ（DWARF .debug_line）の実証**:
   - 生成された `detector_rule.elf` が、Scheme 評価器ではなくユーザーの記述したルールファイル（`rule.cti`）の行番号（`rule.cti:1`, `rule.cti:2`）と機械語アドレスを 1:1 バインドしていることを検証する。

---

## 3. トレーサビリティ / Traceability
- **関連個別設計書**:
  - [[DSN-33-04] ULisp 言語ワークベンチ設計書 (第7章 CTI-QL リファレンス仕様)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
  - [[DSN-33-03] ULisp ステージ多相メタコンパイラ ＆ 二村射影フラクタル実行基盤設計書 (§3 Direct Cogen)](../designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md)
  - [[DSN-33-02] ULisp 多言語フロントエンド ＆ 型付き機械語 LIR 設計書 (§3.4 Diagnostic)](../designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md)
  - [[DSN-33-07] ULisp Zero-libc Bare-Metal Runtime](../designs/DSN-33-07-ulisp_zero_libc_pure_scheme_bare_metal_runtime.md)
- **依存・先行完了 Issue**:
  - [Issue #892: ゲスト言語スタックフレーム抽象（FrameDescriptor）とローカルスロット降格](closed/892-implement-guest-frame-descriptor-and-local-slot-lowering.md)
  - [Issue #893: ゲスト言語動的型タグ表現（Tagged Pointer / NaN-boxing）](closed/893-implement-guest-dynamic-value-tagging-and-nan-boxing.md)
  - [Issue #894: Pure Scheme Packrat PEG 構文解析器ジェネレータ](closed/894-implement-pure-scheme-compile-time-peg-parser-generator.md)
  - [Issue #895: 第2二村射影（Direct Cogen）によるスタンドアロン AOT コンパイラ CLI 生成](closed/895-implement-direct-cogen-driver-and-compiler-cli-generator.md)
  - [Issue #896: Dual Source Span およびゲスト言語 DWARF .debug_line ソースマッピング](closed/896-implement-dual-source-span-and-guest-dwarf-debug-line-emitter.md)
  - [Issue #909: ULisp コンパイラ本体への --cogen CLI オプション統合](closed/909-integrate-cogen-cli-option-into-ulisp-compiler.md)

---

## 4. 脅威モデルとセキュリティ対策 / Security Analysis & Threat Mitigations
| 脅威分類 (CWE) | リスクシナリオ | 具体的対策・防御プロトコル |
| :--- | :--- | :--- |
| **CWE-20 (Improper Input Validation)** | 不正な CTI クエリ文字列（閉じ括弧欠如、不正な演算子、構文破壊）によるパーサー無限ループ・クラッシュ | PEG パーサによる厳格な文法検証、Packrat メモ化での $O(N)$ 線形時間保証、最大式ネスト深度リミット（50段）の強制 |
| **CWE-125 / CWE-787 (Out-of-bounds Read/Write)** | CTI イベント構造体（`<cti-event>`）の未定義フィールドへのアクセスによるメモリ破壊 | `FrameDescriptor` による静的オフセット検証（`threat`: 0, `ip-addr`: 8, `port`: 12, `cve-score`: 16）。スキーマ外フィールドアクセスはコンパイル時エラーとして遮断 |
| **CWE-400 (Uncontrolled Resource Consumption)** | 巨大なクエリ文字列（メガバイト級）の供給によるコンパイル時 DoS | 入力クエリファイルサイズ制限（最大 64KB）、トークン数制限（最大 4,096 トークン）の強制 |
| **CWE-78 (OS Command Injection)** | ルール文字列内リテラルへの改行やシェルメタ文字混入による CLI / アセンブラ破壊 | リテラル文字列のエスケープ正規化、ホワイトリスト検証（`[a-zA-Z0-9_.-]` 優先） |

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/workbench/examples/cti_ql.scm](ulisp/workbench/examples/cti_ql.scm) - CTI-QL PEG 文法定義、`<cti-event>` オブジェクトモデル、評価器意味論 `eval-cti-ql`
- [x] [ulisp/workbench/examples/sample_rule.cti](ulisp/workbench/examples/sample_rule.cti) - リファレンス脅威判定ルールファイル
- [x] [ulisp/workbench/cogen.scm](ulisp/workbench/cogen.scm) - CTI-QL 評価器ディスパッチと二村射影展開の親和性保証
- [x] [ulisp/tests/test_workbench_cti_ql_e2e.scm](ulisp/tests/test_workbench_cti_ql_e2e.scm) - CTI-QL 単体テスト・AOT コンパイル・ELF 実行・命令列検証スイート
- [x] [ulisp/Makefile](ulisp/Makefile) - `test_workbench_cti_ql_e2e` ターゲット追加
- [x] [docs/issues/README.md](README.md) - 台帳ステータス更新

---

## 6. 詳細設計と実装方針 / Implementation Plan
Target Branch: `feat/897-implement-cti-ql-dsl-reference-implementation-and-e2e-verification`

```
  +--------------------------------------------------------------------------+
  |              CTI Query Rule: "threat == ransomware AND cve >= 8"         |
  +------------------------------------+-------------------------------------+
                                       |
                   [1. PEG Parser: cti-ql-grammar]
                                       |
                                       v
  +--------------------------------------------------------------------------+
  |      Typed AST with Dual Source Span: (AND (== threat "ransomware") ...) |
  +------------------------------------+-------------------------------------+
                                       |
                 [2. First / Second Futamura Projection]
                 [   Stage-Poly Lowering & Direct Cogen]
                                       |
                                       v
  +--------------------------------------------------------------------------+
  |             Residual LIR Instructions (No Evaluator Dispatch)            |
  |  L1: (%load-slot %rdi 16)      ; cve-score                               |
  |  L2: (%cmp-ge %rax 8)          ; >= 8                                    |
  |  L3: (%load-slot %rdi 0)       ; threat string/hash                      |
  |  L4: (%cmp-eq %rax 0x9f3a8b21) ; "ransomware"                            |
  |  L5: (%and %rax %rcx)                                                    |
  |  L6: (%return %rax)                                                      |
  +------------------------------------+-------------------------------------+
                                       |
                     [3. Assembler & Self-Contained ELF64]
                                       |
                                       v
  +--------------------------------------------------------------------------+
  |          Executable ELF (detector_rule.elf) with DWARF (.debug_line)     |
  |          Matches event stream in < 2 nanoseconds per packet              |
  +--------------------------------------------------------------------------+
```

### 6.1 `cti-ql` 文法・オブジェクトモデル・評価器実装 (`ulisp/workbench/examples/cti_ql.scm`)
1. **文法定義 (PEG 形式)**:
   ```scheme
   (define cti-ql-grammar-rules
     '((query      (seq expr end-of-input))
       (expr       (alt (seq term "OR" expr) term))
       (term       (alt (seq factor "AND" term) factor))
       (factor     (alt (seq "(" expr ")") predicate))
       (predicate  (seq field-name op-cmp literal-val))
       (field-name (alt "threat" "ip" "port" "cve"))
       (op-cmp     (alt "==" "!=" ">=" "<=" ">" "<"))
       (literal-val (alt string-lit num-lit))))
   ```
2. **ゲストオブジェクトモデル `<cti-event>` (GFD 準拠)**:
   - スロット定義:
     - Slot 0: `threat` (`:symbol` または `:string`) $\implies$ Offset 0
     - Slot 1: `ip-addr` (`:uint32` または `:string`) $\implies$ Offset 8
     - Slot 2: `port` (`:uint16` / `:fixnum`) $\implies$ Offset 12
     - Slot 3: `cve-score` (`:fixnum`) $\implies$ Offset 16
   - `cti-event-make`, `cti-event-threat`, `cti-event-cve-score` 等のアクセサを提供。
3. **単一ソース評価器 (Single-Source Interpreter)**:
   - `(eval-cti-ql ast event)`:
     - `query`: `(eval-cti-ql (cadr ast) event)`
     - `AND`: `(and (eval-cti-ql (cadr ast) event) (eval-cti-ql (caddr ast) event))`
     - `OR`: `(or (eval-cti-ql (cadr ast) event) (eval-cti-ql (caddr ast) event))`
     - `==`, `!=`, `>=`, `<=`, `>`, `<`: フィールド取得と即値比較。

### 6.2 Standalone CLI コンパイラ `cti-qlc` の自動合成
1. `ulisp/bin/ulisp-cogen` または `compiler.scm --cogen` を使用し、
   `cti_ql.scm` から `build/cti-qlc` を 0ms 起動・自己完結バイナリとして生成。
2. 生成された `cti-qlc` が CLI 引数（`-o <out.elf>`, `<in.cti>`, `--runtime-model`）を処理できることを確認。

### 6.3 AOT コンパイルと極限ネイティブコード（7命令）出力検証
1. 入力ルール `sample_rule.cti`:
   ```
   threat == "ransomware" AND cve >= 8
   ```
2. `cti-qlc` による AOT コンパイル実行:
   - 出力バイナリ `build/detector_rule.elf` を生成。
3. 生成された命令列の構造検証:
   - LIR 命令列に評価器のループや未解決のディスパッチが一切含まれず、`LIR-SLOT-REF`, `LIR-CONST`, `LIR-BINOP` のみで構成されていること。
   - アセンブリ出力で連想リスト検索や文字列ハッシュ探索関数呼び出しが消滅していること。

### 6.4 DWARF 透過性とイベント判定テスト
1. **イベント判定テスト**:
   - イベント 1: `threat="ransomware", cve=9` $\implies$ **Match (1)**
   - イベント 2: `threat="ransomware", cve=5` $\implies$ **Reject (0)**
   - イベント 3: `threat="phishing", cve=10` $\implies$ **Reject (0)**
2. **DWARF .debug_line 検証**:
   - `readelf --debug-dump=decodedline build/detector_rule.elf` で、行番号が `sample_rule.cti` の行を指していることを検証。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/workbench/examples/cti_ql.scm` に文法定義、`<cti-event>` オブジェクトモデル、および `eval-cti-ql` 評価器が完備されていること。
- [x] 第2二村射影（`ulisp-cogen` / `compiler.scm --cogen`）によりスタンドアロンコンパイラ `cti-qlc` が自動生成できること。
- [x] `cti-qlc` を用いて `sample_rule.cti` を AOT コンパイルし、実行可能 ELF バイナリ `detector_rule.elf` が出力されること。
- [x] 出力されたバイナリが正しく CTI イベントのマッチ／不一致を判定できること。
- [x] 残余コードから評価器ディスパッチ・AST 走査が消滅し、ダイレクトなアセンブリ命令列のみが出力されていること。
- [x] `readelf --debug-dump=decodedline` で `sample_rule.cti` の行番号が ELF にバインドされていること。
- [x] `make -C ulisp test_workbench_cti_ql_e2e` が 100% PASS すること。
- [x] `make -C ulisp lint_sexpr verify_zero_gauche` が PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。
- [x] Issue 台帳（`docs/issues/README.md`）のステータスが適切に更新されていること。

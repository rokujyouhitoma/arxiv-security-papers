---
ID: 896
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-11-21
---

# [FEAT/ENH] Implement Dual Source Span and Guest DWARF Debug Line Emitter (ID: 896)

## 1. 概要 / Summary
[[DSN-33-04]](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) 第 5 章（ゲスト言語レベルのデバッグ透過性）に基づき、評価器実装のソース位置（Interp Span）とユーザースクリプトのソース位置（Guest Span）を二重管理する **Dual Source Span（`<dual-source-span>`）** を導入する。
生成される ELF バイナリの DWARF `.debug_line` セクションにユーザースクリプトのファイル名・行番号を自動バインドし、GDB/LLDB による透過的ステップ実行・ブレークポイント設定を可能にする。

---

## 2. 背景と課題 / Background & Motivation
1. **メタコンパイラにおけるデバッグ情報の断絶**:
   - 部分評価や Direct Cogen（二村射影）によって生成された AOT コンパイラや残余コードを実行する際、クラッシュや例外が発生すると、GDB 等のデバッガは Scheme 評価器（`interp.scm`）の位置を表示してしまう。
   - ユーザーが記述した DSL スクリプト（例: `rule.cti` や `calc.expr`）のどこでエラーが発生したかを特定できず、言語ワークベンチとしてのユーザビリティが著しく損なわれる。
2. **LIR におけるソーススパンの欠落**:
   - 現在の `ulisp/lir/130_lir.scm` では、Pass 6 開始時に `(ast-strip-span-all prog-raw)` を呼び出しており、関数先頭以外の中間式に対する `%loc` 命令が生成されない。
3. **自前 ELF64 DWARF 生成基盤の活用**:
   - ULisp は既に `elf64_builder.scm` および `144a_x86_assembler.scm` に外部 C コンパイラ非依存の自前 DWARF `.debug_line` 生成器（DWARF 3 仕様）を備えている。
   - LIR レベルで Dual Source Span を解釈し、`guest-file` と `guest-line` を優先して `%loc` を発行することで、Zero-libc かつ外部ツール不要でゲスト言語透過の DWARF バイナリを出力できる。

---

## 3. トレーサビリティ / Traceability
- **関連設計書**:
  - [[DSN-33-04] ULisp 言語ワークベンチ設計書 (第5章 ゲスト言語レベルのデバッグ透過性)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
  - [[DSN-33-03] ULisp ステージ多相メタコンパイラ設計書 (§4.3 Dual-Span 診断レポーター)](../designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md)
  - [[DSN-33-02] ULisp 多言語フロントエンド ＆ 型付き機械語 LIR 設計書](../designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md)
  - [[DSN-33-07] ULisp Zero-libc Bare-Metal Runtime](../designs/DSN-33-07-ulisp_zero_libc_pure_scheme_bare_metal_runtime.md)
- **先行クローズ済み Issue**:
  - [Issue #876: CSP 越境バリデータと Dual Span 診断レポーターの実装](closed/876-implement-csp-boundary-validator-and-dual-span-diagnostics.md)
  - [Issue #894: Pure Scheme Packrat PEG 構文解析器ジェネレータの実装](closed/894-implement-pure-scheme-compile-time-peg-parser-generator.md)
  - [Issue #895: Direct Cogen によるスタンドアロン AOT コンパイラ CLI 生成ドライバの実装](closed/895-implement-direct-cogen-driver-and-compiler-cli-generator.md)
  - [Issue #909: ULisp コンパイラ本体への --cogen CLI オプション統合](closed/909-integrate-cogen-cli-option-into-ulisp-compiler.md)

---

## 4. 脅威モデルとセキュリティ対策 / Security Analysis & Threat Mitigations
| 脅威分類 (CWE) | リスクシナリオ | 具体的対策・防御プロトコル |
| :--- | :--- | :--- |
| **CWE-22 (Path Traversal)** | ゲストスクリプトパスに `../../etc/shadow` や `../` を含む悪意ある文字列が渡され、DWARF `.file` テーブルに不正な相対パスが埋め込まれる | `sanitize-source-path` によるディレクトリトラバーサル無効化。`..` や絶対パス、不可視制御文字（`\0`, `\r`, `\n`）の完全正規化を強制 |
| **CWE-400 (Resource Exhaustion)** | 巨大な行番号（例: $2^{31}-1$）や不正な列番号による DWARF SLEB128/ULEB128 エンコーダの無限ループまたはバッファ肥大化 | 行番号の安全域クリッピング（$1 \le \text{line} \le 10,000,000$）。同一 PC・同一行の冗長 `%loc` 命令の圧縮・抑制フィルタ（LIR Peephole）の導入 |
| **CWE-78 (OS Command Injection)** | DWARF コメントやアセンブリ出力時にファイル名に `"` や改行コードが混入し、GNU as / シェル解釈を狂わせる | ファイル名内の二重引用符・改行・制御文字の徹底サニタイズ（ホワイトリスト文字セット正規化） |

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/helpers.scm](ulisp/compiler/helpers.scm) - `<dual-source-span>` レコード定義、述語、アクセサ、`source-span` 透過抽出ヘルパー
- [x] [ulisp/compiler/diagnostic.scm](ulisp/compiler/diagnostic.scm) - Dual Source Span に対応したエラー診断・表示フォーマットの強化
- [x] [ulisp/lir/130_lir.scm](ulisp/lir/130_lir.scm) - 式単位の Span 保持、きめ細かい `%loc` 命令発行、冗長 `%loc` 抑止
- [x] [ulisp/lir/133_lir_peephole.scm](ulisp/lir/133_lir_peephole.scm) - 連続する同一 `%loc` 命令の最適化・圧縮
- [x] [ulisp/backend/140_backend_x86_64.scm](ulisp/backend/140_backend_x86_64.scm) - `%loc` 命令から `.loc <fid> <line> <col>` への確実な変換
- [x] [ulisp/backend/144a_x86_assembler.scm](ulisp/backend/144a_x86_assembler.scm) - `.file` および `.loc` のパース、`file-table` / `line-table` の構築保証
- [x] [ulisp/backend/elf64_builder.scm](ulisp/backend/elf64_builder.scm) - DWARF 3 `.debug_line` のステートマシン構築とゲスト言語ファイルテーブル出力
- [x] [ulisp/workbench/cogen.scm](ulisp/workbench/cogen.scm) - CLI 生成時に文法・スクリプトの位置情報を Dual Source Span としてアタッチするプロトコル
- [x] [ulisp/tests/test_workbench_dwarf.scm](ulisp/tests/test_workbench_dwarf.scm) - Dual Source Span および DWARF `.debug_line` の E2E 検証スイート
- [x] [ulisp/Makefile](ulisp/Makefile) - `test_workbench_dwarf` ターゲット追加
- [x] [docs/issues/README.md](README.md) - 台帳ステータス更新

---

## 6. 詳細設計と実装方針 / Implementation Plan
Target Branch: `feat/896-implement-dual-source-span-and-guest-dwarf-debug-line-emitter`

```
  +-------------------------------------------------------------------+
  |                      Guest Script (e.g. rule.cti)                 |
  |                      Line 42: "threat == ransomware"              |
  +---------------------------------+---------------------------------+
                                    | PEG Parser / Ast Annotator
                                    v
  +-------------------------------------------------------------------+
  |                    <dual-source-span> Record                      |
  |  guest-file:  "rule.cti"      guest-line:  42   guest-col:  1     |
  |  interp-file: "interp.scm"   interp-line: 120  interp-col: 4     |
  +---------------------------------+---------------------------------+
                                    |
                                    | (Priority: Guest Span > Interp Span)
                                    v
  +-------------------------------------------------------------------+
  |                      LIR Instruction Stream                       |
  |  (%loc <fid:rule.cti> 42 1)                                       |
  |  (%cmp-eq %rax %rcx)                                              |
  +---------------------------------+---------------------------------+
                                    | Assembler / ELF Builder
                                    v
  +-------------------------------------------------------------------+
  |                ELF64 DWARF 3 (.debug_line Section)                |
  |  File Table: [1 -> "rule.cti", 2 -> "interp.scm"]                 |
  |  Line Table: PC 0x4010a0 -> File 1, Line 42                       |
  +-------------------------------------------------------------------+
```

### 6.1 `<dual-source-span>` レコードおよび透過ヘルパー (`ulisp/compiler/helpers.scm`)
1. **レコード定義 (DSN-33-04 §5.1)**:
   ```scheme
   (define-record-type <dual-source-span>
     (%make-dual-source-span-raw guest-file guest-line guest-col
                                 interp-file interp-line interp-col
                                 node-id)
     dual-source-span?
     (guest-file   span-guest-file)
     (guest-line   span-guest-line)
     (guest-col    span-guest-col)
     (interp-file  span-interp-file)
     (interp-line  span-interp-line)
     (interp-col   span-interp-col)
     (node-id      span-dual-node-id))
   ```
2. **構築関数とサニタイズ**:
   - `(make-dual-source-span guest-file g-line g-col interp-file i-line i-col [node-id])`
   - `sanitize-source-path` を `guest-file` と `interp-file` に適用。
   - 行番号・列番号は正の整数に正規化。
3. **ポリモーフィック・アクセサ**:
   - `(span-effective-file span)`: `dual-source-span` の場合は `guest-file`（存在しない場合 `interp-file`）、`source-span` の場合は `span-file` を返却。
   - `(span-effective-line span)`: `dual-source-span` の場合は `guest-line`（存在しない場合 `interp-line`）、`source-span` の場合は `span-start-line` を返却。
   - `(span-effective-col span)`: `dual-source-span` の場合は `guest-col`、`source-span` の場合は `span-start-col` を返却。
   - `(span-effective-interp-file span)` / `(span-effective-interp-line span)`: 評価器側の位置情報を取得。
4. **AST ラッパーとの協調**:
   - `ast-source-span` が `<dual-source-span>` をそのまま透過的に返却できるように拡張。

### 6.2 LIR でのきめ細かい `%loc` 生成と最適化 (`ulisp/lir/130_lir.scm`, `133_lir_peephole.scm`)
1. **スパン付き式の LIR コンパイル**:
   - `(ast-has-span? expr)` を検出した場合、そのスパンから `(span-effective-file span)` と `(span-effective-line span)` を取得。
   - `debug-symbols-enabled?` が真の場合、登録済み `fid` を取得して `(%loc fid line col)` を LIR 命令列へアペンド。
   - `ast-strip-span-all` で一括除去するのではなく、`lir-compile-expr` の再帰過程でスパンを消費しながら式を評価。
2. **冗長 `%loc` の圧縮 (Peephole Optimizer)**:
   - 同一の `(fid, line)` を持つ連続する `%loc` 命令を 1 つに畳み込む（コードサイズ削減と DWARF 行テーブルのコンパクト化）。

### 6.3 DWARF `.debug_line` エミッタとアセンブラの連動 (`ulisp/backend/`)
1. **アセンブラ (`144a_x86_assembler.scm`)**:
   - `.file <fid> "<path>"` で登録されたパスを `file-table` に保存（パスの重複排除と ID 一致の保証）。
   - `.loc <fid> <line> <col>` を受け取った時点の `text-len`（バイトオフセット）を `line-table` エントリ `(fid line col offset)` として記録。
2. **ELF64 ビルダー (`elf64_builder.scm`)**:
   - `build-debug-line-section` において、`file-table` の順序を正しく保持し、ゲスト言語ファイル名を先頭または指定 ID に正しくマッピング。
   - `prog-bytes` のステートマシンで、行番号差分（`line-delta`）とアドレス差分（`pc-delta`）が正確にエンコードされることを確認。

### 6.4 診断レポーター（Pretty Diagnostic）との統合 (`ulisp/compiler/diagnostic.scm`)
- コンパイル時エラー発生時、`span` が `dual-source-span?` の場合：
  ```
  error[G001]: syntax error in guest script
    --> rule.cti:42:10
     |
  42 | threat == ransomware
     |           ^^^^^^^^^^ invalid identifier
     = note: evaluator context: eval_cti_ql at interp.scm:120:5
  ```
  のように、ゲストスクリプトの位置をプライマリに、インタプリタの Scheme 実装位置をセカンダリ（note）として表示。

### 6.5 包括的テストスイート (`ulisp/tests/test_workbench_dwarf.scm`)
1. **Unit Tests**:
   - `<dual-source-span>` の生成、アクセサ、サニタイズ（CWE-22/CWE-400 防御）。
   - `span-effective-file` / `line` の優先順位検証。
2. **LIR & Assembler Tests**:
   - Dual Source Span を持つ AST から LIR 命令列へ `(%loc fid line col)` が正しく発行されること。
   - アセンブラによって `file-table` および `line-table` に登録されること。
3. **E2E DWARF Binary Tests**:
   - ゲストスクリプト（例: `sample_rule.cti`）を模した入力からスタンドアロン ELF バイナリをビルド。
   - バイナリの `.debug_line` セクションをパース（または `readelf --debug-dump=decodedline`）し、`sample_rule.cti` の行番号が機械語アドレスとバインドされていることを検証。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `<dual-source-span>` レコードおよびポリモーフィックアクセサ（`span-effective-*`）が実装され、`source-span?` との完全な後方互換性が保たれていること。
- [x] パストラバーサル（CWE-22）および巨大数値（CWE-400）の境界サニタイズが 100% 適用されていること。
- [x] LIR 生成フェーズでゲスト言語の行番号・ファイル ID を持つ `%loc` 命令が生成され、LIR Peephole で冗長命令が圧縮されること。
- [x] 自前 ELF64 ビルダーが DWARF 3 `.debug_line` にゲストスクリプトのファイル名（例: `rule.cti`）と行番号を正確に出力できること。
- [x] 単体・E2E テスト `ulisp/tests/test_workbench_dwarf.scm` が作成され、`make -C ulisp test_workbench_dwarf` が 100% PASS すること。
- [x] `make -C ulisp lint_sexpr verify_zero_gauche` が PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。
- [x] Issue 台帳（`docs/issues/README.md`）のステータスが適切に更新されていること。

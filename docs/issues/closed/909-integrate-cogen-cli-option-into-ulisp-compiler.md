---
ID: 909
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] Integrate --cogen Option into ULisp Compiler CLI and Unify Driver Subcommands (ID: 909)

## 1. 概要 / Summary
[[DSN-33-04]](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) §4.2（`ulisp-cogen` ドライバ：インタプリタ定義から単一バイナリ CLI の出力）および [[Issue #895]](closed/895-implement-direct-cogen-driver-and-compiler-cli-generator.md) に基づき、独立スクリプトとして実装された第2二村射影（Direct Cogen）生成機能を **ULisp コンパイラ本体（`ulisp/compiler.scm` および `ulisp-boot` / `ulisp-modular`）のネイティブ CLI オプション `--cogen` として統合** する。

これにより、ULisp コンパイラ単一バイナリが通常の Scheme プログラムの AOT コンパイル（第1二村射影）と、言語ワークベンチにおける評価器・文法からの専用コンパイラ CLI 合成（第2二村射影）の両方をワンコマンドで直接駆動可能にする。また、`ulisp/bin/ulisp-cogen` は `compiler.scm --cogen` を呼び出す薄いシンボリックリンクまたはエイリアスコマンド（Git における `git commit` と `git-commit` の関係）として統合し、単一インターフェース化（Single Binary Interface）を確立する。

---

## 2. トレーサビリティ / Traceability
- **上位・関連設計書**:
  - [[DSN-33-04] ULisp 言語ワークベンチ・インタプリタ自動生成 ＆ ゲスト言語ランタイムアーキテクチャ設計書 (第4章 第2二村射影によるスタンドアロン CLI コンパイラ自動生成)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
  - [[DSN-33-03] ULisp ステージ多相メタコンパイラ ＆ 二村射影フラクタル実行基盤設計書](../designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md)
  - [[DSN-33] ULISP 包括設計仕様書: S式メタコンパイラ基盤](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **依存・先行 Issue**:
  - [[Issue #895] Implement Direct Cogen Driver and Compiler CLI Generator](closed/895-implement-direct-cogen-driver-and-compiler-cli-generator.md) (**完了済み**: Direct Cogen コアエンジン `ulisp/workbench/cogen.scm`)
  - [[Issue #894] Implement Pure Scheme Compile-Time PEG Parser Generator in ulisp/peg/](closed/894-implement-pure-scheme-compile-time-peg-parser-generator.md) (**完了済み**: Pure Scheme PEG パーサー)
  - [[Issue #892] Implement Guest Frame Descriptor & Local Slot Lowering](closed/892-implement-guest-frame-descriptor-and-local-slot-lowering.md) (**完了済み**: スタックフレーム・局所スロット抽象)
  - [[Issue #893] Implement Guest Dynamic Value Tagging & NaN-boxing](closed/893-implement-guest-dynamic-value-tagging-and-nan-boxing.md) (**完了済み**: 動的型オブジェクトモデル)
- **後続 Issue**:
  - [[Issue #896] Implement Dual Source Span and Guest DWARF .debug_line Emitter](896-implement-dual-source-span-and-guest-dwarf-debug-line-emitter.md)
  - [[Issue #897] Implement cti-ql DSL Reference Implementation and E2E Verification](897-implement-cti-ql-dsl-reference-implementation-and-e2e-verification.md)

---

## 3. コア要件と設計アーキテクチャ

### 3.1 CLI インターフェース統合
`ulisp/compiler.scm` のコマンドライン引数ループに以下のオプションを追加する：

```bash
# 1. compiler.scm 経由の直接呼び出し
./bin/ulisp-boot compiler.scm --cogen \
    --interpreter=<interp.scm> \
    --grammar=<grammar.peg> \
    -o <bin/my-langc> \
    [--runtime-model=<tagging|nanbox>] \
    [--entry-rule=<rule>]

# 2. 糖衣ショートカット CLI 経由の呼び出し
./bin/ulisp-cogen \
    --interpreter=<interp.scm> \
    --grammar=<grammar.peg> \
    --output=<bin/my-langc> \
    [--runtime-model=<tagging|nanbox>]
```

### 3.2 実行制御フロー
1. `compiler.scm` が `--cogen` フラグを検知した場合、通常の Scheme ソース入力（標準入力またはファイル）読み込みバイパスを行い、`cogen-main` ルーチンへ遷移。
2. `--interpreter` と `--grammar` の引数パスを検証（CWE-78 / CWE-22 防護）。
3. `workbench/cogen.scm` の `synthesize-compiler-cli-source` を呼び出してスタンドアロン CLI ソースを内部生成。
4. `-o` / `--output` で指定された出力ファイルへ書き込み、実行権限（`0755`）を付与して終了。

---

## 4. セキュリティ脅威分析と防御策 (Security Threat Mitigations)
1. **CWE-78: OS Command Injection**:
   - `compiler.scm` 内部でもシェル起動（`system`, `popen`）を一切行わず、プロセス内部の Scheme 手続きのみでファイル入出力・パーサー合成を実行（Zero Shell Invocation）。
   - パス引数に対するホワイトリスト文字検査（`cogen-validate-path`）。
2. **CWE-22: Path Traversal**:
   - 出力先パスの多重 `..` によるワークスペース脱出を `cogen-validate-output-path` により厳格に遮断。
3. **CWE-400: Resource Exhaustion**:
   - 不正な文法や再帰マクロ展開に対する深さ制限（`*cogen-max-recursion-depth*`）を適用。

---

## 5. 影響範囲
- `ulisp/compiler.scm`: `--cogen`, `--interpreter=...`, `--grammar=...`, `--runtime-model=...` オプション追加。
- `ulisp/bin/ulisp-cogen`: `compiler.scm` と共通の cogen エンジンを使用するインターフェース統一。
- `ulisp/tests/test_workbench_cogen.scm`: `compiler.scm --cogen` の E2E テストを追加。
- `ulisp/Makefile`: `test_workbench_cogen` ターゲットで `compiler.scm --cogen` の動作を検証。

---

## 6. 完了条件 / Definition of Done (DoD)
- [x] `ulisp/compiler.scm` に `--cogen` オプションが追加され、`--interpreter`, `--grammar`, `-o` を用いてスタンドアロンコンパイラ CLI を合成・出力できること。
- [x] `ulisp/bin/ulisp-cogen` と `compiler.scm --cogen` の両方で同一の Cogen 生成結果が得られること。
- [x] 不正なパス（CWE-78, CWE-22）が `--cogen` 実行時にも正しく遮断されること。
- [x] 生成された CLI を用いてプログラムが正常にコンパイルできること（E2E 検証）。
- [x] `make -C ulisp test_workbench_cogen` が 100% PASS すること。
- [x] `make -C ulisp lint_sexpr verify_zero_gauche` がエラー 0 件で PASS すること。
- [x] `make py_compile && make static_analysis` がエラー 0 件で PASS すること。
- [x] すべてのファイル参照において相対パス規則が厳格に守られていること。

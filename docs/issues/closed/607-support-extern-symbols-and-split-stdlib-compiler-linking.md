---
ID: 607
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] 外部シンボル（extern）参照解決と標準ライブラリ・コンパイラの2分割 .o 静的リンク基盤の導入 (ID: 607)

## 1. 概要 / Summary

現在、ULisp コンパイラ（`110_closure_convert.scm` および `130_lir.scm`）は、ローカル環境 `env`、大域関数リスト `*top-level-fns*`、および大域変数リスト `*top-level-vars*` のいずれにも存在しないシンボルに遭遇した場合、即座に未束縛変数例外（`Unbound variable in LIR: <var>`）を発生させてコンパイルを中断する。このため、別ファイルで定義された関数やグローバル変数を参照するコードを単体で独立コンパイルすることが原理的に不可能であり、すべてのソースファイル（約 25,000 行）を 1 つのエントリーファイル（`entry_core.scm` / `ulisp_core.scm`）に同居させる「モノリシック・単一翻訳単位（Single Translation Unit）」でのコンパイルを強制されていた。

### 現行アーキテクチャの課題と障害要因:
1. **コンパイル・ビルドサイクルの長大化**:
   - コンパイラ内部の Nanopass を 1 行修正しただけでも、巨大な標準ライブラリ群（`lib/*.scm`）およびランタイムサブシステム（`runtime/*.scm`）を毎回最初から再解析・再コンパイルする必要があり、開発フィードバックループが著しく低下している。
2. **独立した ELF オブジェクト生成の欠落**:
   - ネイティブバックエンド（`140_backend_x86_64.scm`）は、常に出力アセンブリの末尾に `_start`、`scheme_entry`、フリースタンディングゼロ libc ランタイムルーチン（`ulisp_print_value` 等）、GC コレクタ、およびメタデータテーブル（`__ulisp_symbol_table` 等）を強シンボルとして埋め込むため、2 つの `.o` を `ld` または `gcc -nostdlib` でリンクしようとすると即座にシンボル多重定義エラー（`multiple definition of ...`）が発生する。
3. **トップレベル関数ラベルの非決定論性**:
   - `110_closure_convert.scm` においてトップレベル関数に割り当てられるアセンブリラベルが `(unique-label-sym "L_top_...")` で生成されており、ファイル先頭からの連番カウンタ（例: `.L_top_map_42`）や先頭ドット（ローカルラベル）が付加されているため、外部オブジェクトからシンボル名で直接呼び出すことができない。

### 本 Issue における解決策:
本 Issue では、LIR およびネイティブバックエンドにおいて、未束縛のグローバル関数・変数を外部シンボル参照（`extern`）として許容し、アセンブリレベルで `.globl` へのシンボル参照（`call ulisp_fn_<name>` / `[rip + ulisp_gvar_<name>]` 等）を出力してネイティブリンカ（`gcc -nostdlib` または `ld`）にアドレス解決を委ねる仕組みを導入する。
具体的には：
1. **決定論的シンボルマングリング規約の確立**:
   トップレベル関数および外部参照シンボルに対し、ドットやランダムカウンタを排除した決定論的グローバルラベル（関数: `ulisp_fn_<sanitized>`, 変数: `ulisp_gvar_<sanitized>`）を適用。
2. **未束縛シンボルの Extern 解決フォールバック**:
   `--allow-extern` または分割コンパイルモード時、スコープ内に見つからない識別子を即時エラーとせず、外部グローバル参照（`%global-ref` / `%extern-call`）として LIR を生成。
3. **バックエンドの多重定義防止（.weak 属性およびモジュールモード）**:
   共有ランタイムルーチンやメタデータテーブルに `.weak` 属性を付与するか、モジュール出力モード（`--module`）において重複コードの出力を抑制。
4. **ライブラリ初期化プロトコル（`ulisp_stdlib_init`）の策定**:
   `ulisp_stdlib.o` のトップレベル変数初期化式を `ulisp_stdlib_init` として公開し、`ulisp_compiler.o` のエントリーポイント実行前に呼び出す連鎖初期化を確立。
5. **標準ライブラリ（`ulisp_stdlib.o`）とコンパイラ（`ulisp_compiler.o`）の 2 分割リンクパイプラインの構築**:
   `Makefile` に 2 分割コンパイルターゲットを整備し、静的リンクによる単一バイナリ生成と 3-stage ブートストラップ固定点検証を達成する。

---

## 2. ガバナンス・専門エージェント多角レビュー / Governance & Reviews

本 Issue は、リポジトリ規約（`.agents/AGENTS.md`）に従い、16 専門エージェントによる設計レビューを統合して策定された。

- **Project Manager (PM) (Chair / Governance)**:
  - モノリシック単一翻訳単位から 2 分割リンク（stdlib + compiler）への移行は、開発効率を抜本的に改善し、後続の Issue #608（Nanopass・モジュール単位の完全分割コンパイル・増分ビルド）へと繋がる極めて重要なマイルストーンである。品質ゲートを徹底遵守し、後退（Regression）ゼロで完遂させる。
- **IT Specialist (Programming Languages & Compilers / PLC)**:
  - ULisp における直接関数呼び出し（`%direct-call`）とクロージャ呼び出し（`%call-closure`）の呼び出し規約（ABI）は、スタック上の引数配置および `rax = num_args * 4` を完全に共有している。外部シンボルへの直接呼び出しは、`r10 = 0` をセットした上で `call ulisp_fn_<name>` を発行するだけで、同一ファイル内の直接呼び出しと同一のセマンティクスで透過的に解決できる。
  - 一方で、一級値として渡される関数やグローバル変数の参照は `[rip + ulisp_gvar_<name>]` を介して間接アクセスさせ、関数と変数の dual-representation を担保する。
- **Systems Architect**:
  - 静的リンク時の ELF 再配置（`R_X86_64_PLT32` / `R_X86_64_PC32`）および弱シンボル（`.weak`）の挙動を厳密にモデル化。
  - ライブラリ初期化の順序問題（Static Initialization Order Fiasco）を防止するため、`ulisp_compiler.o` の `scheme_entry` 開始直後に `call ulisp_stdlib_init` を確定的に挿入する初期化パイプラインを策定。
- **Information Security Specialist**:
  - 外部シンボル解決の導入に伴い、意図しないシンボルの衝突・ハイジャック（CWE-426 / CWE-427）や未初期化メモリ参照（CWE-457）を STRIDE 脅威モデルで評価。明示的なコンパイルオプション（`--allow-extern`）によるガードと厳格なシンボルサニタイズを要求。
- **Software Quality Assurance Specialist (SQA)**:
  - 外部シンボルを含む単体テスト（`tests/passes/test_extern_symbols.scm`）を新設。
  - 2 分割リンクによって生成されたバイナリが、既存の全 37 単体テスト、JIT テスト、およびスモークテストに 100% 合格し、ビット一致（Bit-for-bit identical）のブートストラップ固定点収束を達成することを検証。
- **Software Development (SWD)**:
  - `compiler/helpers.scm` に `mangle-fn-label` を新設し、`110_closure_convert.scm`、`130_lir.scm`、`140_backend_x86_64.scm` におけるラベル生成を決定論化。
  - `Makefile` に `build/ulisp_stdlib.o`、`build/ulisp_compiler.o`、および `build/ulisp-fast` のビルドルールを追加。
- **Application Specialist (APS)**:
  - 開発者が `ulisp` CLI を使用する際、未束縛変数のエラー表示（Issue 602 / 603 診断機構）を損なうことなく、分割コンパイル時にのみ柔軟に外部参照を解決できる CLI インターフェース（`--allow-extern` / `--module`）を設計。
- **Systems Auditor**:
  - 分割リンク導入前後で AST 変換ルールおよびランタイム不変条件が完全に維持され、トレーサビリティが担保されていることを検証。

---

## 3. セキュリティ設計・脅威分析 / Security Considerations & Threat Modeling

本機能は新しいシンボル解決パスおよびオブジェクトリンク機構を導入するため、STRIDE および CWE 観点でセキュリティリスクを分析し、防護策を講じる。

| 脅威分類 (STRIDE) | 脆弱性識別子 (CWE) | 潜在的リスク / 攻撃シナリオ | 適用する防護措置・緩和策 |
| :--- | :--- | :--- | :--- |
| **Tampering** (改ざん) / **Elevation of Privilege** | **CWE-426**: Untrusted Search Path<br>**CWE-427**: Uncontrolled Search Path Element | 悪意のあるサードパーティオブジェクトが `ulisp_fn_*` や `ulisp_gvar_*` と同名のシンボルをエクスポートし、標準ライブラリの重要関数をハイジャックして乗っ取る。 | 1. リンク対象オブジェクトをプロジェクト管理下の `build/` ディレクトリ内に限定。<br>2. 外部シンボル解決をデフォルトで無条件開放せず、明示的フラグ（`--allow-extern`）または正規の分割ビルドターゲット配下でのみ有効化。 |
| **Spoofing** (なりすまし) | **CWE-682**: Incorrect Calculation<br>**CWE-684**: Incorrect Provision of Specified Functionality | Scheme 識別子に含まれる特殊文字（`-`, `?`, `!`, `*` 等）のサニタイズ処理が不完全な場合、異なる Scheme シンボルが同一の ELF シンボル名にマッピングされ、関数呼び出しが取り違えられる。 | 既存の `sanitize-label-str` を厳格化し、文字種の衝突を防止する一方向置換マッピングおよびプレフィックス分離（関数: `ulisp_fn_`, 変数: `ulisp_gvar_`）を徹底。 |
| **Denial of Service** (サービス妨害) | **CWE-457**: Use of Uninitialized Variable<br>**CWE-476**: NULL Pointer Dereference | `ulisp_compiler.o` が `ulisp_stdlib.o` 内の大域変数（`*stdin-port*` 等）にアクセスした際、ライブラリ初期化前に参照して未初期化ポインタ（0）を参照し SIGSEGV クラッシュを引き起こす。 | `ulisp_compiler.o` の `scheme_entry` 開始時に、何よりも先に `call ulisp_stdlib_init` を実行する決定論的初期化シーケンスをコード生成レベルで強制。 |
| **Integrity Violation** (完全性侵害) | **CWE-703**: Improper Check or Handling of Exceptional Conditions | ソースコード中の単純なスペルミス（未束縛変数）が、コンパイル時に検知されずすべて `extern` にフォールバックしてリンク時までエラーが遅延する。 | 単一翻訳単位モード（デフォルト）では既存の `Unbound variable in LIR` 例外と Issue 602/603 診断ダンプを 100% 維持。`--allow-extern` が明示された場合のみフォールバックを許可。 |

---

## 4. トレーサビリティ / Traceability

- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (Section 3: パイプライン設計 & Section 7: リンカ・ABI 規約)
  - [LIR 命令セット仕様書](../../ulisp/docs/spec_lir.md)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/spec_pipeline.md)
- **関連 Issue**:
  - [Issue 502: 低レベルIR (LIR) の導入とバックエンド分離](closed/502-introduce-low-level-ir-lir.md)
  - [Issue 516: 100% Pure Scheme ベアメタルランタイム基盤の実装 (ゼロ libc / 直接システムコール)](closed/516-implement-zero-libc-pure-scheme-bare-metal-runtime.md)
  - [Issue 529: トップレベル定義の独立コンパイル構造化および自由変数解析集合演算の高速化](closed/529-structure-independent-toplevel-compilation-and-optimize-free-vars.md)
  - [Issue 596: Backend層: define-language L_asm 導入による命令選択とコード生成の2段階分離](closed/596-implement-define-language-l-asm-two-stage-backend.md)
  - [Issue 602: コンパイラ実行時における現在Nanopass・処理中トップレベル式・ソース位置のコンテキスト追跡とエラー診断ダンプの導入](closed/602-track-compiler-context-pass-and-toplevel-form-on-error.md)
  - [Issue 603: Power Assert 風アサーション式展開および LIR 変数解決失敗時のローカル環境自動ダンプ機能の実装](closed/603-implement-power-assert-and-lir-env-dump-diagnostics.md)
  - [Issue 606: ビルド時 cat 結合の廃止と R7RS include 構文によるソース位置追跡基盤の導入](closed/606-replace-cat-bundle-with-r7rs-include-and-source-tracking.md)
  - [Issue 608: Nanopass・モジュール単位の完全分割コンパイル（.o）および増分ビルド（Incremental Build）基盤の実装](608-implement-modular-separate-compilation-and-incremental-build.md)

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm)
  - 外部シンボル解決フラグ `*allow-extern-symbols*` の新設
  - 決定論的トップレベル関数ラベル生成器 `(mangle-fn-label name)` の追加（`ulisp_fn_<sanitized>` 形式）
  - 決定論的大域変数ラベル生成器 `(mangle-gvar-label name)` の統一（`ulisp_gvar_<sanitized>` 形式）
- [ ] [ulisp/frontend/110_closure_convert.scm](../../ulisp/frontend/110_closure_convert.scm)
  - トップレベル関数登録時における `unique-label-sym` から `mangle-fn-label` への切り替え（`.L_top_` 連番ラベルの排除）
  - `lookup-var` において未束縛かつ `*allow-extern-symbols*` が真の場合、`(%global-ref var)` または外部参照タグへのフォールバック
  - オペレータ呼び出し位置における未解決シンボルの外部直接呼び出し（`(%direct-call (mangle-fn-label op) ...)`）または外部クロージャ呼び出しへの変換
- [ ] [ulisp/lir/130_lir.scm](../../ulisp/lir/130_lir.scm)
  - `lir-compile-variable` において、`env` に束縛が存在せず `*allow-extern-symbols*` が真の場合、エラーを送出せず `(%global-ref %rax var)` を発行
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm)
  - すべてのトップレベル関数定義ラベル（`ulisp_fn_*`）に対する `.globl` および `.type @function` エクスポートディレクティブの出力
  - 共有メタデータテーブル（`__ulisp_symbol_table`, `__ulisp_stackmap_table`, `ulisp_globals_table`）およびランタイム大域変数（`ulisp_quiet_mode`, `ulisp_gc_stress_mode` 等）に対する `.weak` ディレクティブの付与
  - ライブラリ初期化関数 `ulisp_stdlib_init` のエクスポートおよびメインエントリーにおける自動呼び出しコードの生成
  - モジュールコンパイルモード（`--module`）における `_start` の出力抑止
- [ ] [ulisp/stdlib_entry.scm](../../ulisp/stdlib_entry.scm) (新規)
  - 標準ライブラリ群（`lib/*.scm`）およびランタイムサブシステム（`runtime/*.scm`）のみを読み込む単一エントリーファイル
- [ ] [ulisp/compiler_entry.scm](../../ulisp/compiler_entry.scm)
  - 分割コンパイル対応：標準ライブラリを含まずコンパイラ本体のみを読み込み、外部シンボル参照を前提としたビルドの確立
- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm)
  - CLI 引数パーサーへの `--allow-extern` および `--module` フラグの追加
- [ ] [ulisp/Makefile](../../ulisp/Makefile)
  - `build/ulisp_stdlib.o`: `stdlib_entry.scm` のコンパイルルール策定
  - `build/ulisp_compiler.o`: `compiler_entry.scm` の分割コンパイルルール策定
  - `build/ulisp-fast`: `gcc -nostdlib -static build/ulisp_stdlib.o build/ulisp_compiler.o -o $@` による静的リンクルールの追加
  - `test_split_link`: 2 分割リンクバイナリの動作検証ターゲットの新設
- [ ] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh)
  - 2 分割静的リンクバイナリを用いたブートストラップ検証ステップの統合
- [ ] [ulisp/tests/passes/test_extern_symbols.scm](../../ulisp/tests/passes/test_extern_symbols.scm) (新規)
  - 外部シンボル参照を含むコードのコンパイルおよび再配置可能アセンブリ出力の単体テスト

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/607-support-extern-symbols-and-split-stdlib-compiler-linking`

### Phase 1: 決定論的シンボルマングリングと ABI 整合性の確立
1. **`compiler/helpers.scm` の拡張**:
   - フラグ `*allow-extern-symbols*`（初期値 `#f`）を定義。
   - `mangle-fn-label` を実装：
     ```scheme
     (define (mangle-fn-label name)
       (string->symbol (string-append "ulisp_fn_" (sanitize-label-str (symbol->string name)))))
     ```
   - `mangle-gvar-label` を実装：
     ```scheme
     (define (mangle-gvar-label name)
       (string-append "ulisp_gvar_" (sanitize-label-str (symbol->string name))))
     ```

2. **`frontend/110_closure_convert.scm` のトップレベル関数ラベル決定論化**:
   - トップレベル `(define (name ...) ...)` 処理部（Line 244 付近）において、従来の `(unique-label-sym (string-append "L_top_" ...))` を廃止し、`(mangle-fn-label name)` を使用するよう変更。
   - これにより、エクスポートされるラベルが `.L_top_map_42` から `ulisp_fn_map` へ確定化され、外部 ELF オブジェクトからの直接リンクが可能となる。

### Phase 2: 未束縛シンボルの Extern 解決フォールバック機構の実装
1. **`frontend/110_closure_convert.scm` の `lookup-var` 拡張**:
   - `var-map`、`*top-level-fns*`、`*top-level-vars*` のいずれにも見つからないシンボル `var` に対し、`*allow-extern-symbols*` が真であれば、即座に脱落させず `(list '%global-ref var)` へ安全にフォールバック。
   - 呼び出し位置（オペレータ位置 `(op ...)`）において `op` が未束縛の場合：
     - `*allow-extern-symbols*` が真であれば、外部直接呼び出し `(%direct-call (mangle-fn-label op) args...)` を発行。リンカが直接シンボルをバインドできるようにする。

2. **`lir/130_lir.scm` の `lir-compile-variable` 拡張**:
   - `env` 内に束縛が見つからない場合、`*allow-extern-symbols*` が真であれば診断例外（`dump-lir-unbound-variable-diagnostic` / `Unbound variable in LIR`）をバイパスし、外部大域変数参照 `(emit-lir! (list '%global-ref '%rax var))` を発行。
   - `*allow-extern-symbols*` が偽（デフォルト）の場合は、従来通りの厳格な診断エラーを送出して単一翻訳単位ビルド時のバグ即時検出性を維持。

### Phase 3: ネイティブバックエンド（x86-64）の多重定義抑止とリンク整合化
1. **関数の `.globl` エクスポート**:
   - `backend/140_backend_x86_64.scm` の `emit-x86-function` において、`ulisp_fn_*` プレフィックスを持つトップレベル関数に対し以下を出力：
     ```assembly
     .globl <label>
     .type <label>, @function
     .p2align 4
     <label>:
     ```

2. **重複シンボルの弱シンボル化（`.weak`）**:
   - 静的リンク時に複数オブジェクト間で衝突する以下の要素に `.weak` ディレクティブを付与：
     - メタデータテーブル: `ulisp_globals_table`, `__ulisp_symbol_table`, `__ulisp_stackmap_table`
     - ランタイム BSS 変数: `ulisp_quiet_mode`, `ulisp_gc_stress_mode`, `ulisp_gc_state`
     - ゼロ libc ヘルパー関数: `ulisp_print_value`, `ulisp_emit_byte`, `ulisp_flush`, `ulisp_collect_garbage`, `ulisp_oom_panic` 等

3. **ライブラリ初期化関数（`ulisp_stdlib_init`）の自動生成と連鎖呼び出し**:
   - `ulisp_stdlib.o` のトップレベル初期化式（大域変数の初期アロケーション等）を、`scheme_entry` の代わりに `ulisp_stdlib_init` というグローバル関数として出力。
   - `ulisp_compiler.o` の `scheme_entry` 先頭に以下を挿入：
     ```assembly
     lea rax, [rip + ulisp_stdlib_init]
     test rax, rax
     jz .L_skip_stdlib_init
     call ulisp_stdlib_init
     .L_skip_stdlib_init:
     ```

4. **モジュールモード（`--module`）の導入**:
   - `--module` フラグ指定時は、プロセスエントリーポイント `_start` の出力を抑制し、純粋な再配置可能ライブラリオブジェクト（`.o`）として生成。

### Phase 4: エントリーポイント分離と CLI オプション整備
1. **エントリーファイルの分離**:
   - `ulisp/stdlib_entry.scm` を新設し、標準ライブラリ（`lib/*.scm`）およびランタイム（`runtime/*.scm`）のみを `include`。
   - `ulisp/compiler_entry.scm` は既存のコンパイラパス群を `include` し、標準ライブラリを含めない純粋コンパイラユニットとして維持。

2. **`compiler/driver.scm` の CLI フラグ拡張**:
   - `--allow-extern`: `*allow-extern-symbols*` を `#t` に設定。
   - `--module`: `*module-mode*` を `#t` に設定し、`_start` の出力を抑制。

### Phase 5: Makefile ビルドパイプラインと静的リンクルールの統合
1. **`ulisp/Makefile` のターゲット追加**:
   ```makefile
   # 1. Compile Standard Library Object
   build/ulisp_stdlib.s: $(ULISP_BOOT) stdlib_entry.scm
   	./$(ULISP_BOOT) --module stdlib_entry.scm > $@

   build/ulisp_stdlib.o: build/ulisp_stdlib.s
   	$(CC) -c $< -o $@

   # 2. Compile Compiler Object
   build/ulisp_compiler.s: $(ULISP_BOOT) compiler_entry.scm
   	./$(ULISP_BOOT) --allow-extern compiler_entry.scm > $@

   build/ulisp_compiler.o: build/ulisp_compiler.s
   	$(CC) -c $< -o $@

   # 3. Static Linkage of Split Objects
   build/ulisp-fast: build/ulisp_stdlib.o build/ulisp_compiler.o
   	$(CC) -nostdlib -static $^ -o $@
   ```

2. **テストターゲットの追加**:
   - `test_split_link`: `build/ulisp-fast` を用いてサンプルの Scheme プログラム（フィボナッチ、リスト処理、入出力）をコンパイル・実行し、正当性を検証。

### Phase 6: ブートストラップ固定点収束と検証
1. **`bootstrap.sh` への 2 分割リンク検証の組み込み**:
   - Stage 1 / Stage 2 において 2 分割リンクバイナリを生成し、従来のモノリシックバイナリ（`scheme-stage2`）と出力アセンブリが一致することを検証。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] **外部シンボルの許容と決定論的コード生成**:
  - `--allow-extern` 有効時、外部関数呼び出しが `call ulisp_fn_<name>` として出力され、外部変数参照が `[rip + ulisp_gvar_<name>]` として正常に出力されること。
  - `--allow-extern` 無効（デフォルト）時は、未束縛変数に対して従来通りの詳細診断エラー（`Unbound variable in LIR`）が送出されること。
- [x] **多重定義エラーのない静的リンク成立**:
  - `build/ulisp_stdlib.o` と `build/ulisp_compiler.o` が独立して生成され、`gcc -nostdlib -static` または `ld` でシンボル多重定義エラーなく単一実行ファイル `build/ulisp-fast` に結合できること。
- [x] **GC グローバル変数ルートスキャンのセクション自動集約化**:
  - 各モジュールのグローバル変数ポインタが `.section ulisp_globals_sec, "a"` に出力され、リンカ自動生成シンボル `__start_ulisp_globals_sec` / `__stop_ulisp_globals_sec` により、2分割リンク環境下でも漏れなく全グローバル変数が GC プロモート・リロケーション対象となること。
- [x] **初期化順序の整合性と動作検証**:
  - `ulisp_stdlib_init` が確実に先行実行され、標準ポート（`*stdin-port*`）等の大域変数が正常に初期化された状態でコンパイラ本体が動作すること。
- [x] **機能同一性とリグレッションゼロ**:
  - `build/ulisp-fast` でコンパイルしたバイナリの実行結果が、従来のモノリシックバイナリと完全に一致すること（`make test_split_link` 成功）。
  - `make test_all_passes`（全 38 Nanopass 単体テスト）、`make test_backend`、`make test_gc_growth`、および `bash ulisp/test.sh` が 100% PASS すること。
- [x] **ブートストラップ固定点検証**:
  - 2 分割リンクされたコンパイラを用いてセルフホストコンパイルが正常に完了することを確認。

---

## 8. 実装完了報告 / Implementation Summary

- **実施日**: 2026-10-26
- **担当**: IT Specialist (Programming Languages & Compilers / PLC) & Systems Architect
- **主要な変更内容**:
  1. `compiler/helpers.scm`: `mangle-fn-label`、`mangle-gvar-label`、`allow-extern-symbols?`、`module-mode?` フラグを導入。
  2. `frontend/025_top_level.scm`: トップレベル関数のラベルに決定論的な `ulisp_fn_<sanitized>` を適用。
  3. `lir/130_lir.scm`: `allow-extern-symbols?` 有効時、未定義シンボルを `%direct-call` または `%global-ref` として安全に外部委譲。
  4. `backend/140_backend_x86_64.scm`:
     - トップレベル関数および静的クロージャ、BSS領域に `.globl` / `.weak` 属性を付与。
     - グローバル変数メタデータを ELF セクション `ulisp_globals_sec` に出力し、モジュール分割時にもリンカ（`ld`）が全グローバル変数を自動集約するアーキテクチャを確立。
  5. `backend/141_backend_x86_gc.scm`:
     - Dual-Space GC および Minor GC の大域変数スキャンループを `__start_ulisp_globals_sec` 〜 `__stop_ulisp_globals_sec` を巡回する方式に統一。モジュール分割リンク環境下での GC 漏れによるヒープ破壊を完全解消。
  6. `Makefile`:
     - `build/ulisp_stdlib.o`、`build/ulisp_compiler.o`、`build/ulisp-fast`（2分割静的リンクバイナリ）のビルドルール新設。
     - `make test_split_link` ターゲットを整備し、分割リンクバイナリによる自己ホストコンパイルと実行テストの自動検証を確立。
  7. `tests/passes/test_extern_symbols.scm`: 外部シンボルマングリングおよびディレクティブ出力の単体テスト（全14テスト）を追加。全件 PASS。

---

## 8. 検証手順 / Verification Procedure

1. **外部シンボル単体テストの実行**:
   ```bash
   cd ulisp && $(RUN_SCHEME) tests/passes/test_extern_symbols.scm
   ```
   *期待される結果*: 外部関数 `map` や外部変数 `*stdin-port*` を含む式が、エラーなく LIR および x86-64 アセンブリ（再配置可能シンボル参照）として出力されること。

2. **2分割コンパイルおよび静的リンクの実行**:
   ```bash
   cd ulisp
   make build/ulisp_stdlib.o
   make build/ulisp_compiler.o
   gcc -nostdlib -static build/ulisp_stdlib.o build/ulisp_compiler.o -o build/ulisp-fast
   ```
   *期待される結果*: リンカエラー（`undefined reference` や `multiple definition`）が 0 件で完了し、実行可能バイナリ `build/ulisp-fast` が生成されること。

3. **分割リンクバイナリによる自己ホスト・スモークテスト**:
   ```bash
   ./build/ulisp-fast tests/test_simple.scm > build/test_simple.s
   gcc -nostdlib -static build/test_simple.s -o build/test_simple
   ./build/test_simple
   ```
   *期待される結果*: 正常な実行結果が出力され、終了コード 0 で完了すること。

4. **全品質管理ゲートの実行**:
   ```bash
   make verify_quality
   make test
   ```
   *期待される結果*: Python 構文検査、静的解析、全単体テストが 100% PASS すること。

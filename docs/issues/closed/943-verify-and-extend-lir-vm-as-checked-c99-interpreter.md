---
ID: 943
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-11-25
担当エージェント:
  - IT Specialist (Programming Languages & Compilers / PLC) [Lead]
  - Software Development (SWD)
  - Information Security Specialist
  - Software Quality Assurance Specialist
ターゲットブランチ: feat/943-verify-and-extend-lir-vm-as-checked-c99-interpreter
---

# [FEAT/ENH] Case A の C99 拡張：LIR 参照 VM の検査付き C インタプリタ実行可否検証と差分診断ハーネス構築 (ID: 943)

## 1. 背景と課題 / Background & Problem Statement

ULisp が C99 および Lua 5.4.7 をコンパイル可能になったことで、$\mathrm{Interp}_C = \mathrm{Interp}_{\text{LIR}} \circ \mathrm{Comp}_C$ の関係から、LIR 参照 VM（[`ulisp/vm/lir_interpreter.scm`](../../../ulisp/vm/lir_interpreter.scm)）を追加の枠組みなしで「NULL ページアクセスや範囲外メモリアクセスをトラップする検査付き C インタプリタ（Miri に近い位置づけ）」として活用できる。これにより、Lua 等の誤コンパイル時に原因がフロントエンド（C → LIR）にあるかバックエンド（LIR → x86-64）にあるかを切り分けられる。

現行のコードベース調査により、以下の基盤と未解決ギャップが特定された：

### 既設基盤（確認済み）
- `lir_interpreter.scm`（`<lir-vm>`）は 16MB 線形バイトベクタメモリ（`*lir-vm-default-mem-size* = 16777216`）、NULL 保護ページ（`0..4095`, `*lir-vm-null-page-limit* = 4096`）、2 パス `.data`/`.bss`・`(reloc target addend)` ローダ、16 本の汎用レジスタ + 16 本の XMM レジスタ（`%xmm0`..`%xmm15`）、`__ulisp_setjmp`/`__ulisp_longjmp`、`__ulisp_san_trap`、および基本 libc / `libm` スタブを既に備えている。

### 解消済みギャップ（本 Issue での実装完了事項）
1. **C99 標準ライブラリ / built-in FFI カバレッジの拡充 (`vm-exec-c-call!` / `vm-dispatch-c-call!`)**:
   - `realloc`, `strcpy`, `strncpy`, `strcat`, `strchr`, `strrchr`, `strstr`, `memchr`, `strspn`, `strcspn`, `strpbrk`, `strtol`, `strtoul`, `strtoll`, `strtoull`, `atoi`, `atol`, `abs`, `labs`, `llabs`, `snprintf`, `sprintf`, `vsnprintf`, `vsprintf`, `qsort`, `bsearch`, `abort`, `__errno_location`, `__errno` の純 Scheme エミュレーションを追加実装し、`qsort`/`bsearch` 比較関数コールバックが呼出元スタックフレーム（`shift + 16`）を破壊しないよう保護した。
2. **Weak シンボル・シンボルエイリアス解決 (`lir-vm-load!` & `c99-merge-lir-programs`)**:
   - `(weak-fns ...)`, `(weak-data ...)`, `(aliases ...)` メタデータ句の読み込み・強定義による弱定義上書き・エイリアスの `functions-table`/`data-table`/`code-addr-table` 透過登録・未定義弱関数呼び出し時の `'invalid-call-target` トラップを実装した。
3. **構造化トラップ返却・終了コード・診断契約 (`--target=vm`)**:
   - `eval-lir-program-checked` / `c99-eval-lir-program-checked` / `c-driver-run-vm` および `--vm-fuel=<N>` を実装し、トラップ発生時に `[ulisp-vm-trap]` 診断を `stderr` へ出力した上で `c-driver-cli-main` から決定論的に終了コード `134` を返す契約を確立した。
4. **C99 x86-64 ネイティブ vs LIR 参照 VM 差分診断ハーネス (`c99-diff-vm-vs-native`)**:
   - `c99-diff-vm-vs-native` および [`test_c99_lir_vm_checked.scm`](../../../ulisp/tests/test_c99_lir_vm_checked.scm)（全 29 テスト PASS）を構築し、単一 TU / 複数 TU における整数・ビットフィールド・ポインタ・`switch`/関数ポインタ・`stdarg`+`vsnprintf`・`setjmp`/`longjmp`・IEEE 754/`libm`・`qsort`・Lua イディオム・`--sanitize-bounds` トラップの完全一致を検証した。

---

## 2. トレーサビリティと影響範囲 / Traceability & Scope

### 関連ドキュメント（すべて相対リンク）
- [DSN-33-13](../../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- [DSN-33-32](../../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
- [Issue #834](834-implement-pure-scheme-lir-reference-vm-interpreter.md)
- [Issue #930](930-implement-c99-bounds-checking-sanitizer-mode.md)

### 変更ファイル
- [x] [`ulisp/vm/lir_interpreter.scm`](../../../ulisp/vm/lir_interpreter.scm): Weak/Alias メタデータローダ対応、純 Scheme C99 libc・コールバックスタブ拡張（NULL ページ・境界チェック付）、`eval-lir-program-checked`
- [x] [`ulisp/driver/c_driver.scm`](../../../ulisp/driver/c_driver.scm): `--vm-fuel=<N>`、複数 TU Weak 上書き/Alias マージ、`c99-eval-lir-program-checked` / `c-driver-run-vm`（トラップ終了コード `134`・`stderr` 診断）、`c99-diff-vm-vs-native`
- [x] [`ulisp/compiler/c_driver_module_header.scm`](../../../ulisp/compiler/c_driver_module_header.scm): `c99_vm` / `c99_driver` 分割モジュール向け extern 識別子登録
- [x] [`ulisp/tests/test_c99_lir_vm_checked.scm`](../../../ulisp/tests/test_c99_lir_vm_checked.scm): 検査付き C インタプリタ実行・CWE トラップ検証・x86-64 vs VM 差分テストスイート（29 PASS）
- [x] [`ulisp/Makefile`](../../../ulisp/Makefile): `test_c99_lir_vm_checked` テストターゲット登録

---

## 3. セキュリティ・品質観点の要件 / Security & Safety Requirements

- **CWE-476 (NULL Pointer Dereference)**: `*lir-vm-null-page-limit*` (`4096`) 未満へのロード/ストアおよび libc スタブ（`strlen(NULL)`, `memcpy(NULL, ...)` 等）を即座に `'out-of-bounds` としてトラップする。
- **CWE-125 / CWE-787 (Out-of-bounds Read/Write)**: `--sanitize-bounds` 有効時の `__ulisp_san_trap`（`'sanitizer-trap`, exit code `134`）および線形メモリ境界外アクセスを決定論的に捕捉する。
- **CWE-400 (Uncontrolled Resource Consumption)**: `--vm-fuel=<N>` による `'out-of-fuel` 安全停止（exit code `134`）をサポートする。

---

## 4. 完了条件 / Definition of Done (DoD)

- [x] **Loader & Metadata Parity**: `lir-vm-load!` および `c99-merge-lir-programs` が `(aliases ...)` / `(weak-fns ...)` / `(weak-data ...)` を解決し、単一 TU・複数 TU ともに未解決ターゲットなしでロード・上書きできること。
- [x] **Checked C99 Libc & Memory Safety**: `vm-dispatch-c-call!` が C99/Lua 標準ライブラリスタブを純 Scheme でエミュレートし、CWE-476 / CWE-125 / CWE-787 / ゼロ除算 / CWE-400 をすべて決定論的にトラップすること。
- [x] **Driver Diagnostics (`--target=vm`)**: `c-driver-main` / `c-driver-cli-main`（およびネイティブ `bin/ulisp-cc --target=vm`）が正常戻り値とトラップ終了コード `134`＋診断出力を返却できること。
- [x] **Differential Parity**: `test_c99_lir_vm_checked.scm`（29/29 PASS）および既存 C99 VM スイート群で `--target=vm` とネイティブ x86-64 実行の完全一致が確認されていること。
- [x] **Quality Gates**: `lint_sexpr.py`, `verify_zero_gauche`, `test_lir_interpreter` (65/65), `test_c99_lir_vm_checked` (29/29), `bin/ulisp-cc --target=vm`, `make check_format`, `make static_analysis`, `make py_compile` がすべて PASS すること。

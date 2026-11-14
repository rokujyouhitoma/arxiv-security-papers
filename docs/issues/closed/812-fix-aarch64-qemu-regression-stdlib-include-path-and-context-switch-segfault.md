---
ID: 812
種別: Bug
優先度: Medium
ステータス: Closed
完了日: 2026-11-14
---

# [BUG/SEC] AArch64 QEMU 回帰ターゲットにおける stdlib include パス解決失敗とコンテキストスイッチテストの SIGSEGV (ID: 812)

## 1. 概要 / Summary

Issue #809 の回帰検証中に、`main` ブランチ（変更前）でも再現する AArch64 実機（QEMU）系ターゲットの既存不具合を 2 件検出し、詳細な原因究明を実施した。

1. `make -C ulisp test_aarch64_qemu` の依存ターゲット `build/ulisp_stdlib_aarch64.s` が、`cd $(ROOT_DIR)` 後に `ulisp/compiler.scm` を実行した際、`stdlib_entry.scm` 内の `(include "lib/posix.scm")` 等の相対パスが解決できず `*** SYSTEM-ERROR: couldn't open input file: "lib/posix.scm"` により異常終了する。
2. `make -C ulisp test_context_switch_aarch64` が、未定義シンボルによるリンクエラー、モジュールヒープ破壊、LIR ピープホール最適化における AArch64 レジスタエイリアス誤認識、および TCB ヘッダ長（80B）不整合に起因して `qemu: uncaught target signal 11 (Segmentation fault)` により異常終了する。

### 再現手順 / Steps to Reproduce
1. `git checkout main && make -C ulisp compiler`
2. `make -C ulisp build/ulisp_stdlib_aarch64.s` → include パスエラー (Error 70)
3. `make -C ulisp test_context_switch_aarch64` → 未定義シンボル / QEMU SIGSEGV

### 再現環境 / Environment
- OS / Env: Linux x86-64 ホスト + `aarch64-linux-gnu-as/ld` + `qemu-aarch64` + `gdb-multiarch`
- 確認日: 2026-11-13〜2026-11-14（Issue #809 作業ブランチおよび `main` の双方で同一結果）

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [ulisp/frontend/010_library.scm](../../ulisp/frontend/010_library.scm)（`find-included-file`, `resolve-include-path`）
- [ulisp/backend/150_backend_aarch64.scm](../../ulisp/backend/150_backend_aarch64.scm)（`*top-level-fns*` 静的クロージャ出力、`module-mode?` ヒープポインタ保持）
- [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)（`lir-inst-defines-reg?`, `lir-reg-aliases?`）
- [ulisp/runtime/concurrency/context_aarch64.s](../../ulisp/runtime/concurrency/context_aarch64.s)（AAPCS64 初期フレームオフセット 160B → 176B 是正）
- [tests/concurrency/test_context_switch_aarch64.scm](../../tests/concurrency/test_context_switch_aarch64.scm)（TCB ヘッダ長 80B 整合、アサーション値是正）
- [ulisp/Makefile](../../ulisp/Makefile)（`build/ulisp_stdlib_aarch64.s`, `test_context_switch_aarch64`, `test_aarch64_qemu`）
- 関連: [Issue #809](closed/809-fix-safepoint-poll-lir-code-emission-and-add-aarch64-stub.md), [Issue #787](closed/787-expand-task-context-block-header-for-handler-chain.md), [Issue #799](closed/799-add-cross-worker-coroutine-yield-exception-and-linux-ci-stress-tests.md)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

GDB / QEMU 動的解析および LIR/ASM コード追跡により、以下の 5 つの根本原因を特定・実証した。

### 原因 1: `find-included-file` における未捕捉 Gauche 例外
- `ulisp/frontend/010_library.scm` 内の `find-included-file` および `resolve-include-path` が、ファイルの存在確認に `(open-input-file path)` を直接使用していた。
- Gauche (`gosh`) において非存在パスに対して `open-input-file` を呼び出すと、`#f` は返らず未捕捉の `<system-error>` が送出されてコンパイラが強制終了する。
- 一方、`ulisp/compiler/helpers.scm` 等では R7RS 標準の `(file-exists? path)` が用いられており、例外を投げず安全に `#f` を返す。

### 原因 2: `150_backend_aarch64.scm` における `*top-level-fns*` 出力欠落
- `140_backend_x86_64.scm` では末尾の `.data` セクションで `*top-level-fns*` を巡回し、全トップレベル関数に対応する静的クロージャ記述子 (`.L_static_closure_<fn>`) とグローバル変数シンボル (`ulisp_gvar_<fn>`) を `.weak` で出力している。
- AArch64 バックエンド (`150_backend_aarch64.scm`) では `*top-level-vars*` のみを `.bss` に出力しており、`*top-level-fns*` の出力ループが完全に欠落していた。
- このため、`ulisp_stdlib_aarch64.o` 内の関数を第一級関数や高階関数として参照するシンボル（`ulisp_gvar_test_runner_get`, `ulisp_gvar_test_on_group_begin_unified` 等）が解決できず、リンクエラーが発生していた。

### 原因 3: `150_backend_aarch64.scm` のモジュールモード (`module-mode?`) におけるヒープポインタ破壊
- AArch64 では `x19` がヒープアロケーションポインタ（x86-64 の `r12` 相当）として全域で使用される。
- しかし、`150_backend_aarch64.scm` のプロローグ/エピローグは `module-mode?`（`ulisp_stdlib_init`）であっても `x19` をスタック退避・復元 (`stp x19 ... / ldp x19 ...`) し、さらにプロローグで `mov x19, x0` を実行していた。
- これにより、`ulisp_stdlib_init` が割り当てたヒープ進捗が `scheme_entry` に戻った瞬間に元のベースアドレスへ巻き戻され、`scheme_entry` が stdlib のヒープオブジェクトを上書き破壊していた。

### 原因 4: LIR ピープホール (`133_lir_peephole.scm`) における AArch64 レジスタエイリアス無視
- `rule-lir-store-load-forward` は直前の `%store` から同一スタック位置の `%load` を検出し、代入元レジスタからの直接 `%mov` に置換する。
- この際、介在命令が代入元レジスタを再定義していないかを `lir-inst-defines-reg?` で検査する。
- x86-64 では戻り値 `%rax` と第1引数 `%rdi` は独立した物理レジスタである。しかし AArch64 では両方とも同一の `x0` にマップされる。
- `lir-inst-defines-reg?` がエイリアスを認識していなかったため、第1引数（`runner`）をメモリからロードした直後に、第2引数ロード（`closure`）が「`%rax` の値を転送すればよい」と誤判定され、`mov x1, x0` が生成された。
- 結果として、第1引数の `runner` レコードポインタが第2引数のクロージャとしても渡され、`<test-runner>` レコード内の全関数ポインタフィールドが `runner` 自身のポインタ（`0x...5`）で汚染され、関数呼び出し時に未定義アドレス（`0x0055f20200000000`）へジャンプして SIGSEGV を引き起こしていた。

### 原因 5: AArch64 コンテキストスイッチの TCB オフセット不整合
- Issue #787 / #799 で `<task-stack>` の TCB ヘッダサイズが 64 バイトから 80 バイト（`*context-tcb-header-size* = 80`）に拡張された。
- x86-64 では `sub rdi, 144`（TCB 80B + フレーム 64B）に更新されていたが、AArch64 側の `runtime/concurrency/context_aarch64.s` は旧仕様の `160`（64B + 96B）のまま残っていた。
- 正しい AArch64 オフセットは `176`（80B + 96B）であり、`160` のままレジスタ検証ルーチンが動作したため、スタックカナリア領域（`[top - 80]`）が破損し、カナリアチェックが `#f` となっていた。
- さらに `ulisp/Makefile` の `test_context_switch_aarch64` ターゲットが `lib/stdlib_macros.scm` を結合せず、かつ `build/ulisp_stdlib_aarch64.o` をリンクしていなかったため、SRFI-64 構文が未定義関数参照となっていた。

### 原因 6: `150_backend_aarch64.scm` の `%call-closure` における第 2 引数レジスタ (`x1`) 破壊
- AArch64 バックエンドの `%call-closure` 実装において、クロージャポインタ (`x10`) から関数エントリーアドレスをロードするスクラッチレジスタとして `x1` を使用していた (`ldr x1, [x10, #-1]; blr x1`)。
- しかし AAPCS64 において `x1` は第 2 引数レジスタであるため、2 引数以上のクロージャ呼び出し（`assq` 等）において第 2 引数が関数エントリーアドレスで上書き破壊され、`assq` が常に `#f` を返すか不正メモリ参照により SIGSEGV を引き起こしていた。
- 他の呼び出し箇所（`%dispatch-consumer` 等）と同様に、AArch64 標準の呼び出し時スクラッチレジスタ `x16` (`ldr x16, [x10, #-1]; blr x16`) を使用するよう是正した。

---

## 4. 実装方針 / Implementation Plan

### 対象ブランチ
`fix/812-fix-aarch64-qemu-regression-stdlib-include-path-and-context-switch-segfault`

### Phase 1: Include パス解決の堅牢化 (`010_library.scm`)
1. [ulisp/frontend/010_library.scm](../../ulisp/frontend/010_library.scm) の `find-included-file` および `resolve-include-path` を、`open-input-file` から `file-exists?` を用いた安全なチェック方式へ改修する。
2. 相対パス、`ulisp/` プレフィックス付きパス、プレフィックス除去パスの順に `file-exists?` で探索し、Gauche 例外送出を完全に防止する。

### Phase 2: AArch64 バックエンドのシンボル出力とヒープポインタ維持 (`150_backend_aarch64.scm`)
1. `150_backend_aarch64.scm` の末尾において、`140_backend_x86_64.scm` と同様に `*top-level-fns*` を巡回し、静的クロージャ `.L_static_closure_*`（ヘッダ `4195336`、関数ポインタ、タグ `+9`）および `ulisp_gvar_*` を `.data` セクションに出力する。
2. `mangle-gvar-label` を使用してグローバルシンボル名を正規化する。
3. `emit-aarch64` のプロローグ/エピローグにおいて、`module-mode?` 時は `x19` をスタック退避・復元せず、また `mov x19, x0` を実行しないように分岐させ、stdlib で進んだヒープポインタがそのまま呼び出し元 `scheme_entry` に引き継がれるようにする。

### Phase 3: LIR ピープホールにおける AArch64 レジスタエイリアス認識 (`nanopass_meta.scm`)
1. [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm) に `lir-reg-aliases?` を追加する。
   - `(current-target-arch)` が `'aarch64` の場合、`(%rax %rdi %al)` および `(%rbx %r12)` をそれぞれ同一エイリアスグループとみなす。
2. `lir-inst-defines-reg?` の全定義判定を `(lir-reg-aliases? def-reg target-reg)` 経由に変更し、AArch64 において第1引数ロードによる `%rax` 破壊を正しく検知・ストアロード転送の誤適用を抑止する。

### Phase 4: AArch64 コンテキストスイッチ & Makefile 整合 (`context_aarch64.s`, `test_context_switch_aarch64.scm`, `Makefile`)
1. [ulisp/runtime/concurrency/context_aarch64.s](../../ulisp/runtime/concurrency/context_aarch64.s) の `ulisp_fn__pctasm_verify_swap_context_regs_excl` におけるスタックオフセットを `160` から `176`（80B TCB + 96B フレーム）に是正する。
2. [tests/concurrency/test_context_switch_aarch64.scm](../../tests/concurrency/test_context_switch_aarch64.scm) の Group 2 アサーションを、x86-64 側と同様に `*context-tcb-header-size*`（80B）および `context-frame-size`（96B）に基づく動的計算に更新する。
3. [ulisp/Makefile](../../ulisp/Makefile) の `test_context_switch_aarch64` ターゲットを以下のように改修する:
   - `(!gc none) (!allow-extern #t) (!disable-pass pass-synapse-inject-safepoints)` をプリペンド。
   - `lib/stdlib_macros.scm` をテストコード先頭に結合。
   - `build/ulisp_stdlib_aarch64.o` をリンク対象に追加。

### Phase 5: 回帰検証と品質ゲート検査
1. `make -C ulisp compiler` でコンパイラを再構築。
2. `make -C ulisp build/ulisp_stdlib_aarch64.o` の単体ビルド成功を確認。
3. `make -C ulisp test_context_switch_aarch64` を実行し、全 7 グループ（アライメント、AAPCS64 不変条件、レジスタ退避、コルーチン、耐久ベンチマーク等）が QEMU 上で 100% PASS することを確認。
4. `make -C ulisp test_aarch64_qemu` がクリーンに PASS することを確認。
5. リポジトリ全体の品質ゲート (`make py_compile`, `make static_analysis`) を実行し、全項目 PASS を確認。

---

## 5. 脅威モデルとセキュリティ考察 / Threat Modeling & Security Considerations

| 脅威 / リスク | 影響 | 対策 |
| :--- | :--- | :--- |
| **CWE-787: Out-of-bounds Write** | TCB ヘッダオフセットのズレによりスタックカナリア領域が破壊され、カナリア検証が無力化する。 | TCB ヘッダサイズ 80B + AAPCS64 フレーム 96B = 176B の定数整合を徹底し、スタックオーバーフロー検知機構を完全に維持。 |
| **CWE-843: Type Confusion / 不正間接分岐** | レジスタエイリアス無視による引数破壊により、レコード型がクロージャとして誤認識され不正アドレスへ間接ジャンプする。 | LIR ピープホールオプティマイザにターゲットアーキテクチャ認識エイリアス解析を導入し、不正なレジスタ転送を静的に完全排除。 |
| **CWE-416: Use After Free** | stdlib モジュールのヒープポインタが初期化時に巻き戻され、解放済み/再利用メモリ領域の不正読み書きが発生。 | モジュールモードにおけるヒープポインタの単調増加・引き継ぎセマンティクスを強制し、ヒープ破壊を防止。 |

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `010_library.scm` の include パス解決が `file-exists?` を使用し、存在しないパスに対する例外送出が根絶されていること
- [x] `build/ulisp_stdlib_aarch64.s` および `.o` が `make -C ulisp` から単体で正常にビルドできること
- [x] `150_backend_aarch64.scm` に `*top-level-fns*` 由来の静的クロージャおよび `ulisp_gvar_*` シンボルが出力されること
- [x] AArch64 における `module-mode?` 実行時に `x19`（ヒープポインタ）が破壊されず、stdlib のヒープアロケーションが保持されること
- [x] `nanopass_meta.scm` の `lir-inst-defines-reg?` が AArch64 の `%rax` / `%rdi` レジスタエイリアスを正しく扱い、第1引数と第2引数の混同バグが発生しないこと
- [x] `context_aarch64.s` のスタックフレームオフセットが 80B TCB ヘッダに対応し（176B）、スタックカナリアが正常に機能すること
- [x] `test_context_switch_aarch64.scm` の全グループが QEMU 上で SIGSEGV なく 100% PASS すること（71/71 assertions passed）
- [x] `make -C ulisp test_aarch64_qemu` が正常終了すること（全 206/206 テスト PASS）
- [x] `make py_compile` および `make static_analysis` がエラー 0 件で通過すること

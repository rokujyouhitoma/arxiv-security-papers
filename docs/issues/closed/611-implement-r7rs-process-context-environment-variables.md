---
ID: 611
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
完了日: 2026-10-28
---

# [FEAT/ENH] R7RS (scheme process-context) 環境変数取得手続き (get-environment-variable / get-environment-variables) の実装 (ID: 611)

## 1. 概要 / Summary
R7RS-small §6.14（System interface）および §5.6 / §5.1 `(scheme process-context)` で規定されている環境変数取得手続きを完全実装する。
1. `(get-environment-variable name)`: 指定した名前の環境変数の値を文字列として取得（存在しない場合は `#f` を返却）
2. `(get-environment-variables)`: プロセスに設定されている全環境変数を名前と値のペア `("NAME" . "VALUE")` の連想リスト（alist）として返却

ULisp のネイティブ AOT ランタイム（x86-64 フリースタンディング / libc 非依存 Linux ELF 実行系、および C / AArch64 バックエンド）において、プロセス起動時に Linux カーネルからスタック上に渡される `char **environ` ポインタを保持・Scheme 空間へ安全に露出する低レベルメカニズムを確立する。
これにより、100% Pure Scheme のセーフティガード下で環境変数テーブルの線形探索・キー照合・文字列構築を行い、外部 libc や動的ライブラリに一切依存しない完全なスタンドアロン実行系として R7RS `(scheme process-context)` の仕様適合率 100% を達成する。

---

## 2. ガバナンス・専門エージェント多角レビュー / Governance & Reviews

本 Issue は、16 専門エージェントフレームワークに基づき、以下の重点専門領域からの設計レビューを統合して策定された。

- **IT Specialist (Programming Languages & Compilers / PLC)**:
  - R7RS-small §6.14 仕様に厳格準拠し、未定義環境変数の参照時に例外を送出せず確実に `#f` を返す不変条件を設計。
  - `(get-environment-variables)` においてキーと値のペア `("KEY" . "VAL")` からなる連想リストを構築し、標準 Scheme の `assoc` 手続きで自然に検索可能なデータ構造を保証。
  - C 文字列終端のヌル文字（`\0`）境界判定を安全に行うため、単一バイト読み出しプリミティブ `%raw-load-u8` を導入し、ページ境界跨ぎの投機的リードによる SEGV を根本防止。
- **Systems Architect**:
  - Linux x86-64 ABI における ELF エントリポイント `_start` 時のスタックレイアウト（`argc`, `argv[]`, `NULL`, `envp[]`, `NULL`）を正確にモデル化。
  - バックエンド層（`140_backend_x86_64.scm`, `160_backend_c.scm`）で静的ポインタスロット `ulisp_environ` を確保し、初期化時に `envp` の先頭アドレスを退避。
  - Scheme 空間からは既存の `%raw-load` および新規 `%get-environ-ptr` 経由で間接参照することで、コンパイラ中間層の抽象度を維持しつつゼロ libc で完結するポータブルアーキテクチャを確立。
- **Software Quality Assurance Specialist (SQA)**:
  - 既存環境変数（`PATH`, `USER`, `HOME` 等）の正常取得、存在しないキーに対する `#f` 返却、空文字列環境変数（`EMPTY=""`）の境界値テストを網羅。
  - 全環境変数連想リストの要素数・型（ペアリストであること）・`assoc` による参照可能性を自動検証する統合テスト `ulisp/tests/test_process_context.scm` を策定。
  - ゼロ libc ネイティブバイナリおよび C バックエンド双方での同等実行性（Differential Consistency）を CI 品質ゲートに組み込む。
- **Information Security Specialist**:
  - 環境変数は外部 untrusted 入力となるため、ヌルポインタ参照（CWE-476）、境界外読み取り（CWE-125）、バッファオーバーフロー（CWE-120/CWE-787）、および無限ループによるサービス拒否（CWE-835）の脅威分析を実施。
  - 探索時のキー照合アルゴリズムにおいて、プレフィックス一致（例: `"PATH"` を探している際に `"PATH_EXT"` に部分一致してしまう不具合）を厳格に排除し、`KEY=` のデリミタ（`=`）の一致確認を必須化。
- **Project Manager (PM)**:
  - Issue 609 (`case-lambda`)、Issue 610 (`base` コア手続き)、および Issue 612 (`char` 述語) と並行して進める R7RS-small 標準ライブラリ完備マイルストーンの一環として位置付け。
  - 本機能の完了により、`(scheme process-context)` の適合率を 50% から 100% へ引き上げ、ビルドスクリプトやツールチェインが環境設定を Scheme 側で柔軟にハンドリング可能となる基盤を確立。

---

## 3. トレーサビリティ / Traceability

- **正典仕様書**:
  - R7RS-small:
    - §6.14: System interface (`get-environment-variable`, `get-environment-variables`)
    - §5.6 / §5.1: `(scheme process-context)`
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 4 章 ランタイムおよびシステムコールインターフェース)
  - [ULisp R7RS 準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) §1.3 (6.14), §1.4 (`(scheme process-context)`)
- **関連 Issue**:
  - Issue #516: [Pure Scheme Bare-Metal Linux Runtime の確立](closed/516-pure-scheme-bare-metal-linux-runtime.md)
  - Issue #580: [Standalone Process Orchestration and Runtime Main](closed/580-standalone-process-orchestration-and-runtime-main.md)
  - Issue #614: [ランタイムのデフォルト沈黙化とコンパイラ成果物出力の是正](614-refactor-runtime-silence-by-default-and-compiler-cli-output.md)
  - Issue #621: [コンパイラ Nanopass 実行時間・メモリ消費プロファイラの実装](closed/621-implement-compiler-pass-timing-and-memory-profiler.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm): `ulisp_environ` グローバルポインタの定義および `_start` での `envp` 格納コード生成
- [ ] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm): C バックエンド `main` における `ulisp_environ = (uint64_t)envp;` 格納
- [ ] [ulisp/compiler/primitives.scm](../../ulisp/compiler/primitives.scm): `%get-environ-ptr` (nullary) および `%raw-load-u8` (binary) プリミティブ宣言
- [ ] [ulisp/compiler/scope.scm](../../ulisp/compiler/scope.scm): スコープ解決テーブルへの `%get-environ-ptr`, `%raw-load-u8` 追加
- [ ] [ulisp/lir/129_lir_primitives.scm](../../ulisp/lir/129_lir_primitives.scm): LIR コード生成における `%get-environ-ptr` および `%raw-load-u8` 命令選択
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm): 単一ファイル版コンパイラへの同期反映
- [ ] [ulisp/lib/posix.scm](../../ulisp/lib/posix.scm): Pure Scheme による `sys-environ-ptr`, `%raw-c-strlen`, `get-environment-variable`, `get-environment-variables` の実装
- [ ] [ulisp/lib/scheme/process-context.sld](../../ulisp/lib/scheme/process-context.sld): 手続きのエクスポート確認・整備
- [ ] [ulisp/tests/test_process_context.scm](../../ulisp/tests/test_process_context.scm): 新規統合テストスイート
- [ ] [ulisp/Makefile](../../ulisp/Makefile): `test_process_context` テストターゲットの追加
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md): `(scheme process-context)` 準拠ステータス更新 (50% → 100%)
- [ ] [docs/issues/611-implement-r7rs-process-context-environment-variables.md](611-implement-r7rs-process-context-environment-variables.md): 本仕様書
- [ ] [docs/issues/README.md](README.md): Issue 台帳のステータス更新

---

## 5. 脅威分析とセキュリティ要件 / Threat Modeling & Security Requirements

環境変数は外部プロセスや攻撃者によって制御可能な untrusted 入力であるため、メモリ安全性および堅牢性に関する脅威分析を実施する。

| 脅威分類 (STRIDE / CWE) | 脅威シナリオ | 影響度 | 対策要件 (Mitigation Requirements) |
| :--- | :--- | :---: | :--- |
| **境界外メモリ読み取り (CWE-125)** | 環境変数文字列の終端ヌル文字（`\0`）を探索する際、8 バイト単位の `%raw-load` で読み出すとページ末尾の直後で SEGV が発生する恐れがある。 | High | 1 バイト単位のゼロ拡張ロードプリミティブ `%raw-load-u8` を新設し、ポインタ境界を厳格に遵守して 1 バイトずつヌル終端を走査する。 |
| **ヌルポインタ間接参照 (CWE-476)** | 環境変数が 1 つも設定されていない場合やブートストラップ環境等で `ulisp_environ` が 0 (NULL) の場合にクラッシュする。 | High | `(sys-environ-ptr)` においてポインタ値が 0 であるか検査し、NULL の場合は即座に探索を中止して安全に `#f` または `'()` を返却する。 |
| **不正な引数入力 / 型混乱 (CWE-20)** | `(get-environment-variable 123)` や `(get-environment-variable 'path)` のように文字列以外の不正な型が渡された場合にランタイムが破壊される。 | Medium | 入力引数が `(string? name)` であることを明示的にアサート・型検査し、非文字列の場合は型エラー（または安全に `#f`）を返却する。 |
| **キープレフィックス誤一致 (CWE-697)** | `"PATH"` を探索している際に `"PATH_EXT=foo"` や `"PATH_LOCAL=bar"` の先頭部分一致に誤ってマッチし、誤った環境変数の値を返却する。 | Medium | キー文字列の一致判定において、`name` の長さ分の文字が完全一致し、かつその直後の文字が厳格にデリミタ `'='` (ASCII 61) であることを確認する。 |
| **無限ループ / DoS (CWE-835)** | 終端 NULL ポインタが存在しない異常なポインタ配列により、メモリ空間全体を走査し続けてプロセスがハングする。 | Low | 最大探索件数のリミットガード（例: 最大 65,536 エントリ）を設け、NULL 終端または上限到達で安全にループを脱出する。 |

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/611-implement-r7rs-process-context-environment-variables`

### 6.1 ネイティブランタイム層における `environ` ポインタの保持
Linux x86-64 freestanding 実行可能ファイルでは、カーネルがプロセス起動時にスタック上に以下の情報を配置する：
```text
  [rsp + 0]                  : argc (64-bit int)
  [rsp + 8]                  : argv[0] pointer
  ...
  [rsp + 8*argc]             : argv[argc-1] pointer
  [rsp + 8*argc + 8]         : NULL (0x0)
  [rsp + 8*argc + 16]        : envp[0] pointer (environ 先頭アドレス)
  ...
  [rsp + 8*argc + 16 + 8*N]  : NULL (0x0) (environ 終端)
```
1. `ulisp/backend/140_backend_x86_64.scm`:
   - `.bss` / `.data` 領域にグローバルシンボル `ulisp_environ` を定義：
     ```assembly
         .globl ulisp_environ
     ulisp_environ:
         .quad 0
     ```
   - `_start` エントリポイントにおいて、`argc`（`[rbp]`）と `argv[0]`（`[rbp + 16]`）から `envp` の先頭アドレスを計算し、`ulisp_environ` に格納：
     ```assembly
         mov rcx, [rbp]                   ; argc
         lea rdx, [rbp + 16]              ; &argv[0]
         lea rdx, [rdx + rcx*8]           ; past argv NULL -> envp
         lea rax, [rip + ulisp_environ]
         mov [rax], rdx
     ```
2. `ulisp/backend/160_backend_c.scm`:
   - グローバル変数 `uint64_t ulisp_environ = 0;` を定義。
   - `main(int argc, char **argv, char **envp)` 内で `ulisp_environ = (uint64_t)envp;` を実行。

### 6.2 コンパイラプリミティブおよび LIR 命令選択の拡張
1. `%get-environ-ptr` (引数なし):
   - `ulisp_environ` 変数のアドレスを返すプリミティブ。
   - LIR 命令: `(%code-ref %rax "ulisp_environ")`
2. `%raw-load-u8` (2 引数: `base-ptr`, `byte-offset`):
   - アドレス `base-ptr + byte-offset` の 1 バイトをゼロ拡張して Scheme Fixnum（下位 2 ビットタグ 0）として返す。
   - LIR 生成:
     ```scheme
     ((%raw-load-u8)
      (emit-lir! '(%sar %rax 2))
      (emit-lir! (list '%load '%rdx '%rsp si))
      (emit-lir! (list '%load-byte-zx '%rax '%rdx '%rax))
      (emit-lir! '(%shl %rax 2)))
     ```
3. `compiler/primitives.scm`, `compiler/scope.scm`, `lir/129_lir_primitives.scm`, `compiler.scm` にそれぞれ登録。

### 6.3 100% Pure Scheme による探索ルーチンの実装 (`ulisp/lib/posix.scm`)
`posix.scm` に以下の手続きを純粋な Scheme コードとして実装する：

1. `(sys-environ-ptr)`:
   - `(%get-environ-ptr)` の指すポインタスロットから現在の `char **environ` を取得。NULL の場合は 0 を返す。
2. `(%raw-c-strlen ptr)`:
   - `ptr` から 1 バイトずつ `%raw-load-u8` で走査し、`0` に達するまでの長さを計測して Fixnum で返す。
3. `(%raw-c-string->string ptr len)`:
   - 長さ `len` の Scheme 文字列 `(make-string len)` をヒープアロケートし、各バイトを `(integer->char (%raw-load-u8 ptr i))` でセットして返す。
4. `(get-environment-variable name)`:
   - `(if (not (string? name)) (error ...))` または安全ガード。
   - `klen = (string-length name)` を取得。
   - `envp = (sys-environ-ptr)` が 0 の場合は `#f` を返す。
   - ループで各 `entry-ptr` を走査（NULL ポインタに遭遇したら探索終了、`#f` を返却）：
     - `entry-ptr` の先頭 `klen` バイトが `name` の各文字と一致するか比較。
     - `klen` 番目のバイトが ASCII 61 (`'='`) であるか検査。
     - 完全一致した場合、文字列全体の長さ `total-len = (%raw-c-strlen entry-ptr)` を取得し、値の長さ `vlen = (- total-len (+ klen 1))` を算出。
     - `make-string` で値を抽出し、Scheme 文字列として返却。
5. `(get-environment-variables)`:
   - `envp` の全エントリを NULL 終端まで走査。
   - 各エントリについて最初の `'='` のインデックス `eq-idx` を探索。
   - キー文字列 `(substring ... 0 eq-idx)` と値文字列 `(substring ... (+ eq-idx 1) len)` を生成。
   - `(cons key val)` をリストに蓄積し、全エントリ走査後に元の順序を維持して返却。

### 6.4 `(scheme process-context)` SLD 定義の検証
`ulisp/lib/scheme/process-context.sld` において、以下の手続きが正常にエクスポートされていることを確認：
- `command-line`
- `exit`
- `emergency-exit`
- `get-environment-variable`
- `get-environment-variables`

また、未定義であった `emergency-exit` を `(define emergency-exit exit)` として `posix.scm` 内で補完定義する。

### 6.5 仕様準拠ドキュメントの更新
- `ulisp/docs/ref_r7rs_compliance.md`:
  - §1.3 (6.14): `get-environment-variable`, `get-environment-variables` のステータスを **×** から **◎** に更新。
  - §1.4: `(scheme process-context)` の適合率を **約 50%** から **◎ 100%** に更新。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] **プリミティブ実装**: `%get-environ-ptr` および `%raw-load-u8` が LIR および x86-64 / C バックエンドで正常にコード生成されること。
- [x] **低レベルポインタ保持**: ネイティブ x86-64 バイナリおよび C バックエンド実行時に `ulisp_environ` に正しい `char **environ` が格納されること。
- [x] **単一環境変数取得**: `(get-environment-variable "PATH")` 等の標準環境変数が正しい Scheme 文字列として取得できること。
- [x] **未定義変数の挙動**: 存在しない環境変数（例: `"ULISP_NON_EXISTENT_VAR_xyz"`）に対して `#f` を返すこと。
- [x] **空文字列環境変数の挙動**: 空文字列の環境変数（例: `EMPTY=""`）に対して空文字列 `""` を正しく返すこと。
- [x] **全環境変数連想リスト取得**: `(get-environment-variables)` が `(("KEY" . "VAL") ...)` 形式のペアのリストを返し、`assoc` で正常に検索できること。
- [x] **プレフィックス誤一致の防止**: `"PATH"` の検索が `"PATH_SOMETHING"` に誤マッチしないこと。
- [x] **ライブラリ利用可能性**: `(import (scheme process-context))` 経由で上記すべての手続きが問題なくインポート・呼び出し可能であること。
- [x] **テストスイート PASS**: `make test` および新規テスト `ulisp/tests/test_process_context.scm` が 100% パスすること。
- [x] **仕様書整合性**: `ulisp/docs/ref_r7rs_compliance.md` のステータスが 100% (◎) に更新されていること。

---

## 8. 検証・テスト手順 / Verification & Testing Procedures

### 8.1 統合テスト (`ulisp/tests/test_process_context.scm`) の構成
以下の内容を含むテストスクリプトを作成し、検証を行う：
```scheme
(import (scheme base)
        (scheme process-context)
        (scheme write))

(define (assert-true name condition)
  (if condition
      (begin (display "[PASS] ") (display name) (newline))
      (begin (display "[FAIL] ") (display name) (newline) (exit 1))))

;; 1. 既存環境変数の取得テスト
(let ((path (get-environment-variable "PATH")))
  (assert-true "PATH environment variable is string" (string? path))
  (assert-true "PATH environment variable is not empty" (> (string-length path) 0)))

;; 2. 存在しない環境変数のテスト
(assert-true "Non-existent variable returns #f"
             (eq? (get-environment-variable "ULISP_UNKNOWN_VAR_12345") #f))

;; 3. 全環境変数の連想リストテスト
(let ((vars (get-environment-variables)))
  (assert-true "get-environment-variables returns a pair/list" (pair? vars))
  (assert-true "first element is a pair" (pair? (car vars)))
  (assert-true "first element car is string" (string? (caar vars)))
  (assert-true "first element cdr is string" (string? (cdar vars)))
  (let ((path-entry (assoc "PATH" vars)))
    (assert-true "PATH found in alist" (pair? path-entry))
    (assert-true "PATH in alist matches get-environment-variable"
                 (string=? (cdr path-entry) (get-environment-variable "PATH")))))
```

### 8.2 コマンドライン実行手順
```bash
# 1. コンパイラのビルド
cd ulisp && make compiler

# 2. 単体テスト実行 (x86-64 ネイティブ)
./test.sh

# 3. カスタム環境変数付き検証
TEST_ULISP_VAR="hello_ulisp_world" ./bin/ulisp-boot < tests/test_process_context.scm

# 4. 全体品質ゲート確認
make check
```

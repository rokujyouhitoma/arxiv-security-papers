---
ID: 601
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] ネイティブランタイムにおけるシンボル名表示の復元および未捕捉例外メッセージの構造化整形 (ID: 601)

## 1. 概要 / Summary
現在、ULisp ネイティブバイナリ（`bin/ulisp-boot` やフリースタンディング実行系）において、未捕捉例外（`unhandled exception`）が発生した際に、例外オブジェクト内のシンボルが一律 `#<symbol>` とマスクされて出力される。
そのため、例えば `(error "Unbound variable in LIR: car" 'car)` が投げられた場合でも、以下のように表示され、例外種別や引数シンボルが不可視となってしまう：
```text
*** ERROR: unhandled exception: (#<symbol> "Unbound variable in LIR: car" #<symbol>)
```

本 Issue では、コンパイル時静的シンボル Intern テーブル（`*symbol-table*`）をネイティブ ELF の `.rodata` セクション（`__ulisp_symbol_table`）に出力し、`142_backend_x86_freestanding.scm` の出力ルーチン（`ulisp_print_value` / `ulisp_print_symbol`）からシンボル名（ASCII 文字列）を辿って正しく復元出力できるように改修する。
さらに、未捕捉例外ハンドラ（`ulisp_unhandled_exception`）において、例外オブジェクトが `(error-object msg irritants...)` または `(error msg irritants...)` の形式である場合に、エラーメッセージ文字列と引数リスト（`Irritants`）を分離し、人間可読な構造化メッセージとして整形出力する例外フォーマッタを実装する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (Section 2.1: 64ビット Tagged Pointer メモリモデル、Symbol Tag = 2)
  - [R7RS 例外仕様準拠ドキュメント](../../ulisp/docs/r7rs_specification_compliance.md) (Section 6.11: `error`, `error-object?`, `error-object-message`, `error-object-irritants`)
- **関連 Issue**:
  - [Issue 528: 静的シンボル Intern テーブルおよび到達不能関数デッドコード除去 (DCE) による最適化](closed/528-implement-static-symbol-interning-and-dead-code-elimination.md)
  - [Issue 531: 軽量大域脱出ハンドラスタックに基づく R7RS 例外処理機構の実装](closed/531-implement-r7rs-exception-handling-with-handler-stack.md)
  - [Issue 569: x86-64 バックエンドからの GC コレクタおよびフリースタンディングランタイムの物理的パス分離](closed/569-separate-x86-gc-collector-and-freestanding-runtime-passes.md)
  - [Issue 580: runtime.c の完全廃止と低水準 Scheme による完全自己完結ランタイムの実現](closed/580-deprecate-runtime-c-and-implement-pure-scheme-runtime.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm) (`*symbol-table*` の参照用アクセサ・イテレータの提供)
- [x] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (`emit-backend-x86-64` における `.rodata` セクションへの `__ulisp_symbol_table` 出力)
- [x] [ulisp/backend/142_backend_x86_freestanding.scm](../../ulisp/backend/142_backend_x86_freestanding.scm) (`ulisp_print_symbol` の新設、`ulisp_print_value` のシンボル出力改善、および `ulisp_unhandled_exception` の構造化整形)
- [x] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm) (C バックエンドにおけるシンボルテーブル出力およびシンボル名表示の整合)
- [x] [ulisp/runtime/printer.scm](../../ulisp/runtime/printer.scm) (Pure Scheme プリンタにおけるシンボル印字の整合)
- [x] [ulisp/tests/passes/test_142_backend_x86_freestanding.scm](../../ulisp/tests/passes/test_142_backend_x86_freestanding.scm) (`ulisp_print_symbol` および例外整形の単体テスト)
- [x] [ulisp/tests/passes/test_140_backend_x86.scm](../../ulisp/tests/passes/test_140_backend_x86.scm) (`__ulisp_symbol_table` メタデータ出力テスト)
- [x] [ulisp/tests/test_exceptions.scm](../../ulisp/tests/test_exceptions.scm) (未捕捉例外メッセージ整形出力の結合テスト)

---

## 4. 脅威モデルとセキュリティ・堅牢性要件 / Threat Model & Security Requirements
1. **不正メモリアクセス・バッファオーバーラン防止 (CWE-119 / CWE-125)**:
   - `ulisp_print_symbol` において `__ulisp_symbol_table` を走査する際、テーブル長（`count`）による厳格な境界チェックを実施し、未登録シンボルや不正ポインタによる SEGV を防ぐ。
   - シンボル名文字列は null-terminated（`.asciz`）として静的領域に配置し、`ulisp_emit_str` による出力境界を保証する。
2. **未捕捉例外オブジェクトの型安全検証 (CWE-843 Type Confusion)**:
   - `ulisp_unhandled_exception` において例外オブジェクトを解釈する際、`car` や `cdr` を直接参照する前に、必ずペアタグ（下位3bit = `1`）および空リスト（`63`）のチェックを実施する。
   - 非リスト（数値、真偽値、不正ポインタ等）が `raise` された場合でも、安全にフォールバックして元の値をそのまま印字し、クラッシュを物理遮断する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/601-restore-symbol-printing-and-format-unhandled-exceptions`

### Step 1: コンパイル時静的シンボルメタデータテーブルの出力 (`140_backend_x86_64.scm`)
1. `ulisp/compiler/helpers.scm` において、`*symbol-table*` の全エントリ（`(list sym id str)`）を取得可能なヘルパー関数（`get-all-symbols`）を確認・整備。
2. `ulisp/backend/140_backend_x86_64.scm` の `emit-backend-x86-64`（`.rodata` 出力部）において、`*symbol-table*` に登録された各シンボルの ASCII 文字列ラベル（`.L_sym_str_<id>`）と、以下の構造を持つシンボルメタデータテーブルを出力：
   ```x86asm
       .section .rodata
       .align 8
       .globl __ulisp_symbol_table
   __ulisp_symbol_table:
       .quad <symbol_count>
       ;; Entry 1:
       .quad <symbol_id_1>
       .quad .L_sym_str_1
       ;; Entry 2:
       .quad <symbol_id_2>
       .quad .L_sym_str_2
       ...
   ```
3. 各シンボルの名前文字列（`asciz`）を `.rodata` セクション内に配置。

### Step 2: フリースタンディングネイティブプリンタのシンボル名復元 (`142_backend_x86_freestanding.scm`)
1. `ulisp_print_symbol` アセンブリ関数の新規実装：
   - 引数: `rdi` = tagged symbol (`id`)
   - `lea rsi, [rip + __ulisp_symbol_table]` からテーブル長 `rcx = [rsi]` をロード。
   - `rcx` 回のループで `[rsi + 8 + i * 16]`（ID）と `rdi` を比較：
     - 一致した場合: `[rsi + 16 + i * 16]`（文字列アドレス）を `rdi` に設定し、`ulisp_emit_str` を呼び出して復元文字列を出力。
     - 不一致で終端に達した場合: フォールバックとして `#<symbol>` または `#<symbol-` + ID + `>` を出力。
2. `ulisp_print_value` のシンボルタグ判定（tag 2: `cmp rax, 2`）において、`.L_str_symbol` の固定出力から `call ulisp_print_symbol` へ置き換え。

### Step 3: 未捕捉例外フォーマッタの実装 (`142_backend_x86_freestanding.scm`)
1. `ulisp_unhandled_exception` を拡張：
   - 例外オブジェクト `rdi` を検査。
   - `(val & 7) == 1`（ペア）の場合、先頭要素（`car` = `[rdi - 1]`）を取得。
   - `car` が `'error-object` または `'error` のシンボル ID（コンパイル時 intern ID と比較、または `ulisp_print_symbol` 同様の解決）と合致するか判定。
   - 合致した場合（構造化エラー）:
     1. `"*** ERROR: "` を標準エラー出力に出力（`ulisp_emit_str`）。
     2. `cadr`（メッセージ）を取得：
        - 文字列（`(val & 7) == 3`）の場合は引用符なしで直接テキストを出力（`ulisp_write_string`）。
        - それ以外の場合は `ulisp_print_value` を呼び出し。
     3. 改行（`\n`）を出力。
     4. `cddr`（引数リスト `irritants`）を取得：
        - 空リスト（`63`）でなければ、`"    Irritants: "` をインデント出力。
        - 引数リストの各要素を空白区切りで `ulisp_print_value` により出力。
        - 改行を出力。
   - 合致しない場合（非構造化例外、単一の値など）:
     1. `"*** ERROR: unhandled exception: "` を出力。
     2. `ulisp_print_value` で値そのものを印字。
     3. 改行を出力。
2. `ulisp_flush` を実行し、`syscall exit(1)` で安全に終了。

### Step 4: C バックエンドおよび Pure Scheme プリンタの整合
1. `ulisp/backend/160_backend_c.scm`: C バックエンドでも静的シンボル配列を出力し、`SYMBOL_TAG` 判定時にシンボル名を検索して印字するよう更新。
2. `ulisp/runtime/printer.scm`: Pure Scheme ランタイムの `runtime-print-value-raw` において、可能であればシンボル名を出力できるように整合。

### Step 5: テストケースの追加と検証
1. `ulisp/tests/passes/test_142_backend_x86_freestanding.scm`:
   - `ulisp_print_symbol` および `ulisp_unhandled_exception` のアセンブリ生成検証テストを追加。
2. `ulisp/tests/passes/test_140_backend_x86.scm`:
   - `__ulisp_symbol_table` が正しく `.rodata` に出力されることを検証するテストを追加。
3. `ulisp/tests/test_exceptions.scm` または `ulisp/test.sh`:
   - `(error "test-error" 'foo 'bar)` 実行時の標準エラー出力文字列のテストを追加。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] ネイティブ x86-64 実行系において、シンボルが `#<symbol>` ではなく実際のシンボル名（例: `car`, `error-object`, `foo`）として正確に出力されること。
- [x] `(error "msg" 'arg1 'arg2)` の未捕捉例外発生時に、以下の形式で標準エラー出力に整形表示されること：
  ```text
  *** ERROR: msg
      Irritants: arg1 arg2
  ```
- [x] 不正・未知のシンボルや非構造化例外が渡された場合でも、SEGV せずに安全なフォールバック出力が行われること。
- [x] `make -C ulisp compiler.scm` でコンパイラが正常に再生成されること。
- [x] `make -C ulisp test_passes` および `bash ulisp/test.sh` が 100% PASS すること。

---

## 7. 実装・検証結果サマリー / Resolution Summary
1. **静的シンボル Intern テーブルの出力 (`140_backend_x86_64.scm`, `160_backend_c.scm`)**:
   - `ulisp/compiler/helpers.scm` に `get-all-symbols` を追加し、全シンボル ID と ASCII 文字列を `.rodata` セクションの `__ulisp_symbol_table` / `ulisp_symbol_table` として出力。
2. **シンボル名復元と未捕捉例外フォーマッタ (`142_backend_x86_freestanding.scm`, `160_backend_c.scm`)**:
   - `ulisp_find_symbol_str` および `ulisp_print_symbol` を新設し、タグ 2 のシンボルを ASCII 文字列として印字。
   - `ulisp_unhandled_exception` を実装し、`(error-object msg irritants...)` または `(error msg irritants...)` に対して `*** ERROR: <msg>` および `    Irritants: <irritants>` 形式の構造化整形出力を実現。
3. **付随する潜在バグの修正**:
   - `140_backend_x86_64.scm` における `%disp` オペランドのレジスタオフセット修飾対応（`mov [r12 + rdx], r10`）。
   - `gc_state` 構造体の mature_to / mature_size オフセット整合およびプロファイルパラメータ整合。
4. **全品質ゲート通過**:
   - `make -C ulisp test_passes`: 35 パス全 147 単体テスト PASS。
   - `make -C ulisp test_exceptions`: 全 R7RS 例外テスト PASS。
   - `make -C ulisp test_gc_profile`: 全 GC プロファイルテスト PASS。
   - `make -C ulisp test_c`: C バックエンド全 139 テスト PASS。
   - `bash ulisp/test.sh`: 全フェーズ完全 PASS。
   - `make -C ulisp bootstrap_verify`: 3 段階ブートストラップ固定点（bit-for-bit identical）確認完了。
   - `make py_compile static_analysis`: 0 エラー PASS。

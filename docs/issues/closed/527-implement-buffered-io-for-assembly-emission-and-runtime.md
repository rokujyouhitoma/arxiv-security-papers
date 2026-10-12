---
ID: 527
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] アセンブリ出力およびランタイムの 4KB ブロック I/O バッファリング化によるシステムコール削減 (ID: 527)

## 1. 概要 / Summary
ULisp コンパイラ（`compiler.scm`）およびネイティブベアメタルランタイム（`ulisp_write_char`）において、文字出力時に 1バイトごとに Linux `sys_write` システムコール（および ILisp における行ごとの `flush`）を発行していることが、Stage 2 以降の自己ホスティングブートストラップ（2.9MB のアセンブリ出力で約 290 万回のシステムコール発生）および ILisp コンパイル処理における致命的な性能ボトルネックとなっている。
本 Issue では、ランタイムおよびアセンブリ出力エンジンに 4KB〜64KB のブロック I/O バッファリング機構を導入し、システムコール発行回数を数百万回から数百〜数千回へ削減することで、コンパイルおよびブートストラップ処理を根本から高速化する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: 
  - `ulisp/compiler.scm` (`ulisp_write_char`, `emit-x86-64`)
  - `ulisp/lib/printer.scm` (`display-string`, `write-char`)
  - `ulisp/bootstrap.sh` (Stage 2: `scheme-stage1 ulisp_core.scm > stage2.s`)
  - Issue #516 (ベアメタル Linux ランタイム %syscall・_start 実装)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm)
- [x] [ulisp/passes/00_helpers.scm](../../ulisp/passes/00_helpers.scm)
- [x] [ulisp/passes/06_lir.scm](../../ulisp/passes/06_lir.scm)
- [x] [ulisp/passes/07_backend_x86_64.scm](../../ulisp/passes/07_backend_x86_64.scm)
- [x] [ulisp/lib/printer.scm](../../ulisp/lib/printer.scm)
- [x] [ulisp/lib/posix.scm](../../ulisp/lib/posix.scm)
- [x] [ulisp/runtime.c](../../ulisp/runtime.c)
- [x] [ilisp/port.py](../../ilisp/port.py)
- [x] [ilisp/backend/ulisp_codegen/compiler.py](../../ilisp/backend/ulisp_codegen/compiler.py)
- [x] [tests/test_bare_metal_ulisp.py](../../tests/test_bare_metal_ulisp.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/527-implement-buffered-io-for-assembly-emission-and-runtime`

1. **ベアメタルランタイムの 4KB 出力バッファ実装**:
   - `ulisp_out_buf` (4096バイト) および `ulisp_out_buf_len` を `.bss` に配置。
   - `ulisp_emit_byte` / `ulisp_write_char` / `ulisp_emit_str` / `ulisp_write_string` を実装し、4KB 満杯時または明示的 `ulisp_flush` 時のみ `sys_write` を発行。
   - プロセス終了時（`_start` の `.L_start_exit`）に `ulisp_flush` を発行。
2. **コンパイラアセンブリ出力 (`07_backend_x86_64.scm`) のバッチ文字列化**:
   - `(define (emit line) (write-string line) (write-char #\newline))` に刷新し、1文字ループを回避。
3. **ILisp 側の `display` 自動 flush 抑制**:
   - `ilisp/port.py` の `StandardOutputPort` / `FileOutputPort` に 4KB バッファリングを導入し、行ごとの過剰な `flush()` を廃止。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ulisp_write_char` が 4KB バッファリングされ、1文字ごとの `sys_write` が解消されること。
- [x] `stage1.s` / `stage2.s` 生成時のシステムコール実行回数が 290万回から数千回以下（strace 等で検証）に削減されること（`tests/test_bare_metal_ulisp.py::test_buffered_io_syscall_reduction` で 10,000 文字出力時の `write` システムコール回数が 3 回であることを strace 自動検証）。
- [x] Stage 2 のアセンブリ出力時間が大幅に短縮され、ハングアップやタイムアウトなしに完了すること（`stage2.s` 3.0MB の全出力処理を含めシステム CPU 時間がわずか 1.8 秒）。
- [x] 既存の全 nanopass テスト (127/127 PASS)、AOT ELF テスト (18/18 PASS)、ベアメタルテスト (4/4 PASS) が 100% PASS すること。


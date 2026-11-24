---
ID: 953
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] x86-64 即値 `mov` の短縮符号化（`mov r32, imm32` / `xor r32, r32`）を `140` と `144a` の双方に適用 (ID: 953)

## 1. 概要 / Summary

`ulisp-boot`（#952 後・`.text` 9,247,973 B）を `objdump -d -M intel` で解析した結果、非負 32bit 即値のロードおよび 64bit 自己 `xor` で合計 300 KB 超の冗長命令が発生している。

| パターン | 命令長 | `ulisp-boot` 実測数 | 短縮後の命令長 | 期待削減量 |
|---|---:|---:|---|---:|
| 非負 32bit 即値 `mov r64, imm32` (`48/49 C7 C0..C7`, `1 <= imm < 2^32`) | 7 B | 156,783 | `mov r32, imm32`（低 8 レジスタ 5 B / `r8-r15` 6 B） | 約 300 KB |
| 即値 0 `mov rax, 0x0`（`140` `%apply` L1924 の `%raw-asm` 由来） | 7 B | 32 | `xor eax, eax`（2 B） | 約 0.16 KB |
| 負の 32bit 符号拡張即値（`-2^31 <= imm < 0`） | 7 B | 328 | 変更不可（7 B `REX.W C7 /0` 必須） | 0 B |
| 低 8 レジスタ 64bit 自己 `xor r64, r64` (`48 31 C0..FF`) | 3 B | 7,180 | `xor r32, r32`（2 B `31 C0..FF`） | 約 7 KB |

合計 **157,143 箇所**の 7 バイト `mov r64, imm32` のうち 99.8%（**156,815 箇所**）が非負であり、32bit レジスタ書き込みの上位 32bit 自動ゼロ拡張仕様を利用して短縮できる。

### 重要な実装上の注意点

1. **`140` と `144a` の両経路を直す必要がある**:
   - `ulisp-boot` / `ulisp-cc` は [140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm) が出力する GAS アセンブリを GNU `as --64` で組み立てている。GNU `as` は `mov rax, 42` を 7 バイト `48 c7 c0 2a 00 00 00`、`xor rax, rax` を 3 バイト `48 31 c0` にするため（実機確認済み）、`140` 側で `mov eax, 42` / `xor eax, eax` を出力しない限り `ulisp-boot` / `ulisp-cc` は縮まない。
   - 一方、[144a_x86_assembler.scm](../../../ulisp/backend/144a_x86_assembler.scm) L1275-1282 は `--target-elf` / `-c` / `--as` / C99 / Lua / JIT 向けの内部アセンブラであり、ここで 5/6 バイト符号化（`B8+rd imm32` / `41 B8+rd imm32`）を選ぶことで Lua/C99 生成 ELF も同時に縮小する。
2. **フラグ生存条件**: `xor r32, r32` は RFLAGS を破壊するため、[143_backend_x86_peephole.scm](../../../ulisp/backend/143_backend_x86_peephole.scm) の `rule-x86-zero-xor` は直後にフラグを読む命令（`jcc` / `set` / `cmov`）が続く場合には適用を抑制する（既存の `x86-asm-reads-flags?` を流用）。`mov r32, imm32` 自体はフラグを変更しないため常に安全である。
3. **既存ユニットテストとの整合**: [test_140_backend_x86_64.scm](../../../ulisp/tests/passes/test_140_backend_x86_64.scm)、[test_143_backend_x86_peephole.scm](../../../ulisp/tests/passes/test_143_backend_x86_peephole.scm)、[test_144a_x86_assembler.scm](../../../ulisp/tests/passes/test_144a_x86_assembler.scm) 等は機械語レベルと AST レベルの期待値を確認し、文字列比較テスト（例: `test_jit_buffer.scm` L134 `"    mov rax, 255"`、L140 `%raw-asm "    xor r10, r10"` の明示テスト）との衝突がない形で適用する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](../945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（Lua 5.4.7 ビルドプロファイル・計測基盤を共有）
  - [Issue #951](951-disable-safepoint-injection-in-single-threaded-compiler-modules.md)
  - [Issue #952](952-strip-release-binaries-and-split-debug-symbols.md)（本施策のベースライン）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm)
  - `emit-x86-asm-inst`（L2559-2635 付近）: `mov` の出力先が 64bit GP レジスタかつソースが非負 32bit 整数（`0 <= val <= 4294967295`、`quotient` による 30bit 安全範囲判定）のとき `reg32->str` で出力する（例: `mov eax, 42`、`mov r10d, 42`）。また自己 `xor`（出力先とソースが同一 64bit GP レジスタ）のとき両方を `reg32->str` で出力する（例: `xor eax, eax`、`xor r10d, r10d`）。
  - `%apply` / `%capture-cc` 等内の `%raw-asm`（L1268, L1860, L1924, L1934, L1948, L1965, L1985, L2004）: `"    mov rax, 0"` を `"    xor eax, eax"` に、`"    mov rax, 4/8/12/16"` 等を `"    mov eax, ..."` に短縮する（L1766 `%direct-call` の `"    xor r10, r10"` は `test_140_backend_x86_64.scm` L130 の互換性のため据え置き）。
- [x] [143_backend_x86_peephole.scm](../../../ulisp/backend/143_backend_x86_peephole.scm)
  - `x86-asm-reads-flags?` を `rule-x86-zero-xor` より前へ移動し、`rule-x86-zero-xor` に `(or (null? rest) (not (x86-asm-reads-flags? (car rest))))` ガードを追加する。
- [x] [144a_x86_assembler.scm](../../../ulisp/backend/144a_x86_assembler.scm)
  - `mov reg, imm` 符号化部（L1275-1290）: `(= sz 8)` の分岐に非負 32bit 即値（`0 <= val < 2^32`、`>= val 0` かつ `(<= (quotient val 4) 1073741823)`）の節を先頭に追加し、`(= sz 4)` と同じ 5/6 バイト符号化（`B8+rd imm32`、拡張レジスタのみ `REX.B = 0x41` 付与）を生成する。負の 32bit 符号拡張範囲は 7 バイト `REX.W C7 /0 imm32`、それ以外は 10 バイト `REX.W B8+rd imm64` を維持する。
- [x] [test_140_backend_x86_64.scm](../../../ulisp/tests/passes/test_140_backend_x86_64.scm)
  - GAS テキスト出力の単体テスト追加（`mov eax, 42`、`mov rax, -1` の 64bit 維持、64bit 大即値の維持、`xor eax, eax` 出力）。
- [x] [test_143_backend_x86_peephole.scm](../../../ulisp/tests/passes/test_143_backend_x86_peephole.scm)
  - `rule-x86-zero-xor` が直後の `jcc` / `set` 前で発火しないことを検証するテスト追加。
- [x] [test_144a_x86_assembler.scm](../../../ulisp/tests/passes/test_144a_x86_assembler.scm)
  - `mov rax, 42`（5 バイト）、`mov r10, 42`（6 バイト `41 BA`）、`mov rax, -1`（7 バイト `48 C7 C0`）の機械語バイト列検証テスト追加。
- [x] [bin/ulisp-boot](../../../ulisp/bin/ulisp-boot)
  - 3 段モジュラーブートストラップ後の更新済みシードバイナリ。

### セキュリティ・正当性観点
- 32bit レジスタ書き込み時の上位 32bit ゼロ拡張は x86-64 ISA の不変仕様であり、非負値 `0 <= val < 2^32` では 64bit 値として完全に等価。負数（MSB=1）に誤って適用すると符号拡張されず上位 32bit が 0 になるため、`>= val 0` の判定を厳密に行う（`32bit ULisp fixnum/tag` が非負領域で安全に収まる範囲も確認する）。
- 30bit 固定長整数環境・ILisp・ULisp 自前整数系でのオーバーフロー回避のため、`4294967295` リテラル直接比較の代わりに `(and (>= val 0) (<= (quotient val 4) 1073741823))` 等を使用する（`144a` L1276 と同じ方式）。

---

## 4. 実装方針 / Implementation Plan

Target Branch: `perf/953-short-immediate-mov-encoding`

1. **ベースライン確認**（`main` b867aca70）:
   - `bin/ulisp-boot`（10,824,800 B / `.text` 9,247,973 B / 7B `mov` 157,143 件 / 非負 156,815 件 / 3B 自己 `xor` 7,180 件）、`bin/ulisp-cc`（13,465,560 B / `.text` 11,434,789 B）を記録。
2. **`143_backend_x86_peephole.scm` のフラグ生存ガード追加**:
   - `x86-asm-reads-flags?` を `rule-x86-zero-xor` の手前に移動し、フラグ読み取り命令の直前では `(mov reg 0) -> (xor reg reg)` を行わないようにする。
3. **`140_backend_x86_64.scm` の 32bit 即値 mov / self-xor 出力対応**:
   - `emit-asm-instruction` の `(mov)` で出力先が 64bit GP レジスタ（`x86-gp64-reg?` 等）かつソースが非負 32bit 整数（`(%imm n)` または整数 `n`）のとき、`reg32->str` を使って `"    mov eax, 42"` の形式で出力する。
   - `emit-asm-instruction` の `(xor)` で出力先・ソースが同一の 64bit GP レジスタのとき `reg32->str` を使って `"    xor eax, eax"` の形式で出力する。
   - `%apply` L1924/1934/1948/1965/1985 等の `%raw-asm` 即値ロードも `xor eax, eax` / `mov eax, imm` に揃える。
4. **`144a_x86_assembler.scm` の 5/6 バイト符号化対応**:
   - `mov reg, imm`（L1275-1286）に `(= sz 8)` かつ非負 32bit 整数の分岐を追加し、`(= sz 4)` と同じ `B8+rd imm32`（拡張レジスタは `41 B8+rd imm32`）を出力する。
5. **ユニットテスト追加**:
   - `test_140_backend_x86_64.scm` / `test_143_backend_x86_peephole.scm` / `test_144a_x86_assembler.scm` に上記テストケースを追加する。
6. **モジュラー 3 段ブートストラップ・`ulisp-cc` 再リンク・統合検証**:
   - `make -C ulisp bootstrap_verify_modular`（5 モジュール stage2 == stage3 不動点一致）および `make -C ulisp ulisp-cc` を実行する。
   - Note: `ulisp-boot` の `.text` が大きく縮むため、`stage1`（旧シード）と `stage2`（新コード出力）は当然変わり、`stage2 == stage3` が一致する。`bootstrap_verify_modular` が通れば不動点収束が確認できる。
   - `make -C ulisp test_ulisp_cc_native`、`test_differential_elf`、`test_builtin_as`、`test_passes`、`test_jit_buffer`、`test_c99_gnu_ext` を実行する。
7. **事後計測と品質ゲート**:
   - `objdump` で 7 バイト非負 `mov r64, imm32` と 3 バイト自己 `xor` の残数、`.text` / ファイルサイズ、自己コンパイル 5 回中央値、Lua 5.4.7 ビルド時間を計測し「6. 計測結果」に記録する。
   - `make format check_format static_analysis py_compile test` および `verify-quality-gates` を全 PASS させてクローズ・マージする。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `objdump` で `ulisp-boot` / `ulisp-cc` の 7 バイト非負 `mov r64, imm32`（基準 156,815 件）が 90% 以上削減されている（**−99.80%**）
- [x] `ulisp-boot` の `.text` が約 250 KB 以上削減されている（**−378,112 B = −369.3 KB**）
- [x] `144a` 自前アセンブラで `mov rax, 42` が 5 バイト、`mov r10, 42` が 6 バイトで生成されることを単体テストで検証済み
- [x] `rule-x86-zero-xor` がフラグ消費命令の直前で発火しないことを単体テストで検証済み
- [x] Lua 5.4.7 ビルド（`test_ulisp_cc_native`）、`test_differential_elf`、`test_builtin_as`、C99 テストが PASS
- [x] `make -C ulisp bootstrap_verify_modular` で 5 モジュールすべて stage2 == stage3 の自己コンパイル不動点（SHA-256 一致）を維持
- [x] 施策前後の計測（自己コンパイル時間中央値 5 回・ELF/`.text` サイズ・`objdump` 命令数）を本 Issue「6. 計測結果」に記録
- [x] `make format` / `make check_format` / `make static_analysis` / `make py_compile` / `make test` が全 PASS
- [x] `verify-quality-gates` 全 PASS（相対リンクのみ・絶対パス 0 件）

---

## 6. 計測結果 / Measurements

ベースライン（#952 適用直後、`main` b867aca70、Linux x86-64）と変更後（`ulisp_stdlib.o` 含む全モジュール再構築後）を比較。

| 指標 | 変更前 (#952後) | 変更後 | 差分 |
|---|---:|---:|---:|
| `ulisp-boot` 7 バイト非負 `mov r64, imm32` | 156,815 (うち 0 は 32) | 308 (うち 0 は 0) | **−156,507 (−99.80%)** |
| `ulisp-boot` 3 バイト低 8 レジスタ自己 `xor` | 7,180 | 86 | **−7,094 (−98.80%)** |
| `ulisp-boot` `.text` | 9,247,973 B | 8,869,861 B | **−378,112 B (−369.3 KB)** |
| `ulisp-boot` ファイルサイズ | 10,824,800 B | 10,452,272 B | **−372,528 B (−363.8 KB)** |
| `ulisp-cc` `.text` | 11,434,789 B | 10,964,469 B | **−470,320 B (−459.3 KB)** |
| `ulisp-cc` ファイルサイズ | 13,465,560 B | 12,994,728 B | **−470,832 B (−459.8 KB)** |
| 自己コンパイル時間（5 モジュール合計・5 回中央値） | 13.60 s | 13.08 s | **−0.52 s (−3.8%)** |

- 自己コンパイル時間詳細（5 回交互実測）: 旧 `13.82 / 13.78 / 13.60 / 13.43 / 13.04 s`（中央値 `13.60 s`）、新 `13.80 / 13.67 / 12.97 / 13.08 / 13.03 s`（中央値 `13.08 s`）。
- 残存 7 バイト非負 `mov r64, imm32` 308 件（`neg`: 328 件不変）および 3 バイト自己 `xor` 86 件は `140` 以外のハンドアセンブリ（`%raw-asm` / startup / entry 等）であり、`ulisp-cc` では計 458 件残存。
- テスト: `make -C ulisp test_passes`（858/858 Nanopass + 165/165 Pass 1-7 PASS）、`make -C ulisp test_144a`（6/6 PASS）、`make -C ulisp test_builtin_as`（6/6 PASS）、`make -C ulisp test_differential_elf`（13/13 PASS）、`make -C ulisp test_jit_buffer`（27/27 PASS）、`make -C ulisp bootstrap_verify_modular`（5 モジュール不動点 PASS）、`make -C ulisp test_ulisp_cc_native`（C99/musl/Lua 33 TU SHA-256 パリティ + Lua 公式 `all.lua` 全 PASS）。

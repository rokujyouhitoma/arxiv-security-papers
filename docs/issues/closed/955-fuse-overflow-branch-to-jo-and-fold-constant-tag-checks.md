# Issue #955: 算術 fast path の短縮：オーバーフロー分岐の `jo` 融合と定数オペランドのタグ検査畳み込み

- **ステータス**: Closed
- **カテゴリ**: Performance / Code Size / Codegen Optimization (`L_lir` / `L_asm_x86`)
- **優先度**: High
- **作成日**: 2026-11-25
- **完了日**: 2026-11-25
- **担当**: Project Manager (PM), IT Specialist (PLC), Software Development (SWD), Systems Architect, Software Quality Assurance Specialist

---

## 1. 背景と目的 (Context & Objective)

`#951`（シングルスレッドコンパイラモジュールのセーフポイント注入停止）、`#952`（Release バイナリの `strip` / debuginfo 分離）、`#953`（32-bit 即値 `mov` 短縮）、`#954`（`.p2align` の関数入口・ループ先頭限定）の完了後も、`main` (`551d751e8`) のコンパイラ生成バイナリには固定長タグ付き算術 fast path の冗長命令が大量に残存していた。

`ulisp-boot`（`.text` `8,126,261 B` / ファイル `9,707,024 B`）および `ulisp-cc`（`.text` `10,053,989 B` / ファイル `12,089,736 B`）の生成アセンブリ・逆アセンブリを計測したところ、以下の 3 点が主要な冗長命令クラスターとして観測された。

1. **オーバーフロー分岐の `seto` + `movzx` + `cmp 0` + `jne` 冗長列** (`ulisp-boot`: **3,762** 箇所, `ulisp-cc`: **5,041** 箇所)
   - LIR の `%add-overflow` / `%sub-overflow` / `%mul-overflow` は [140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm) にて常に `seto dl` + `movzx rdx, dl`（LIR 上の `0`/`1` 値化）へ展開され、直後に `(cmp ovf 0)` + `(jcc neq slow)` が続くため、フラグレジスタ (`OF`) を 1 度 `dl` に退避してから再度 `cmp rdx, 0` でテストして `jne` していた。
   - **重要制約**: [test_lir_overflow_and_unsigned.scm](../../../ulisp/tests/test_lir_overflow_and_unsigned.scm) が `lower-lir-instruction` 単体呼び出し時の `seto dl` 出力や LIR の `%*-overflow` 命令を直接検証しており、[150_backend_aarch64.scm](../../../ulisp/backend/150_backend_aarch64.scm) や C バックエンド・LIR インタプリタ・LIR differential fuzz も `%*-overflow` を前提としている。したがって LIR 命令セットおよび Pass 140 単体 lowering は維持しつつ、**Pass 143 (`L_asm_x86` ピープホール最適化)** にて `seto dl` -> `movzx rdx, dl` -> `cmp rdx, 0` -> `jne slow` を単一の `jo slow`（および逆極性 `je` -> `jno`）へ融合する設計が最も安全かつ効果的である。
   - あわせて [144a_x86_assembler.scm](../../../ulisp/backend/144a_x86_assembler.scm) の `*x86-mnem-str-map*` / `canonical-mnem` / `jcc` エンコーダに `jo` (`0x70` / `0x0F 0x80`) および `jno` (`0x71` / `0x0F 0x81`) を追加し、self-hosted ELF / `-c` / `--as` / JIT 経路の整合性を確保した。

2. **タグマスク後の冗長 `cmp rdx, 0`** (`ulisp-boot`: `and rdx, 0x3` が **8,856** 箇所)
   - タグ判定で `and rdx, 0x3` を行った直後に `cmp rdx, 0` + `je`/`jne` を生成するパターンが多数存在する。`and` 命令自体が `ZF` を正しく更新するため、`cmp rdx, 0` は完全に冗長であり、Pass 143 ピープホールで `and <reg>, <imm>` 直後の `(cmp <reg> 0)`（ZF 系分岐または `sete`/`setne al` 直前）を安全条件付きで除去した。

3. **定数 fixnum オペランドに対する冗長なタグ検査** (`ulisp-boot`: 二項タグ検査 `or rdx, QWORD PTR [rsp - N]` が **8,843** 箇所、うち直前に `mov eax, 0x...` を伴う既知 fixnum 定数オペランドが **4,511** 箇所)
   - [129_lir_primitives.scm](../../../ulisp/lir/129_lir_primitives.scm) および [128_lir_branch_fusion.scm](../../../ulisp/lir/128_lir_branch_fusion.scm) の二項算術 (`+`, `-`, `*`, `quotient`, `modulo`, `bitwise-and`, `bitwise-ior` 等) および融合比較分岐 (`(< x 1)`, `(= n 0)` 等) について、コンパイル時定数 fixnum 判定ヘルパー `lir-known-fixnum-const?` と共通タグ検査生成関数 `emit-lir-bin-tag-check!` を導入し、片側定数時は変数側のみ `bit-and reg 3`（`%bit-or` 省略）、両側定数時はタグ検査自体を完全に省略した。

---

## 2. 依存関係と関連 Issue (Dependencies & Related Issues)

- **前提・完了済み関連 Issue**:
  - [951-disable-safepoint-injection-in-single-threaded-compiler-modules.md](951-disable-safepoint-injection-in-single-threaded-compiler-modules.md): セーフポイント除去（ベースライン構築）
  - [952-strip-release-binaries-and-split-debug-symbols.md](952-strip-release-binaries-and-split-debug-symbols.md): Release バイナリの `strip` とサイズ可視化基盤
  - [953-shorten-immediate-mov-encoding-in-x86-backend-and-assembler.md](953-shorten-immediate-mov-encoding-in-x86-backend-and-assembler.md): `144a_x86_assembler.scm` の短縮エンコード対応
  - [954-restrict-p2align-to-loop-headers-and-function-entries-in-scheme-codegen.md](954-restrict-p2align-to-loop-headers-and-function-entries-in-scheme-codegen.md): `.p2align` 削減（`main` ベースライン `551d751e8`）
  - 関連過去最適化: `#935`, `#945`
- **後続最適化**:
  - 生成命令数・I-cache フットプリント削減により、関数インライン化やレジスタ割付改善の効果を増幅する。

---

## 3. 影響範囲と対象ファイル (Scope & Target Files)

### 変更対象ファイル
- [144a_x86_assembler.scm](../../../ulisp/backend/144a_x86_assembler.scm): `*x86-mnem-str-map*`, `canonical-mnem`, `jcc` 命令エンコーダへの `jo` (`0x70` / `0x0F 0x80`) / `jno` (`0x71` / `0x0F 0x81`) 追加
- [143_backend_x86_peephole.scm](../../../ulisp/backend/143_backend_x86_peephole.scm):
  - `rule-x86-overflow-branch-fuse`: `(%raw-asm "    seto dl")` + `(%raw-asm "    movzx rdx, dl")` + `(cmp rdx 0)` + `(jcc jne/jnz/je/jz lbl)` を `(jcc jo/jno lbl)` へ融合
  - `rule-x86-and-cmp-zero-branch-fuse`: `(and reg mask)` + `(cmp reg 0)` + `(jcc je/jne/jz/jnz lbl)`（または `sete`/`setne al`）から冗長 `(cmp reg 0)` を除去（`jl`/`jg` 等は除外）
- [128_lir_branch_fusion.scm](../../../ulisp/lir/128_lir_branch_fusion.scm): `lir-known-fixnum-const?`, `emit-lir-bin-tag-check!` 追加、および `lir-compile-fused-cmp-cond` への適用
- [129_lir_primitives.scm](../../../ulisp/lir/129_lir_primitives.scm): `+`, `-`, `*`, `modulo`, `quotient`, `bitwise-and`, `bitwise-ior`, および `lir-compile-relop` への `emit-lir-bin-tag-check!` 適用
- テスト・成果物:
  - [test_lir_overflow_and_unsigned.scm](../../../ulisp/tests/test_lir_overflow_and_unsigned.scm), [test_128_lir_branch_fusion.scm](../../../ulisp/tests/passes/test_128_lir_branch_fusion.scm), [test_129_lir_primitives.scm](../../../ulisp/tests/passes/test_129_lir_primitives.scm)
  - [test_143_backend_x86_peephole.scm](../../../ulisp/tests/passes/test_143_backend_x86_peephole.scm), [test_144a_x86_assembler.scm](../../../ulisp/tests/passes/test_144a_x86_assembler.scm)
  - `ulisp/compiler.scm`, `ulisp/bin/ulisp-boot`, `ulisp/bin/ulisp-boot.debug`, `ulisp/bin/ulisp-modular`, `ulisp/bin/ulisp-modular.debug`, `ulisp/bin/ulisp-cc`, `ulisp/bin/ulisp-cc.debug`

### 参照のみ（非変更・契約確認対象）
- [140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm): `jcc` の `'jo` / `'jno` 出力対応、`%*-overflow` の `seto dl` + `movzx rdx, dl` 出力維持を確認
- [150_backend_aarch64.scm](../../../ulisp/backend/150_backend_aarch64.scm): AArch64 `%*-overflow` 実装への影響なしを確認

---

## 4. 実装計画 (Implementation Plan)

- **作業ブランチ**: `perf/955-fuse-overflow-branch-and-fold-tag-checks`

1. **Step 1: `144a_x86_assembler.scm` への `jo` / `jno` サポート追加** — 完了
2. **Step 2: `143_backend_x86_peephole.scm` でのピープホール融合規則実装** — 完了
3. **Step 3: `129_lir_primitives.scm` & `128_lir_branch_fusion.scm` での定数 fixnum タグ検査畳み込み** — 完了
4. **Step 4: 再ブートストラップ (`ulisp_stdlib.o` + `ulisp-boot` + `ulisp-cc`) と品質ゲート検証** — 完了（3-stage modular bootstrap 5 モジュール完全不動点収束）

---

## 5. 完了条件 (Definition of Done / Acceptance Criteria)

- [x] `144a_x86_assembler.scm` が `jo` / `jno`（short/near 分岐とも）を正しくエンコードでき、単体テスト (`make test_144a` 7/7) が PASS する。
- [x] `143_backend_x86_peephole.scm` により `ulisp-boot` 内の `seto dl` -> `movzx rdx, dl` -> `cmp rdx, 0` -> `jne` 冗長列（ベースライン 3,762 箇所）が `jo` へ融合・全廃（0 箇所、`jo` = 3,768）され、`and rdx, 3` 直後の冗長 `cmp rdx, 0` も 0 箇所へ除去される。
- [x] `129_lir_primitives.scm` と `128_lir_branch_fusion.scm` により既知 fixnum 定数オペランドに対する冗長な `or rdx, [rsp]` タグ検査（ベースライン 4,511 箇所）が 0 箇所へ畳み込まれ、非 fixnum / オーバーフロー境界値で誤変換しない。
- [x] 既存の LIR 契約テスト（`test_lir_overflow_and_unsigned.scm` Groups 1–4 x86-64/AArch64/Verifier PASS [Group 5 `%shr` C 式括弧表記は既存既知差異], `test_fuzz_lir` 62/62 PASS, `test_lir_interpreter` 65/65 PASS）および新規単体テスト（`test_all_passes` 878/878 PASS）が PASS する。
- [x] `ulisp-boot` / `ulisp-cc` の Release ビルドおよびセルフホスト検証（3-stage modular bootstrap、`--as` / `-c` / `--target-elf` 検証、`test_ulisp_cc_native`）が完了し、ベースライン比の命令数・`.text` サイズ削減実績を Section 6 に記録している。

---

## 6. 計測・検証結果 (Measurements & Verification)

### ベースライン (`main` @ `551d751e8`, 2026-11-25 計測)
| 計測項目 | `ulisp-boot` | `ulisp-cc` | 備考 |
|---|---|---|---|
| バイナリ総サイズ | `9,707,024 B` | `12,089,736 B` | #954 完了直後 |
| `.text` セクションサイズ | `8,126,261 B` | `10,053,989 B` | — |
| `seto` 出現箇所数 | `3,762` | `5,041` | 6 モジュール `.s` 全量で `seto dl` + `movzx` + `cmp 0` + `jne` を構成 |
| `and rdx, 0x3` 出現箇所数 | `8,856` | (未計測) | 直後の冗長 `cmp rdx, 0` 除去対象 |
| 二項 `or rdx, QWORD PTR [rsp - N]` 箇所数 | `8,843` | (未計測) | うち直前 `mov eax, 0x...` (定数 fixnum) が `4,511` 箇所 |

### 実装後実績 (After #955)
| 計測項目 | `ulisp-boot` (変化) | `ulisp-cc` (変化) | 備考 |
|---|---|---|---|
| バイナリ総サイズ | `9,629,616 B` (**-77,408 B / -0.80%**) | `11,971,368 B` (**-118,368 B / -0.98%**) | stripped + split `.debug` |
| `.text` セクションサイズ | `8,048,309 B` (**-77,952 B / -0.96%**) | `9,934,981 B` (**-119,008 B / -1.18%**) | `size -A -d` 計測 |
| `seto` 出現箇所数 | **`0`** (**-3,762 / -100%**) | **`0`** (**-5,041 / -100%**) | すべて `jo` (`ulisp-boot`: 3,768, `ulisp-cc`: 5,050) へ融合 |
| `and rdx, 0x3` 直後の `cmp rdx, 0` | **`0`** (全 8,858 箇所除去) | **`0`** (全 12,450 箇所除去) | Pass 143 で冗長比較を完全除去 |
| 二項 `or rdx, QWORD PTR [rsp - N]` 箇所数 | `1,951` (**-6,892 / -77.9%**) | `2,942` | うち直前 `mov eax, 0x...` (定数 fixnum) は双方とも **`0`** |

- **テスト結果サマリー**:
  - `make test_all_passes`: **878 / 878 PASS** (39 ユニットテスト群: Pass 128/129/140/143 含む)
  - `make test_144a`: **7 / 7 PASS** (Test 7 `jo`/`jno` short `0x70`/`0x71`・near `0x0F 0x80`/`0x0F 0x81` 含む)
  - `make test_fuzz_lir`: **62 / 62 PASS** (`x86-64` vs `C99`)
  - `make test_lir_interpreter`: **65 / 65 PASS**
  - `make bootstrap_verify_modular`: **5 / 5 モジュール 3 段階完全不動点 (`stage2_*.s == stage3_*.s`) PASS**
  - `make test_builtin_as`: **6 / 6 PASS** (`--as` / `-c`) / `make test_differential_elf`: **13 / 13 PASS** (`--target-elf`)
  - `make test_ulisp_cc_native`: **ALL PASS** (Lua 5.4.7 ビルド・公式テストスイート完走 + ネイティブ高速化ベンチマーク含む)

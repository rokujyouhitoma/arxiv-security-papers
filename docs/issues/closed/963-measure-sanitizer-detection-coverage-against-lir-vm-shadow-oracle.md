---
ID: 963
種別: Feature
優先度: High
ステータス: Closed
担当エージェント:
  - Software Quality Assurance Specialist [Lead]
  - Information Security Specialist
  - IT Specialist (Programming Languages & Compilers / PLC)
  - Software Development (SWD)
ターゲットブランチ: feat/963-measure-sanitizer-coverage-via-vm-oracle
完了日: 2026-11-25
---

# [FEAT/ENH] シャドウメモリ付き LIR VM を判定基準（オラクル）とした `--sanitize-bounds` 検出範囲・CWE カバレッジ計測ハーネス (ID: 963)

## 1. 概要・背景 / Summary & Background

`#962` によって [lir_interpreter.scm](../../../ulisp/vm/lir_interpreter.scm) に 1 バイト/バイトのシャドウメモリと前後 16 バイト Redzone が導入され、LIR 参照 VM がオブジェクト単位のメモリ破壊（CWE-122 / CWE-415 / CWE-416 / CWE-590）を捕捉できるオラクル（判定基準）になった。

二村射影の言葉で言えば、`--sanitize-bounds`（`#930`）は「検査付き VM インタプリタをコンパイル時プログラムで特殊化した第 1 射影」に相当する。よって、`#962` のシャドウメモリ付き VM を比較基準に据え、現行 `--sanitize-bounds` がどの CWE をコンパイル時挿入ガード（`__ulisp_san_trap`）で先制捕捉でき、どのケースを見逃しているかを定量・自動で計測するハーネスを構築した。

---

## 2. トレーサビリティと影響範囲 / Traceability & Scope

### 関連ドキュメント（すべて相対リンク）
- [Issue #962](962-implement-lir-vm-shadow-memory-for-heap-oob-uaf-and-double-free.md)（LIR VM シャドウメモリ・オブジェクト単位検査オラクル）
- [Issue #964](964-unify-vm-and-sanitizer-checks-via-define-mem-check.md)（`define-mem-check` SSOT によるギャップ解消）
- [Issue #930](930-implement-c99-bounds-checking-sanitizer-mode.md)（C99 `--sanitize-bounds` 実装）
- [Issue #943](943-verify-and-extend-lir-vm-as-checked-c99-interpreter.md)（LIR VM 検査付きインタプリタ＆差分診断ハーネス）

### 影響範囲・変更対象ファイル
- [x] [test_c99_bounds_sanitizer.scm](../../../ulisp/tests/test_c99_bounds_sanitizer.scm)（19 ケースの CWE ベンチマーク定義、`san-classify-cwe-case` 4 象限分類器、カバレッジ表レポータ追加）
- [x] [160_backend_c.scm](../../../ulisp/backend/160_backend_c.scm)（L1829 `static ULISP_UNUSED void ulisp_safepoint_slow_path(void) {}` へ属性位置修正、`--target=c` E2E 完全復旧）

---

## 3. 実測カバレッジマトリクス（#963 ベースライン） / Measured Coverage Matrix

19 ケース（Unsafe 16 ケース + Negative Control 3 ケース）を `sanitize-bounds? = #f`（VM Oracle）および `sanitize-bounds? = #t`（Sanitizer）で実行した結果、両者が**相互補完的な 4 象限**を形成していることが判明した：

| 分類象限 | 件数 | 割合 | 該当 CWE / ケース | 技術的理由・#964 への示唆 |
| :--- | :---: | :---: | :--- | :--- |
| **`caught-both`**（双方捕捉） | **3** | 18.8% | `CWE-476` 直接 NULL 参照 (`*p`, `s->y`, `p[0]`) | `lower_to_lir.scm` が `C99-SAN-002` で先制捕捉し、VM も NULL ページ保護で捕捉 |
| **`sanitizer-only`**（サニタイザ単独捕捉） | **3** | 18.8% | `CWE-121/787` (`a[4]`, `a[-1]`, `&a[5]`) | **重要な実測発見**：VM はスタックフレーム・静的データの部分配列 Redzone を持たないため素通りし、`--sanitize-bounds` (`C99-SAN-001`) のみが捕捉 |
| **`gap-vm-only`**（第1射影ギャップ：VMのみ捕捉） | **10** | 62.5% | `CWE-122` (4件), `CWE-416` (2件), `CWE-415` (1件), `CWE-590` (2件), `CWE-476/strlen(NULL)` (1件) | `--sanitize-bounds` は動的ヒープ割り当てサイズ・解放状態・libc スタブ境界を検査しない。`#964` で縮減対象 |
| **`clean-pass`**（Negative Control） | **3** | 100% | `&arr[N]` sentinel、Lua ヒープ `[1]` FAM、`calloc/realloc/free(NULL)` | 偽陽性 **0 件** (`False Positives: 0`) |

---

## 4. 完了条件 / Success Criteria (DoD)

- [x] 19 ケース（Unsafe 16 ケース + Negative Control 3 ケース）の CWE 別判定・差分計測ハーネスが [test_c99_bounds_sanitizer.scm](../../../ulisp/tests/test_c99_bounds_sanitizer.scm) に組み込まれ、全件期待通りに分類・アサートされること
- [x] 全 Negative Control ケースで False Positive が 0 件（特に Lua `[1]` trailing FAM がヒープ割り当て時にも偽陽性を出さないこと）
- [x] CWE 別カバレッジ集計（`caught-both` / `sanitizer-only` / `gap-vm-only`）とギャップ一覧が再現可能に出力され、本 Issue に実測数値が記録されていること
- [x] `160_backend_c.scm:1829` の属性修正により `make -C ulisp test_c99_bounds_sanitizer`（Scheme 69/69 PASS + `.sh` E2E Pass 144 / Host ld / Portable C `--target=c` 全 PASS）・`test_c99_lir_vm_checked`・`test_lint_sexpr` が 100% PASS すること
- [x] `make check_format`・`make static_analysis`・`make py_compile` および相対リンク検証（絶対パス 0 件）が PASS すること

---

## 5. 完了サマリー / Completion Summary

- [test_c99_bounds_sanitizer.scm](../../../ulisp/tests/test_c99_bounds_sanitizer.scm)（Group 5）に 19 ケースの CWE マイクロベンチマークと 4 象限差分分類器 `san-classify-cwe-case` を実装し、ベースライン（Unsafe 16 件中 Sanitizer 6/16 [うち `caught-both` 3、`sanitizer-only` 3]・`gap-vm-only` 10/16・False Positive 0/3）を定量確定。
- [160_backend_c.scm](../../../ulisp/backend/160_backend_c.scm#L1829) の `ulisp_safepoint_slow_path` 属性順序を修正し、`make -C ulisp test_c99_bounds_sanitizer`（Scheme 69 passed + `.sh` Pass 144 / Host ld / Portable C 全 E2E PASS）・`test_c99_lir_vm_checked`（43 passed）・`test_lint_sexpr`・`make check_format && make static_analysis && make py_compile` がすべて EXIT 0 で完走することを確認。

---
ID: 964
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] `define-mem-check` によるメモリ安全性検査仕様の単一情報源化と LIR VM・`--sanitize-bounds` 双方への統一射影 (ID: 964)

## 1. 概要 / Summary

`#930`（[lower_to_lir.scm](../../ulisp/frontend_c/lower_to_lir.scm) におけるコンパイル時ガード挿入）と `#943`/`#962`（[lir_interpreter.scm](../../ulisp/vm/lir_interpreter.scm) における解釈時検査）は、同一のメモリ安全性ポリシーを別々の手書き実装として二重管理している。

`#944` で値表現を `define-value-repr` に一本化したのと同様に、本 Issue では検査種別ごとの述語・CWE 分類・トラップ仕様を1箇所の宣言的 DSL（`define-mem-check`）として定義し、以下の2方向へ統一射影する（手書き `cogen` パターン）：
1. **VM 用射影**: LIR 参照 VM が解釈時に評価する実行時検査ルール・エラーメッセージ・CWE メタデータ。
2. **サニタイザ用射影**: `lower_to_lir.scm` が `--sanitize-bounds` 時に挿入する LIR ガード命令列。

これにより、`#963` で特定されたサニタイザ側の検出ギャップ（サイズ既知のヒープ割り当て `malloc(N)` 境界検査や同一関数内の `free` 後状態検査等）を単一情報源から構造的に補完する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [Issue #963](963-measure-sanitizer-detection-coverage-against-lir-vm-shadow-oracle.md)（VM オラクル比較による検出ギャップ計測）
  - [Issue #962](closed/962-implement-lir-vm-shadow-memory-for-heap-oob-uaf-and-double-free.md)（VM シャドウメモリ検査）
  - [Issue #944](closed/944-unify-host-and-guest-value-representation-via-define-value-repr.md)（`define-value-repr` による SSOT 設計パターン）
  - [Issue #930](closed/930-implement-c99-bounds-checking-sanitizer-mode.md)（C99 `--sanitize-bounds`）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [lower_to_lir.scm](../../ulisp/frontend_c/lower_to_lir.scm) (`define-mem-check` サニタイザ射影の適用と既知サイズヒープ境界/関数内状態ガード拡張)
- [ ] [lir_interpreter.scm](../../ulisp/vm/lir_interpreter.scm) (`define-mem-check` 仕様と整合したトラップ種別・CWE タグの統一参照)
- [ ] [module_header.scm](../../ulisp/compiler/module_header.scm) (新規公開シンボル登録)
- [ ] [test_c99_bounds_sanitizer.scm](../../ulisp/tests/test_c99_bounds_sanitizer.scm) (ギャップ解消後のカバレッジ向上検証と仕様一致テスト)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/964-unify-memory-checks-via-define-mem-check`

1. `define-mem-check` レジストリ＆DSL を導入し、`null-deref` (CWE-476)・`static-bounds` (CWE-121)・`heap-bounds` (CWE-122)・`use-after-free` (CWE-416)・`double-free` (CWE-415)・`invalid-free` (CWE-590) の検査述語と診断メタデータを一元定義する。
2. `lower_to_lir.scm` の既存 `--sanitize-bounds` ガード生成を `define-mem-check` 駆動へ移行し、`#963` で判明したサイズ既知ヒープ割り当て (`malloc(N)`/`calloc(M,S)`) 境界や同一関数内解放後アクセス等の未検出ギャップをサニタイザ射影側へ追加する。
3. VM 側のトラップ通知・CWE 分類も同一仕様テーブルを参照するよう整合し、`#963` のベンチマークでサニタイザ検出率の向上を実測する。詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `define-mem-check` から VM 側検査メタデータと `lower_to_lir.scm` ガード生成の双方が導出されていること
- [ ] `#963` で特定されたサニタイザ未検出ケースの一部（既知サイズ `malloc` 範囲外等）が `--sanitize-bounds` で捕捉可能になり、ネイティブ実行でもトラップすること
- [ ] `--sanitize-bounds` 無効時のゼロオーバーヘッド不変条件が維持されていること
- [ ] `make -C ulisp test_c99_bounds_sanitizer test_c99_lir_vm_checked bootstrap_verify_modular` および品質ゲートが全 PASS すること

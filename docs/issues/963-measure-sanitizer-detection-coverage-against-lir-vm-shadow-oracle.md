---
ID: 963
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] シャドウメモリ付き LIR VM を判定基準（オラクル）とした `--sanitize-bounds` 検出範囲・CWE カバレッジ計測ハーネス (ID: 963)

## 1. 概要 / Summary

二村射影の観点において、`--sanitize-bounds`（`#930`）は「検査付き VM インタプリタ（`#943` + `#962`）をコンパイル時プログラムで特殊化した第 1 射影」に相当する。VM がオラクル（正解の安全性判定基準）として機能する状態で、現行サニタイザがどの CWE を静的/残余ガードで捕捉でき、どのケースを見逃しているかを定量計測する必要がある。

現在、リポジトリ内に CWE 分類ごとの最小再現ベンチマーク（Juliet 形式の小規模 C テスト群）および VM オラクルとの自動差分計測ハーネスは存在しない。本 Issue では [test_c99_bounds_sanitizer.scm](../../ulisp/tests/test_c99_bounds_sanitizer.scm) の `san-eval-vm-outcome` 等を拡張し、`--sanitize-bounds`（VM 上実行およびネイティブ実行）とシャドウメモリ付き VM の検出結果を自動突合して「VM は検出するがサニタイザは未検出」のギャップ一覧とカバレッジ指標を出力する計測ハーネスを構築する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [Issue #962](closed/962-implement-lir-vm-shadow-memory-for-heap-oob-uaf-and-double-free.md)（LIR VM シャドウメモリ・オブジェクト単位検査オラクル）
  - [Issue #930](closed/930-implement-c99-bounds-checking-sanitizer-mode.md)（C99 `--sanitize-bounds` 実装）
  - [Issue #943](closed/943-verify-and-extend-lir-vm-as-checked-c99-interpreter.md)（LIR VM 検査付きインタプリタ＆差分診断ハーネス）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [test_c99_bounds_sanitizer.scm](../../ulisp/tests/test_c99_bounds_sanitizer.scm) (`san-eval-vm-outcome` を活用した CWE 別ベンチマークスイートと検出差分マトリクス出力)
- [ ] [test_c99_lir_vm_checked.scm](../../ulisp/tests/test_c99_lir_vm_checked.scm) (オラクル側トラップ分類の整合確認)
- [ ] [Makefile](../../ulisp/Makefile) (計測ハーネス実行ターゲット整備)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/963-measure-sanitizer-coverage-via-vm-oracle`

1. 最小 C テストケース群（CWE-121 スタック配列越境、CWE-122 ヒープ範囲外アクセス、CWE-415 二重解放、CWE-416 解放後使用、CWE-476 NULL 参照、CWE-590 不正解放、および正当アクセスによる偽陽性ゼロ確認用 negative controls）を整備する。
2. 各ケースを `(sanitize-bounds? . #t)` で LIR 化し、`#962` のシャドウメモリ有効 VM で実行して `__ulisp_san_trap`（サニタイザ捕捉）と VM シャドウメモリトラップ（VM オラクルのみ捕捉）を切り分け、ネイティブ実行結果とも突き合わせる。
3. CWE ごとの捕捉率と未捕捉ギャップ一覧を構造化レポートとして出力し、後続 Issue（`#964`）の入力指標とする。詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 対象 CWE 群（CWE-121 / 122 / 415 / 416 / 476 / 590）および正当アクセスの自動実行・分類ハーネスが動作すること
- [ ] すべての正当アクセス（negative controls）で偽陽性トラップが発生しないこと
- [ ] 「サニタイザ捕捉 vs VM オラクル捕捉（ギャップ）」のカバレッジ表が再現可能に出力されること
- [ ] `make -C ulisp test_c99_bounds_sanitizer test_c99_lir_vm_checked` および品質ゲートが全 PASS すること

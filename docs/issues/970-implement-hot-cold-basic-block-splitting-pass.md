---
ID: 970
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Hot/Cold 基本ブロック分離パス（Slow Path の関数末尾・Cold 領域隔離）の導入 (ID: 970)

## 1. 概要 / Summary

現在ホットパスの直後にインライン配置されている型タグ検査失敗（`cmp_br_slow`）・GC 起動・`--sanitize-bounds` トラップ・例外送出などの Cold ブロックを関数末尾（および必要に応じ `.text.cold` セクション）へ隔離する基本ブロック配置パスを導入する。
L1 命令キャッシュ（I-Cache）の局所性とフォールスルー分岐予測率を向上させる。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [Issue #957](957-share-arithmetic-and-compare-slow-path-stubs.md)
  - [Issue #968](968-split-x86-64-backend-and-eliminate-raw-asm-peephole-matching.md)
  - [BASELINE.md](../../ulisp/benchmarks/BASELINE.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [128_lir_branch_fusion.scm](../../ulisp/lir/128_lir_branch_fusion.scm)
- [ ] [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm)
- [ ] [150_backend_aarch64.scm](../../ulisp/backend/150_backend_aarch64.scm)
- [ ] [pass_manager.scm](../../ulisp/compiler/pass_manager.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/970-hot-cold-block-splitting`

1. LIR/ASM ブロック属性として `:cold`（slow path / GC / trap / raise 到達ブロック）を識別・伝播する解析を実装する。
2. ホットパスを連続フォールスルー配置し、Cold ブロックを関数末尾または `.text.cold` へ再配置するパスを追加する。
3. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] Hot ブロックが連続配置され、Cold ブロック（`cmp_br_slow` / trap 等）が関数末尾へ隔離されること
- [ ] ホットループの I-Cache ミス率・実行レイテンシ改善がベンチマークで確認されること
- [ ] `make format` / `make static_analysis` / `make test` および `verify-quality-gates` が全 PASS すること

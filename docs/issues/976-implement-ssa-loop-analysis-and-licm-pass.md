---
ID: 976
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] SSA ループ解析基盤（自然ループ検出）と LICM（ループ不変コード移動）パスの実装 (ID: 976)

## 1. 概要 / Summary

`pass_manager.scm` の解析レジストリに支配木（Dominator Tree）ベースの自然ループ検出・プリヘッダ正規化解析を追加し、`L_mir_ssa` 上でループ不変コード移動（LICM）パスを実装する。
ループ内のクロージャ環境ロード・不変グローバル参照・ベクタ長取得・不変算術計算をプリヘッダへ移動させ、Scheme/C99 双方のホットループを高速化する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [Issue #966](966-separate-mir-ssa-and-machine-lir-for-unified-middle-end.md)
  - [Issue #973](973-implement-ssa-sccp-gvn-adce-and-decompose-lir-peephole.md)
  - [BASELINE.md](../../ulisp/benchmarks/BASELINE.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [pass_manager.scm](../../ulisp/compiler/pass_manager.scm)
- [ ] [132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm)
- [ ] [lir_lang.scm](../../ulisp/lir/lir_lang.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/976-ssa-loop-analysis-and-licm`

1. 支配関係とバックエッジから自然ループ（ヘッダ・本体・プリヘッダ）を抽出する `loop-info` 解析プロパティを登録する。
2. 純粋性・エイリアス非干渉性・投機的トラップ安全性を検証しつつ、ループ不変命令をプリヘッダへ巻き上げる LICM パスを実装する。
3. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] ループ不変式（環境ロード・不変計算・アドレス計算等）が安全にプリヘッダへ移動されること
- [ ] 副作用・例外・エイリアスを含むケースで誤移動を起こさないことが差分テストで検証されること
- [ ] `make format` / `make static_analysis` / `make test` および `verify-quality-gates` が全 PASS すること

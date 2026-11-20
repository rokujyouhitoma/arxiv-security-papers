---
ID: 886
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] セルフホスティング決定論性と不動点（Stage 2 -> Stage 3 diff 0）の検証 (ID: 886)

## 1. 概要 / Summary
DSN-33-03 §2.4 および §8.2 に基づき、全タスク実装後の Ulisp コンパイラ自身を Stage 1 $\to$ Stage 2 $\to$ Stage 3 でブートストラップ再コンパイルし、Stage 2 と Stage 3 の生成コード差分が完全にゼロ（$\mathrm{diff} = 0$）であることを検証する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-33-03 §2.4, §8.2](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#24-不動点方程式とセルフホスティング固定点stage-1--2--3)
- 関連 Issue: #617 (Bootstrap Chain)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/build/](ulisp/build/)
- [ ] [Makefile](Makefile)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/886-verify-self-hosting-fixed-point-and-zero-diff-bootstrap`

1. `make bootstrap` を実行し、Stage 1 から Stage 2、Stage 3 の順にセルフホストビルド。
2. `diff -u ulisp/build/scheme-stage2.s ulisp/build/scheme-stage3.s` を実行。
3. 差分が 0 バイトであることを確認し、自己相似メタコンパイラの不動点を証明。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Stage 2 と Stage 3 の生成アセンブリが完全一致（$\mathrm{diff} = 0$）すること。
- [ ] `make test` が 100% PASS すること。

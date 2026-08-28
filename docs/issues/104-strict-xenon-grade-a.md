---
ID: 104
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Xenon 循環的複雑度（CC）判定基準の厳格化（全基準 Grade A への昇格） (ID: 104)

## 1. 概要 / Summary
現在 `Makefile` 内で定義されている `xenon` ターゲットは `--max-absolute B --max-modules B --max-average A` となっており、モジュールおよび関数・クラス単位の循環的複雑度（Cyclomatic Complexity）において `B` 判定を許容している。
コードベースの保守性・品質・凝集度を極限まで高めるため、すべての閾値（`--max-absolute`, `--max-modules`, `--max-average`）を `A` に引き上げ、厳格な静的解析基準を強制する。

---

## 2. トレーサビリティ / Traceability
- [Makefile](../../Makefile) (`xenon`, `static_analysis`)
- `.agents/skills/verify-quality-gates/`
- `.agents/AGENTS.md` (Software Quality Assurance Specialist, Mandatory Quality Gates)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [Makefile](../../Makefile)
- [ ] `src/` 配下の各 Python モジュール（複雑度が B 判定となっている箇所の確認およびリファクタリング）

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/104-strict-xenon-grade-a`

1. `Makefile` の `xenon` ターゲット設定を `--max-absolute A --max-modules A --max-average A src` に変更。
2. `make xenon` を実行し、Grade A を超過（B 以上）している関数・モジュールを特定。
3. 必要に応じて関数分割・責務分離などのリファクタリングを実施して全ソースを Grade A に適合させる。
4. `make check_format`、`make static_analysis`、`make test` を実行して品質ゲートのパスを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `Makefile` の `xenon` ターゲットが `--max-absolute A --max-modules A --max-average A src` に更新されていること。
- [ ] `src/` 配下の全モジュールにおいて `make xenon` がエラーなく 0 終了（Grade A 適合）すること。
- [ ] `make check_format` および `make static_analysis` が正常に PASS すること。

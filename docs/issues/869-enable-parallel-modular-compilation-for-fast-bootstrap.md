---
ID: 869
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] bootstrap.sh および Makefile におけるマルチコア並列ビルドの標準化による自己ホスト高速化 (ID: 869)

## 1. 概要 / Summary
`make -C ulisp bootstrap` による自己ホスト固定点検証は、現在シングルスレッド直列で 3 ステージ（Stage 1〜3 + stdlib）をコンパイルしており、完了まで約 44〜48 秒を要している。
一方、プロジェクトには既に 5 モジュール並列インクリメンタルコンパイルを行う `--modular` モード（`make -j$JOBS`）が存在しており、これを用いると約 23 秒（50% 以上の時間短縮）でビット一致の固定点検証およびシード更新を達成できる。
本 Issue では、`bootstrap.sh` および `Makefile` の `bootstrap` ターゲットを見直し、CPU コア数に応じた並列ビルド（modular モード等）を標準化することで、日常の開発サイクルや CI/CD パイプラインにおける自己ホストビルド性能を倍速化する。

---

## 2. トレーサビリティ / Traceability
- DSN-33 Architecture Specification: 5-Module Modular Architecture
- 関連 Issue: [Issue #608](closed/608-implement-modular-separate-compilation-and-incremental-build.md), [Issue #846](closed/846-fix-ulisp-modular-and-bootstrap-arity.md)
- スクリプト: [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh), [ulisp/Makefile](../../ulisp/Makefile)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh)
- [ ] [ulisp/Makefile](../../ulisp/Makefile)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/869-fast-modular-bootstrap`

1. `ulisp/bootstrap.sh` のデフォルト動作改善：
   - デフォルトで利用可能 CPU コア数（`nproc`）を検出し、マルチコア環境（コア数 > 1）かつ引数指定がない場合、自動的に並列コンパイルパイプライン（`BOOTSTRAP_MODULAR=1`）を標準動作とする。
   - 明示的に直列 split-link を行いたい場合のために `--split-link` または `--monolithic` オプションはそのまま維持する。
2. `ulisp/Makefile` の `bootstrap` ターゲット改善：
   - `bootstrap:` ターゲットが最適なジョブ並列度（`JOBS = $(shell nproc 2>/dev/null || echo 4)`）を活用するよう連携を強化。
3. `make -C ulisp bootstrap` を実行し、全 5 モジュールの固定点（`stage2_*.s == stage3_*.s`）がビット一致で検証され、所要時間が 20 秒台前半に短縮されることを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `make -C ulisp bootstrap` がマルチコア並列パイプラインを活用し、所要時間が 48 秒から約 23 秒以下に半減すること。
- [ ] 全 5 モジュール（`compiler_base`, `frontend_passes`, `lir_passes`, `backend_passes`, `compiler_driver`）の固定点（Stage 2 vs Stage 3）が完全一致すること。
- [ ] スモークテスト（42 出力）および `bin/ulisp-boot` シード更新が正常に行われること。

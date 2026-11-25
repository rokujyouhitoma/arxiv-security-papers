---
ID: 968
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] x86-64 バックエンド 140_backend_x86_64.scm（4,145行）のモジュール分割と 143 ピープホールの %raw-asm 文字列依存解消 (ID: 968)

## 1. 概要 / Summary

4,145 行の `140_backend_x86_64.scm` に同居する命令選択・アセンブリ出力・Freestanding ランタイム補助関数を責務別に分割（`140a_x86_isel` / `140c_x86_layout` / `140d_x86_emit` / `140e_x86_runtime_stubs`）する。
あわせて `143_backend_x86_peephole.scm` で `(%raw-asm "    seto dl")` 等の文字列一致に依存している箇所を構造化 `L_asm_x86` AST 命令へ統一し、保守性とルール合成性を高める。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [Issue #955](closed/955-fuse-overflow-branch-to-jo-and-fold-constant-tag-checks.md)
  - [Issue #961](961-introduce-linear-scan-register-allocation-for-scheme-lir.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [backend_lang.scm](../../ulisp/backend/backend_lang.scm)
- [ ] [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm)
- [ ] [143_backend_x86_peephole.scm](../../ulisp/backend/143_backend_x86_peephole.scm)
- [ ] [150_backend_aarch64.scm](../../ulisp/backend/150_backend_aarch64.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/968-split-x86-64-backend`

1. `140_backend_x86_64.scm` を命令選択・ブロック配置・テキスト出力・ランタイム補助のモジュールに分割する。
2. `backend_lang.scm` の `L_asm_x86` に不足命令（`setcc` / `movzx` 等）を正規定義し、`143_backend_x86_peephole.scm` の `%raw-asm` 文字列マッチを撤廃する。
3. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] x86-64 バックエンドが責務別ファイルへ分割され、ピープホール規則が構造化 `L_asm_x86` AST のみで動作すること
- [ ] 既存の x86-64 / ELF / アセンブラテストおよびブートストラップ不動点が全 PASS すること
- [ ] `make format` / `make static_analysis` / `make test` および `verify-quality-gates` が全 PASS すること

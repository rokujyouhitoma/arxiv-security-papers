---
ID: 929
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] DDC (Diverse Double-Compiling) による C コンパイル出力の決定論性・ビット一致検証ハーネスの実装 (ID: 929)

## 1. 概要 / Summary
ULisp による C99 コンパイルパイプラインの決定論性（Deterministic Compilation）および供給網信頼性（Ken Thompson の "Trusting Trust" 対策）を証明するため、同一の Lua / musl C ソースコード群を異なるビルド環境・コンパイラ連鎖（GCC / Clang / ULisp）でビルド・突合し、ULisp 出力 ELF バイナリの SHA-256 ハッシュ完全一致を検証する DDC ハーネスを実装する（Step S8 / T17）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §6.1, §6.3](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-13 §6.3](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤 Issue: #886 (セルフホスティング不動点検証), #925, #928

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/tests/test_c_ddc_determinism.sh` (新規: 決定論的 SHA-256 比較 & 異種コンパイラ間相互ブート検証)
- [ ] `ulisp/driver/c_driver.scm` / `ulisp/backend/144_backend_x86_elf.scm` (非決定要素・ハッシュ順依存の完全排除)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_c_ddc` ターゲット追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/929-implement-ddc-determinism-verification`

1. C99 フロントエンドのハッシュテーブル走査順序やシンボル採番を完全に決定論的（出現順／ソート順）にし、実行環境・ビルド時刻・ファイルパスの揺らぎが生成 ELF バイナリへ混入しないよう保証する。
2. 異なるホストコンパイラ（例: GCC でビルドした ULisp vs Clang でビルドした ULisp、あるいは Reference VM 経由 vs ネイティブ版）を用いて Lua をそれぞれコンパイルし、出力される `.o` および最終 ELF バイナリの SHA-256 ハッシュがビット単位で 100% 一致することを検証する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 異なる環境・複数回実行でビルドした Lua オブジェクト／ELF バイナリの SHA-256 ハッシュが 100% 一致すること。
- [ ] DDC 相互コンパイル検証スクリプト（`test_c_ddc_determinism.sh`）が CI で安定 PASS すること。

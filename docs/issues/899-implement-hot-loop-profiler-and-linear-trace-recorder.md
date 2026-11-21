---
ID: 899
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Implement Hot-Loop Profiler and Linear Trace Recorder (ID: 899)

## 1. 概要 / Summary
[[DSN-33-05]](../designs/DSN-33-05-ulisp_endogenous_meta_tracing_jit_architecture.md) 第 4 章に基づき、ホットループ検出カウンタ、限定継続（`shift`/`reset`）を用いた内因的トレースレコーダ、および線形命令列（LIR Trace）抽出エンジンを実装する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-33-05] ULisp 内因的メタトレーシング JIT アーキテクチャ包括設計書 (第4章 トレース記録と限定継続)](../designs/DSN-33-05-ulisp_endogenous_meta_tracing_jit_architecture.md)
  - [[DSN-33-02] ULisp 多言語フロントエンド ＆ 型付き機械語 LIR 設計書](../designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/jit/tracer/tracer.scm](../../ulisp/jit/tracer/tracer.scm)
- [ ] [ulisp/jit/core/delimcc.scm](../../ulisp/jit/core/delimcc.scm)
- [ ] [ulisp/jit/bridge/to_lir.scm](../../ulisp/jit/bridge/to_lir.scm)
- [ ] [ulisp/tests/test_jit_tracer.scm](../../ulisp/tests/test_jit_tracer.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/899-implement-hot-loop-profiler-and-linear-trace-recorder`

1. ホットループの実行頻度を追跡する軽量なプロファイルカウンタ（閾値 `HOT_THRESHOLD = 50`）を実装。
2. 閾値到達時に `shift`/`reset` 境界を設定し、後続の評価ステップを副作用なく単一実行トレースとしてキャプチャ。
3. キャプチャした実行パスを直線的な LIR 命令列（SSA 形式）へ変換する `bridge/to_lir.scm` を強化。
4. 単体テスト `test_jit_tracer.scm` を作成し、条件分岐や再帰呼び出しが単一のホットパス LIR トレースとして正しく記録されることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] ホットループが自動検知され、限定継続により線形トレースが抽出されること。
- [ ] トレースが LIR の基本ブロック構造へ正確にマッピングされること。
- [ ] `make -C ulisp test_jit_tracer` が PASS すること。
- [ ] `make py_compile && make static_analysis` が PASS すること。

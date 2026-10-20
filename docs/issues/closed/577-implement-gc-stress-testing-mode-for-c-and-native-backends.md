---
ID: 577
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/TEST] Cバックエンドおよびネイティブ後端共通 GC ストレステストモード (--gc-stress) の実装 (ID: 577)

## 1. 概要 / Summary
uLisp は正確な世代別・コピー型 GC (Precise Copying GC) を採用しており、Pass 131 (`131_lir_safepoint.scm`) および Pass 141 (`141_backend_x86_gc.scm`)、`runtime.c` によってメモリ管理を行っている。
コピー型 GC ではオブジェクトがメモリ空間内を物理的に移動するため、Safepoint や関数呼び出し境界において「1つでも生存ポインタのスタック退避・ルート登録が漏れている」と、移動前の無効なアドレスを参照する致命的なハイゼンバグ（稀に発生する SEGV やデータ破壊）を引き起こす。
通常実行ではヒープ領域が枯渇するまで GC が発火しないため、ルート登録漏れが潜在化したまま見過ごされやすい。

本 Issue では、全ヒープアロケーション（`%alloc`）の実行時に必ず GC を強制起動し、オブジェクトの総移動・To-Space コピーを誘発する「GC ストレステストモード（`--gc-stress` / 環境変数 `ULISP_GC_STRESS=1`）」をネイティブランタイムおよび `runtime.c` の双方に実装する。これにより、スタック走査および Safepoint ルート保護の完全性を機械的・決定論的に検証する。

---

## 2. トレーサビリティ / Traceability
- 先行研究系譜: Precise Garbage Collection & Stack Maps (Baker / Cheney on the M.T.A.)
- DSN-33 コンパイラ・ランタイム仕様
- 関連 Issue:
  - [closed/564-wire-automatic-copying-gc-trigger-in-backend.md](closed/564-wire-automatic-copying-gc-trigger-in-backend.md)
  - [closed/568-implement-hybrid-exact-and-conservative-stack-scanning.md](closed/568-implement-hybrid-exact-and-conservative-stack-scanning.md)
- 関連ファイル:
  - [ulisp/runtime.c](../../ulisp/runtime.c)
  - [ulisp/passes/131_lir_safepoint.scm](../../ulisp/passes/131_lir_safepoint.scm)
  - [ulisp/passes/141_backend_x86_gc.scm](../../ulisp/passes/141_backend_x86_gc.scm)
  - [ulisp/passes/160_backend_c.scm](../../ulisp/passes/160_backend_c.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/runtime.c](../../ulisp/runtime.c) (`ulisp_alloc` 内に `ULISP_GC_STRESS` 条件分岐を追加し、毎割当での `gc_collect()` 実行)
- [x] [ulisp/passes/141_backend_x86_gc.scm](../../ulisp/passes/141_backend_x86_gc.scm) (ネイティブ `%alloc` スローパスにおける常時 GC 呼出しモードの実装)
- [x] [ulisp/passes/160_backend_c.scm](../../ulisp/passes/160_backend_c.scm) (Cコード生成におけるアロケーション直前・関数境界でのルート退避マクロ連携)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`test_gc_stress` ターゲット追加、ストレステスト用実行フラグ配線)
- [x] [ulisp/tests/test_gc_stress.scm](../../ulisp/tests/test_gc_stress.scm) (新規: 相互再帰・大量クロージャ生成・循環リスト等による負荷テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/577-implement-gc-stress-testing-mode-for-c-and-native-backends`

1. **`runtime.c` への常時 GC 発火ロジック実装**:
   - ランタイム初期化時（`ulisp_init`）に環境変数 `ULISP_GC_STRESS` を検査し、グローバル設定 `g_gc_stress_mode` を初期化。
   - `ulisp_alloc(size)` 冒頭で `g_gc_stress_mode` が有効な場合、ヒープ残量にかかわらず `gc_collect()` を強制トリガー。
   - アロケーション直後に To-Space へのコピーと全ルートポインタの再書換えが行われることを保証。
2. **ネイティブバックエンド (x86-64) へのストレステストフラグ対応 (`141_backend_x86_gc.scm`)**:
   - AOT コンパイル時のオプション `--gc-stress` により、インライン・バンプポインタ割当をバイパスし、常にランタイムの GC トランポリンを呼ぶ命令列を出力。
   - Safepoint スタックマップの全エントリが正確に追跡・更新されるかをテスト。
3. **C バックエンド (`160_backend_c.scm`) の保護強化**:
   - C バックエンドが出力する一時変数やスタックフレームにおいて、GC 発生時に生存しているポインタが確実にランタイムのシャドウスタック/ルート配列に登録されていることを確認。
4. **統合ストレステストの作成 (`test_gc_stress.scm`)**:
   - 深い再帰ループ（末尾・非末尾混合）
   - 大量クロージャのアロケーションと呼び出し
   - ベクタ・ペアの連結と循環構造の生成
   - これらの処理を `--gc-stress` 下で実行し、値の不整合や SEGV が一切起きないことを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `runtime.c` およびネイティブランタイムに `ULISP_GC_STRESS` 制御フラグが実装されていること
- [x] `make -C ulisp test_gc_stress` ターゲットが新設され、ストレステストが自動実行できること
- [x] Cバックエンドおよび AOT x86-64 バックエンドの双方で `test_gc_stress.scm` が 100% PASS すること
- [x] 既存の GC テストスイート（`test_gc_growth`, `test_gc_profile`, `test_gc_hybrid`）がデグレードなく PASS すること
- [x] 相対パスのみを使用し、絶対パスが含まれないこと

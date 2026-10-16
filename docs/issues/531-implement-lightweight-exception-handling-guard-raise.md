---
ID: 531
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 軽量大域脱出ハンドラスタックに基づく R7RS 例外処理機構 (guard / raise) の実装 (ID: 531)

## 1. 概要 / Summary
現在の ULisp は、型不一致、ゼロ除算、リスト外参照、未定義変数アクセス等のランタイムエラーが発生した際に OS レベルのシグナル（SIGSEGV / abort）でプロセスが即座にクラッシュする仕様となっている。
本 Issue では、R7RS Section 6.11（Exceptions）に準拠した例外捕捉構文 `(guard (var (cond-clause ...)) body ...)` および例外送出プリミティブ `(raise obj)` / `(raise-continuable obj)` を導入する。
なお、本実装は将来の完全な第一級継続（`call/cc`, Issue #540）を見据えた「3段階継続ロードマップ」の【ステップ1: 単方向・1回限り大域脱出（Escape Continuation）】に位置づけられる。ベアメタル・外部依存ゼロ（`-nostdlib -static`）の極限軽量性を維持するため、スタックディープコピーを伴わず、C 言語の `setjmp` / `longjmp` に類似した「軽量大域脱出ハンドラスタック（Exception Handler Stack Frame）」をランタイムおよびアセンブリ層に配備し、構文木パースやバッチ実行における堅牢なエラー回復を実現する。

---

## 2. トレーサビリティ / Traceability
- **関連規格**:
  - R7RS Section 6.11 (Exceptions: `guard`, `raise`, `with-exception-handler`)
  - R7RS Section 6.12 (Environments and Evaluation)
- **継続アーキテクチャ・ロードマップ**:
  - 【ステップ1（本Issue #531）】: 軽量大域脱出フレームによる例外処理 (`guard` / `raise`)
  - 【ステップ2（Issue #538 / #540）】: ゼロヒープ多値受渡し (`values` / `call-with-values`) および `dynamic-wind` リソース保護
  - 【ステップ3（Issue #540）】: スタックコピー方式による多重複帰可能な第一級継続 (`call/cc`)
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第4章 ランタイム機構)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-36: 完全ベアメタル自己完結型 Freestanding 実行基盤](../designs/DSN-36-ulisp_baremetal_freestanding_pure_scheme_runtime.md)
- **関連先行・後続 Issue**:
  - Issue #526: Mytkowicz 測定バイアス排除機構と動的命令数差分テスト基盤の統合
  - Issue #538: ゼロヒープ割当複数値返却のための R7RS 多値機構の実装
  - Issue #540: スタックコピー方式および dynamic-wind 統合に基づく完全な第一級継続 (call/cc) の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/07_backend_x86_64.scm](../../ulisp/passes/07_backend_x86_64.scm) (ハンドラスタック退避・復元、`%push-handler`, `%pop-handler`, `%raise-jump` LIR 命令)
- [ ] [ulisp/passes/07_backend_aarch64.scm](../../ulisp/passes/07_backend_aarch64.scm) (AArch64 向けハンドラフレーム管理)
- [ ] [ulisp/passes/02_desugar.scm](../../ulisp/passes/02_desugar.scm) (`guard` 構文の `with-exception-handler` / ハンドラ形式への脱糖)
- [ ] [ulisp/lib/exception.scm](../../ulisp/lib/exception.scm) (新規作成: Scheme レベルの標準例外プリミティブ)
- [ ] [ulisp/runtime.c](../../ulisp/runtime.c) (デバッグランタイム側ハンドラスタック境界検査)
- [ ] [tests/test_bare_metal_ulisp.py](../../tests/test_bare_metal_ulisp.py) (例外捕捉・回復 E2E 単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/531-ulisp-exception-handling-guard-raise`

1. **アセンブリ層の大域脱出フレーム（Handler Frame）**:
   - スレッドローカル/グローバルなハンドラスタックポインタ（`ulisp_handler_chain`）を BSS に保持。
   - ハンドラフレーム構造: `[prev_handler_ptr, saved_rsp, saved_rbp, handler_pc_label]` (32バイト)。
2. **中間表現とコード生成**:
   - `%push-handler`: 現在の RSP, RBP, ジャンプ先ラベルをスタックに積み、`ulisp_handler_chain` を更新。
   - `%pop-handler`: 正常終了時にハンドラフレームをポップして `ulisp_handler_chain` を巻き戻す。
   - `%raise`: 引数の例外オブジェクトを RAX に保持し、`ulisp_handler_chain` の RSP/RBP/PC へ即座にジャンプ。
3. **脱糖とマクロ**:
   - `(guard (var clause ...) body ...)` を `%with-exception-handler` と `cond` 節ディスパッチに脱糖。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(guard (e ((= e 42) 'caught)) (raise 42))` がクラッシュせずに `'caught` を返すこと。
- [ ] ゼロ除算や不正リスト参照などのエラーが `raise` 経由で安全に捕捉可能であること。
- [ ] 正常系において、ハンドラプッシュ・ポップのオーバーヘッドが 5ns 未満であること。
- [ ] セルフホスティング固定点ブートストラップ（`bootstrap.sh`）が完全一致（Identical）でパスすること。

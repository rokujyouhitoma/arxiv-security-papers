---
ID: 540
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] スタックコピー方式および dynamic-wind 統合に基づく完全な第一級継続 (call/cc) の実装 (ID: 540)

## 1. 概要 / Summary
Issue #531 では、例外捕捉・回復（`guard` / `raise`）向けにスタックコピーを伴わない軽量単方向大域脱出フレーム（Escape Continuation）を導入した。
本 Issue では、Scheme 言語の最も象徴的な言語機能であり、R7RS Section 6.10 に規定される **完全な第一級継続（First-Class Multi-Shot Continuation: `call/cc`）** および文脈出入り保護機構 **`dynamic-wind`** を実装する。
第一級継続により、単なるエラー脱出に留まらず、コルーチン（協調的マルチタスク）、非決定性バックトラッキング探索（`amb` オペレータ）、ジェネレータ、および過去の実行コンテキストへの多重複帰（Multi-shot re-entrancy）を可能にする。
ベアメタル・ゼロ libc 環境において、スタック全フレームのヒープ化（Spaghetti Stack）に伴う日常的オーバーヘッドを避けつつ、Chez Scheme / Chibi Scheme 等で実績のある **スタックコピー方式（Stack-copying with memcpy）** を採用し、Exact GC スタックマップ（Issue #519）および多値返却プロトコル（Issue #538）と統合する。

---

## 2. トレーサビリティ / Traceability
- **関連規格**:
  - R7RS Section 6.10 (Control features: `call-with-current-continuation`, `call/cc`, `dynamic-wind`)
  - SRFI-179 (Continuation-passing and dynamic wind extensions)
- **継続アーキテクチャ・ロードマップ**:
  - 【ステップ1（Issue #531）】: 軽量大域脱出フレームによる例外処理 (`guard` / `raise`)
  - 【ステップ2（Issue #538）】: ゼロヒープ多値受渡し (`values` / `call-with-values`)
  - 【ステップ3（本Issue #540）】: スタックコピー方式による多重複帰可能な第一級継続 (`call/cc`) & `dynamic-wind`
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第4章 ランタイム機構)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-36: 完全ベアメタル自己完結型 Freestanding 実行基盤](../designs/DSN-36-ulisp_baremetal_freestanding_pure_scheme_runtime.md)
- **関連先行 Issue**:
  - Issue #531: 軽量大域脱出ハンドラスタックに基づく R7RS 例外処理機構の実装
  - Issue #538: ゼロヒープ割当複数値返却のための R7RS 多値機構の実装
  - Issue #519: アンボクシング混在環境向け Exact GC スタックマップ (Stackmap) 自動生成機構の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/07_backend_x86_64.scm](../../ulisp/passes/07_backend_x86_64.scm) (`ulisp_capture_cc`, `ulisp_restore_cc` アセンブリルーチン、`%capture-continuation`, `%restore-continuation`)
- [ ] [ulisp/passes/07_backend_aarch64.scm](../../ulisp/passes/07_backend_aarch64.scm) (AArch64 向けスタックキャプチャ・リストア)
- [ ] [ulisp/passes/07_backend_c.scm](../../ulisp/passes/07_backend_c.scm) (C バックエンド向け setjmp/スタックバッファ実装)
- [ ] [ulisp/lib/continuation.scm](../../ulisp/lib/continuation.scm) (新規作成: `call/cc`, `dynamic-wind`, Wind-chain 共通祖先巻き戻しアルゴリズム)
- [ ] [ulisp/lib/gc.scm](../../ulisp/lib/gc.scm) (継続オブジェクトのヒープヘッダ定義および休止スタックペイロード走査)
- [ ] [ulisp/runtime.c](../../ulisp/runtime.c) (`ulisp_stack_base` の初期化とスタック深さ境界検査)
- [ ] [tests/test_call_cc.scm](../../ulisp/tests/test_call_cc.scm) (コルーチン・多重複帰・dynamic-wind 単体テストスイート)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/540-ulisp-first-class-call-cc-dynamic-wind`

1. **スタック底ポインタ（`ulisp_stack_base`）の捕捉**:
   - `_start` および `scheme_entry` 突入時、初期 `%rsp` を `ulisp_stack_base` に記録。
   - キャプチャ対象サイズ = `ulisp_stack_base - %rsp`。
2. **継続オブジェクト（Continuation Object）のヒープ構造**:
   - ヘッダフォーマット:
     ```text
     [0..7]   : ヘッダタグ (tag=CONTINUATION_TAG)
     [8..15]  : スタックコピー長 (バイト数)
     [16..23] : 退避された %rsp
     [24..31] : 退避された %rbp
     [32..71] : Callee-saved レジスタ群 (rbx, r12, r13, r14, r15)
     [72..79] : キャプチャ時点の wind-chain ポインタ
     [80..]   : スタックフレームの実データバイト列 (memcpy)
     ```
3. **低レベルスタック保存・復元ルーチン**:
   - `ulisp_capture_cc`:
     - 現在のスタックフレームバイト列をヒープへ複写し、継続オブジェクトを生成。
     - 初回呼び出し時は継続手続きオブジェクトをレシーバ `(lambda (k) ...)` に渡してそのまま継続。
   - `ulisp_restore_cc`:
     - 継続手続き `(k val ...)` が呼ばれた際、対象継続オブジェクトのスタックバイト列を現在のスタック領域へ書き戻し。
     - レジスタ群と `%rsp` / `%rbp` を復元し、退避されていたリターンアドレスへ直接ジャンプ。
4. **`dynamic-wind` による文脈出入り保護**:
   - `(dynamic-wind before-thunk thunk after-thunk)` を定義し、現在のアクティブな wind チェーンを管理。
   - 継続呼び出しによる非局所脱出時、現在の wind チェーンと復元先 wind チェーンの「最近共通祖先（LCA: Lowest Common Ancestor）」を計算。
   - 共通祖先まで `after-thunk` を脱出順に実行し、共通祖先から復元先まで `before-thunk` を突入順に実行してからスタック復元を実施。
5. **多値返却（Issue #538）および Exact GC（Issue #519）との完全統合**:
   - 継続手続きは 0 個、1 個、または任意の多値を受け取って過去フレームへ復元可能。
   - GC 発動時、休止中継続オブジェクト内のスタックコピーに含まれる生ポインタをスタックマップ情報に基づき安全に移動・追跡（Pointer Fixup）。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `(call/cc (lambda (k) (+ 1 (k 41))))` が `41` を返すこと（通常の大域脱出）。
- [x] 継続 `k` を変数に保存し、関数の終了後に再度 `(k 100)` を複数回呼び出してもスタック破壊・クラッシュせず正しい結果を返すこと（Multi-shot Reentrancy）。
- [x] `dynamic-wind` の `before` / `after` ハンドラが、継続によるスコープの脱出・再突入時に仕様通り正しく発火すること。
- [x] `call/cc` と `values`（Issue #538）が連携し、多値を受け取って継続復帰できること。
- [x] 協調型コルーチン（Coroutine generator）が `call/cc` を用いて正常に動作すること。
- [x] セルフホスティング固定点ブートストラップ（`bootstrap.sh`）および差分テスト（`make -C ulisp diff_test`）が 100% 合格すること。

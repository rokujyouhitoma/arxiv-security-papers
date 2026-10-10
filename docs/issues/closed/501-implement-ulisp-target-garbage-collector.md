---
ID: 501
種別: Feature
優先度: High
ステータス: Closed
担当: IT Specialist (Programming Languages & Compilers / PLC), SWD, Systems Architect, SQA
---

# [FEAT] Implement Target Runtime Garbage Collector for ULisp (ID: 501)

## 1. 概要 / Summary
現在、ULisp のターゲットランタイム（`ulisp/runtime.c`）は 4GB 固定長のバンプアロケータ（ゼロGC）で動作していたが、ヒープメモリ枯渇を防ぐため、**「おすすめの構成（黄金比: Scheme 主導 Cheney's 2-Space Copying GC）」**を正式採用し完全実装・不動点検証を完了した。

**【黄金比アーキテクチャ方針】**:
1. **Garbage Collector**: Scheme 標準ライブラリ（`ulisp/lib/gc.scm`）として完全自前実装。Cheney's 幅優先コピーアルゴリズムを Scheme の末尾再帰（TCO）で記述し、ULisp コンパイラ自身でコンパイル。GC 中は静的状態バッファを利用しゼロアロケーションで実行。
2. **メモリ確保 (ヒープ領域)**: BSS 静的メモリ領域 `uint64_t ulisp_gc_state[8];` を利用し、デュアルヒープ（from-space / to-space）を完全管理。
3. **C ランタイム (`runtime.c`)**: コード追加を最小限（`uint64_t ulisp_gc_state[8];` の 1 行のみ）に維持し、Thin C Cushion ポリシーを厳格に順守。
4. **全ターゲット共通動作**: x86-64 ネイティブおよび Portable C99 の全バックエンドで共通の GC ロジックが自動適用。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §2.3 (ゼロGC・バンプアロケータから GC への移行仕様), §7 (ランタイムアーキテクチャ)
- **DSN-31**: §3.2 (Backend B: ULisp AOT Native Backend)
- **先行 Issue**: #494 (Modularize ULisp Stdlib and Minimal C Runtime), #504 (Implement ULisp C and Wasm Backend via LIR)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/gc.scm](file:///workspace/arxiv-security-papers/ulisp/lib/gc.scm): 新規追加。Cheney's Copying GC アルゴリズム本体（スタックルート走査、オブジェクト退避、フォワーディング、空間swap、ゼロアロケーション）
- [x] [ulisp/passes/06_lir.scm](file:///workspace/arxiv-security-papers/ulisp/passes/06_lir.scm): 最小低レベルイントリンシック (`%raw-load`, `%raw-store!`, `%ptr-add`, `%ptr-tag`, `%ptr-untag`, `%ptr-tag-add`, `%get-rsp`, `%get-heap-ptr`, `%set-heap-ptr!`, `%get-gc-state-ptr`)、8バイト統一プレフィックスヘッダ出力
- [x] [ulisp/passes/07_backend_x86_64.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_x86_64.scm): LIR 命令の x86-64 出力（GAS 互換分割、%alloc プレフィックスヘッダ対応）
- [x] [ulisp/passes/07_backend_c.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_c.scm): LIR 新命令の C99 トランスパイル出力
- [x] [ulisp/runtime.c](file:///workspace/arxiv-security-papers/ulisp/runtime.c): 静的状態バッファ `uint64_t ulisp_gc_state[8];`（変更は最小1行のみ）
- [x] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile): `lib/gc.scm` のコアビルド組み込み
- [x] [ulisp/test.sh](file:///workspace/arxiv-security-papers/ulisp/test.sh): メモリ制約下での Step 26 単体・3回連続 GC サイクルテスト追加
- [x] [ulisp/test_c.sh](file:///workspace/arxiv-security-papers/ulisp/test_c.sh): C バックエンドでの互換性テスト全件 PASS
- [x] [ulisp/bootstrap.sh](file:///workspace/arxiv-security-papers/ulisp/bootstrap.sh): セルフホスティング不動点検証 (`diff stage2.s stage3.s == 0` bit-for-bit 完全一致成立)
- [x] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳の更新

---

## 4. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/lib/gc.scm` にて Cheney's Copying GC が Scheme コードとして完全実装されていること。
- [x] `runtime.c` の変更が最小限に抑えられ（1行のみ）、Thin C Runtime のポリシーが維持されていること。
- [x] 小容量ヒープ環境下で GC が自動発動し、大量アロケーション・複数回サイクルを行ってもクラッシュせず正常終了すること。
- [x] `ulisp/test.sh` および `ulisp/test_c.sh` の全テストが 100% PASS すること。
- [x] `ulisp/bootstrap.sh` の不動点検証（`diff stage2.s stage3.s == 0`）が成立すること。
- [x] すべての品質ゲートを通過すること。

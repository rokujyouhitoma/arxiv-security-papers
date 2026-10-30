---
ID: 639
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] FBIP (Perceus) インプレース再利用最適化パス (fbip-inplace-transform) の実装 (ID: 639)

## 1. 概要 / Summary
[DSN-37] Phase 3 Task 3.3 に基づき、線形所有権のもとで参照カウント 1（単一参照）であることが静的に保証された不変データ構造の更新を、新規アリーナ割り当てを行わずに生メモリ直接上書きへ変換する `fbip-inplace-transform` 最適化パスを実装する。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-37: Synapse 二層分離型並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#145-phase-3-nanopass-コンパイラ統合--fbip) (第 1.1 節 技術的出自、第 12.3 節 fbip-inplace-transform、第 14.5 節 Task 3.3)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/passes/pass_fbip.scm` (新規: FBIP 最適化パス)
- [ ] `tests/passes/test_pass_fbip.scm` (新規: インプレース更新変換テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/639-nanopass-fbip-inplace-transform`

1. **更新パターンの静的検出**:
   - 関数の末尾または線形ブロック内で、「古い cons セル / レコード / ベクタを分解（消費）し、その直後に同一サイズの新しいセルを割り当てて返却する」パターンを AST パターンマッチで検出。
2. **生メモリストアへの置換**:
   - `(cons new-car new-cdr)` 等の確保式を、古いセルのアドレスを再利用する `(%raw-mem-write! old-cell 0 new-car)` および `(%raw-mem-write! old-cell 8 new-cdr)` へ変換。
3. **アリーナアロケーションのバイパス**:
   - メモリ確保のオフセット加算コードを完全に消去。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] リストの走査・写像処理において、新規アリーナアロケーションが完全にスキップされること
- [ ] 変換後のネイティブコードがセグメンテーションフォールトを起こさず、正しい計算結果を返すこと
- [ ] メモリ消費量測定において、走査中のヒープ消費増分が 0 バイトであることを確認すること


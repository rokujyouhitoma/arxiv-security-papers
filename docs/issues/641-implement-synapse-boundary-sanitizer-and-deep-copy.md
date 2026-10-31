---
ID: 641
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] ホスト・カーネル境界サニタイザおよびディープコピー機構の実装 (ID: 641)

## 1. 概要 / Summary
[DSN-37] Phase 4 Task 4.1 に基づき、コントロールプレーン（Layer 1: R7RS）と並列計算プレーン（Layer 2: アフィン部分言語コア / ASC）の間でデータを受け渡す際の境界サニタイザを実装する。
即値型のゼロコピーレジスタ渡し、および複合型（リスト、ベクタ、文字列）の相手アリーナへの再帰的ディープコピーを厳格に強制し、Shared-Nothing メモリモデルを堅持する。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#146-phase-4-ホストカーネル境界--世代管理型投機タスク破棄) (第 8.1 節 データサニタイズ、第 14.6 節 Task 4.1)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/runtime/concurrency/boundary.scm` (新規: 境界サニタイザおよびディープコピー)
- [ ] `tests/concurrency/test_boundary.scm` (新規: 境界サニタイズ単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/641-boundary-sanitizer`

1. **型判別ディスパッチ**:
   - Fixnum, Flonum, Boolean, Character: ポインタ共有が発生しないためそのままレジスタ渡し。
2. **相手アリーナへの再帰コピー**:
   - Pair（リスト）: タスクのアリーナから cons セルを順次バンプ割り当てしながら要素をディープコピー。循環リストは検出してエラー。
   - Vector: 相手アリーナに連続メモリを確保し、要素を再帰コピー。
   - String / Bytevector: バイト列を `memcpy` 相当でアリーナへ複製。
3. **境界分離の完全性検証**:
   - コピー完了後、外側と内側のアドレス空間に共通のポインタが 1 つも存在しないことをアサート。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] タスク内で渡された複合オブジェクトを変更・再利用しても、呼び出し元 R7RS 側のデータが一切影響を受けないこと
- [ ] 境界を跨いだポインタの直通（漏洩）が静的および動的アサーションで 100% 遮断されること
- [ ] 即値型がオーバーヘッドゼロ（レジスタ直接渡し）で渡ること

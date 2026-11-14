---
ID: 840
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT] Nanopass パスマネージャにおける解析結果キャッシュ自動無効化と再計算 (ID: 840)

## 1. 概要 / Summary
Nanopass / Picopass パスマネージャ（`ulisp/compiler/pass_manager.scm`）を拡張し、各パス定義において `preserves`（維持・保存する解析情報）および `invalidates`（破壊・無効化する解析情報）を明示的に宣言可能にする。
これにより、変数の生存区間解析（Liveness）、変数の別名・エスケープ情報（Alias/Escape）、CFG の支配関係（Dominator Tree）などの解析結果について、パスマネージャが「未計算または無効化されていれば自動で再計算・更新する」依存関係駆動の実行機構を確立する。
C 由来の複雑な CFG に対する反復ピープホール最適化や定数伝播ループを安全に回せるようにするとともに、Scheme 側の最適化パイプライン（CP0/LVN/Picopass）の堅牢性を保証する。

---

## 2. トレーサビリティ / Traceability
- **DSN-38**: §2 (D1: mem2reg, D2: 既存最適化の適用), §3 (S6: 性能改善)
- **DSN-33-01**: §5.1 (パス・ルール依存関係 DAG と自動スケジューリング)
- **関連 Issue**: #765 (Rule Dependency DAG), #813 (Fuse-rules Post-order), #827 (Braun SSA Arbitrary CFG)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm): 解析情報依存 DAG の追跡、無効化シグナル発行、遅延再計算ドライバ
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm): `define-pass` 構文への `preserves` / `invalidates` オプション拡張
- [ ] [ulisp/tests/test_pass_manager_cache_invalidation.scm](../../ulisp/tests/test_pass_manager_cache_invalidation.scm): 解析キャッシュ整合性および自動再計算テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/840-nanopass-analysis-cache-invalidation`

1. 解析プロパティ（Analysis Property）の抽象定義：
   - `'cfg-dominators`, `'variable-liveness`, `'alias-sets`, `'term-hash-consing` などのプロパティ識別子の統一。
   - プロパティごとの計算ルーチン（解析パス）の登録。
2. パス契約メタデータの拡張：
   ```scheme
   (define-pass optimize-peephole
     (:preserves (cfg-dominators))
     (:invalidates (variable-liveness alias-sets))
     ...)
   ```
3. パスマネージャの依存性解決ループの実装：
   - 後続パスが `(:requires (variable-liveness))` を持つ場合、直前のパスで無効化されていれば自動的に解析パスを実行してキャッシュを再構築。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 解析プロパティが無効化された後、そのプロパティを要求するパスの直前で再計算ルーチンが自動実行されること。
- [ ] 最適化パスの連続反復適用（Fixpoint 反復）において、古い解析情報に起因する不正なコード変換・最適化バグが完全に抑止されること。
- [ ] 単体テスト `test_pass_manager_cache_invalidation.scm` がパスすること。

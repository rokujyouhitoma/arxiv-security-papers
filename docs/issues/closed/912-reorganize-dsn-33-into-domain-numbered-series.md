---
ID: 912
種別: Docs / Architecture
優先度: High
ステータス: Closed
---

# [DOCS/ARCH] DSN-33 シリーズの 2桁ドメイン番台方式（10番台〜40番台）への体系的再編 (ID: 912)

## 1. 概要 / Summary
時系列で割り振られていた `DSN-33-01`〜`DSN-33-09` の個別仕様書群を、技術領域（ドメイン）ごとに明確に分類する **2桁ドメイン番台方式**（10番台: コアコンパイラ、20番台: メタコンパイラ・JIT、30番台: ランタイム・応用、40番台: 検証・ベンチマーク）へとリナンバリング・リネームし、ドキュメント台帳（`MNG-01`）および相互参照リンクを完全に同期する。

---

## 2. トレーサビリティ / Traceability
- 上位仕様: `docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md`
- ドキュメント台帳: `docs/processes/MNG-01-document_ledger.md`
- 関連設計書: `DSN-33-11`〜`13`, `DSN-33-21`〜`23`, `DSN-33-31`〜`32`, `DSN-33-41`, `DSN-37`

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [DSN-33](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- [x] `DSN-33-11` 〜 `DSN-33-41` (全9ファイルのリネーム ＆ 本文番号・相互リンク更新)
- [x] [DSN-37](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- [x] [ドキュメント台帳 MNG-01](../processes/MNG-01-document_ledger.md)
- [x] [Issue 台帳](README.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `docs/912-reorganize-dsn-33-into-domain-numbered-series`

1. `git mv` により `DSN-33-01`〜`09` を `DSN-33-11`, `12`, `13`, `21`, `22`, `23`, `31`, `32`, `41` へ改名する。
2. 一意な辞書マッピング置換により、全 `DSN-33*` 文書および `DSN-37` 内の文書番号・リンク・関連個別仕様書リスト（ドメイン順グループ化）を一括更新する。
3. `MNG-01-document_ledger.md` を新番台体系で更新する。
4. 旧ファイル名リンク残存 0 件、絶対パス混入 0 件、`make py_compile` 通過を確認し、Issue をクローズして `main` へマージする。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 9 個別設計書が 10/20/30/40 番台ファイル名へリネームされていること。
- [x] `docs/designs/` および `docs/processes/` において旧ファイル名 `DSN-33-0[1-9]-` へのリンク残存が 0 件であること。
- [x] `DSN-33` 系文書および `MNG-01` の番号体系と説明が整合していること。
- [x] 絶対パスリンクが 0 件、`make py_compile` が正常終了すること。

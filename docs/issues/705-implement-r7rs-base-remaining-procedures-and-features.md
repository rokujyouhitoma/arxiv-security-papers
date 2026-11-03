---
ID: 705
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-small (scheme base) 残余コア手続き群 (features, input/output-port-open?) の完全実装 (ID: 705)

## 1. 概要 / Summary

R7RS-small コア言語仕様および標準ライブラリ **`(scheme base)`** において未実装（`×`）として残存していた残余コア手続き群を実装し、コア言語サポート率を実質 100% 近傍へと完結させる。
対象手続き:
1. **`features` (§6.14 / base)**: システムで有効な機能識別子シンボルのリスト（`r7rs`, `exact-closed`, `ratios`, `exact-complex`, `full-unicode`, `little-endian`, `big-endian`, `ulisp` 等）を返却する手続き。
2. **`input-port-open?` (§6.13.1 / base)**: 指定されたポートが入力ポートかつ開放状態であるかを判定する述語。
3. **`output-port-open?` (§6.13.1 / base)**: 指定されたポートが出力ポートかつ開放状態であるかを判定する述語。

---

## 2. トレーサビリティ / Traceability

- 関連仕様:
  - R7RS-small Section 6.13.1: Ports (`input-port-open?`, `output-port-open?`)
  - R7RS-small Section 6.14: System interface (`features`)
  - R7RS-small Section 7.1.1: Base Library (`(scheme base)`)
  - ULisp 言語仕様準拠リファレンス: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.3 (6.13.1, 6.14), §1.4

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/lib/port.scm](../../ulisp/lib/port.scm) (`input-port-open?`, `output-port-open?` の実装)
- [ ] [ulisp/lib/posix.scm](../../ulisp/lib/posix.scm) または [ulisp/lib/math.scm](../../ulisp/lib/math.scm) (`features` 手続きの実装)
- [ ] [ulisp/lib/scheme/base.sld](../../ulisp/lib/scheme/base.sld) (エクスポート宣言の追加)
- [ ] [ulisp/tests/test_ports.scm](../../ulisp/tests/test_ports.scm) (ポート開放述語テストの拡充)
- [ ] [ulisp/tests/test_r7rs_cond_expand.scm](../../ulisp/tests/test_r7rs_cond_expand.scm) (`features` テストの追加)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (ステータス更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/705-implement-r7rs-base-remaining-procedures-and-features`

1. **ポート個別開放状態述語の実装 (`ulisp/lib/port.scm`)**:
   ```scheme
   (define (input-port-open? p)
     (and (input-port? p) (port-open? p)))

   (define (output-port-open? p)
     (and (output-port? p) (port-open? p)))
   ```
2. **`features` 手続きの実装**:
   - [Pass 010 (010_library.scm)](../../ulisp/frontend/010_library.scm) の `cond-expand` 認識済み機能シンボル群と整合する静的リストを返却する手続き `(features)` を定義。
3. **`(scheme base)` エクスポート登録**:
   - `ulisp/lib/scheme/base.sld` に `features`, `input-port-open?`, `output-port-open?` を追加。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `(scheme base)` から `features`, `input-port-open?`, `output-port-open?` が正常にエクスポート・解決されること。
- [ ] 入力ポート、出力ポート、およびクローズ後の各ポートに対して述語が正確に `#t` / `#f` を返却すること。
- [ ] `(features)` の返却リストに `r7rs` やアーキテクチャ特性（エンディアン等）が含まれること。
- [ ] AOT ネイティブコンパイルおよび回帰テストが PASS すること。
- [ ] `make verify_r7rs_traceability` が 100% PASS し、`ref_r7rs_compliance.md` の該当項目ステータスが **◎** に更新されること。


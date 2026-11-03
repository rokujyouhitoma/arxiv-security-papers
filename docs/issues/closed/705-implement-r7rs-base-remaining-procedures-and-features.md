---
ID: 705
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] R7RS-small (scheme base) 残余コア手続き群 (features, input/output-port-open?) の完全実装 (ID: 705)

## 1. 概要 / Summary

R7RS-small コア言語仕様および標準ライブラリ **`(scheme base)`** において未実装（`×`）として残存していた残余コア手続き群（`features`, `input-port-open?`, `output-port-open?`）を実装し、コア言語サポート率を完結させる。

---

## 2. トレーサビリティ / Traceability

- 関連仕様:
  - R7RS-small Section 6.13.1: Ports (`input-port-open?`, `output-port-open?`)
  - R7RS-small Section 6.14: System interface (`features`)
  - R7RS-small Section 7.1.1: Base Library (`(scheme base)`)
  - ULisp 言語仕様準拠リファレンス: [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) §1.3 (6.13.1, 6.14), §1.4

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/lib/port.scm](../../../ulisp/lib/port.scm) (`input-port-open?`, `output-port-open?` の実装)
- [x] [ulisp/lib/posix.scm](../../../ulisp/lib/posix.scm) (`features` 手続きの実装)
- [x] [ulisp/lib/scheme/base.sld](../../../ulisp/lib/scheme/base.sld) (エクスポート宣言の追加)
- [x] [ulisp/tests/test_ports.scm](../../../ulisp/tests/test_ports.scm) (ポート開放述語テストの拡充)
- [x] [ulisp/tests/test_r7rs_cond_expand.scm](../../../ulisp/tests/test_r7rs_cond_expand.scm) (`features` テストの追加)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) (ステータス更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/705-implement-r7rs-base-remaining-procedures-and-features`

### Step 1: ポート個別開放状態述語の実装 (`ulisp/lib/port.scm`)
- R7RS §6.13.1 に準拠し、`input-port-open?` および `output-port-open?` を `ulisp/lib/port.scm` に実装し、文字列ポートに対する `close-port` 状態反映も強化。

### Step 2: `features` 手続きの実装 (`ulisp/lib/posix.scm`)
- R7RS §6.14 に準拠し、有効な機能識別子シンボルのリストを返却する `(features)` 手続きを `ulisp/lib/posix.scm` に実装。

### Step 3: `(scheme base)` エクスポート登録 (`ulisp/lib/scheme/base.sld`)
- `ulisp/lib/scheme/base.sld` の `export` 節に `features`, `input-port-open?`, `output-port-open?` を追加。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `(scheme base)` から `features`, `input-port-open?`, `output-port-open?` が正常にエクスポート・解決されること。
- [x] 入力ポート、出力ポート、およびクローズ後の各ポートに対して `input-port-open?` / `output-port-open?` が正確に `#t` / `#f` を返却すること。
- [x] `(features)` の返却リストがリストであり、`r7rs`, `ulisp`, `exact-closed`, `little-endian` 等のシンボルを含むこと。
- [x] `make -C ulisp test_ports test_r7rs_cond_expand` が PASS すること。
- [x] `make verify_r7rs_traceability` が 100% PASS し、`ref_r7rs_compliance.md` の該当項目ステータスが **◎** に更新されること。


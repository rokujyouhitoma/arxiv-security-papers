---
ID: 648
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-large (SRFI 1 Lists) 高階リスト操作手続き群の実装 (ID: 648)

## 1. 概要 / Summary
R7RS-large (Red Edition) の核となる SRFI 1 (Lists) の主要高階関数群（`filter`, `fold`, `fold-right`, `take`, `drop`, `any`, `every`, `find`, `remove` 等）を ULisp 標準ライブラリに実装する。
自己ホスティング・コンパイラ内部パス（AST 変換・最適化パス）および一般的な Scheme アプリケーション開発における生産性と表現力を大幅に強化する。

---

## 2. トレーサビリティ / Traceability
- R7RS-large: Red Edition / SRFI 1 (List Library)
- 仕様リファレンス: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1
- 関連ライブラリ: [ulisp/lib/list.scm](../../ulisp/lib/list.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/list.scm](../../ulisp/lib/list.scm)
- [ ] [ulisp/lib/srfi/1.sld](../../ulisp/lib/srfi/1.sld) (新規ライブラリ定義)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)
- [ ] [ulisp/tests/test_srfi1.scm](../../ulisp/tests/test_srfi1.scm) (新規テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/648-implement-srfi-1-higher-order-list-procedures`

1. `ulisp/lib/list.scm` に `fold`, `fold-right`, `filter`, `remove`, `take`, `drop`, `take-right`, `drop-right`, `any`, `every`, `find` などの純粋 Scheme 手続きを追加。
2. ライブラリ `(srfi 1)` を `ulisp/lib/srfi/1.sld` として策定し、`import` 可能にする。
3. 末尾再帰最適化 (TCO) を最大限活かし、スタックオーバーフローを起こさないループ構造とする。
4. 単体テストを追加し、`make test` をパスさせる。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] SRFI 1 の主要関数（`fold`, `filter`, `take`, `drop`, `any`, `every` 等）が期待通り動作すること。
- [ ] AOT ネイティブコンパイルおよび C バックエンド双方で動作確認されること。
- [ ] `ref_r7rs_compliance.md` の SRFI 1 のステータスを更新すること。


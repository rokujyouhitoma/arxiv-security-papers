---
ID: 868
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] lib/vector.scm (R7RS Base) と lib/srfi/133.scm (SRFI 133) のモジュール分離と依存関係解消 (ID: 868)

## 1. 概要 / Summary
コミット `8842728e1` (Issue #853) において、SRFI 133 ベクタ操作ライブラリ（40+ 手続き）が、既存の R7RS-small 仕様である `ulisp/lib/vector.scm`（元は 184 行）に直接追加された。
その結果：
1. `lib/vector.scm` が 184 行から 848 行へ急激に肥大化。
2. SRFI 133 手続き群（`vector-unfold`, `vector-map` 等）が `list`, `reverse`, `length`, `list-tail` などのリスト手続きに依存するため、`lib/vector.scm` を単体で include すると未束縛変数エラー（Unbound Symbol: list）が発生し、必ず `lib/list.scm`（747行）を同時に include しなければならなくなった。
3. `stdlib_entry.scm` および `build/ulisp_stdlib.o` のビルド時間やフットプリントが増大し、`test_c.sh` でもベクタ関連テストが 51,000 行超の C コードを生成する直接要因となっている。

本 Issue では、R7RS-small `(scheme base)` に必要な基本ベクタライブラリ（`lib/vector.scm`, 184行）と、R7RS-large Red Edition / SRFI 133 の拡張ライブラリ（`lib/srfi/133.scm`）を明確にモジュール分離し、相互依存とコード肥大化を根本解消する。

---

## 2. トレーサビリティ / Traceability
- R7RS Section 6.8 (Vectors): `(scheme base)` エクスポート対象手続き
- SRFI 133: Vector Library (R7RS-large Red Edition: `(scheme vector)`)
- 関連 Issue: [Issue #853](closed/853-implement-srfi-133-vector-library-and-scheme-vector-module.md), [Issue #866](866-optimize-test-c-library-includes-for-high-speed-execution.md)
- 仕様定義: [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/vector.scm](../../ulisp/lib/vector.scm)
- [ ] [ulisp/lib/srfi/133.scm](../../ulisp/lib/srfi/133.scm) (新規作成)
- [ ] [ulisp/lib/scheme/vector.sld](../../ulisp/lib/scheme/vector.sld)
- [ ] [ulisp/lib/srfi/133.sld](../../ulisp/lib/srfi/133.sld)
- [ ] [ulisp/tests/test_srfi_133.scm](../../ulisp/tests/test_srfi_133.scm)
- [ ] [ulisp/Makefile](../../ulisp/Makefile)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/868-modularize-r7rs-vector-and-srfi-133`

1. `ulisp/lib/vector.scm` を R7RS-small `(scheme base)` 相当のクリーンな状態（約 180 行）にロールバック・整理：
   - `vector-copy-range`, `vector-copy-range!`
   - `vector-fill-range!`
   - `vector-append2`, `vector-copy`, `vector-copy!`, `vector-append`
   - `vector->list`, `vector->list-range`, `list->vector`
   - `vector-map`, `vector-for-each`
   - `vector->string-range`, `string->vector-range`
   - ※ `list.scm` に依存する SRFI 133 高度手続き（`vector-unfold`, `vector-fold`, `vector-binary-search`, `vector-partition` 等）は含まない。
2. 新規ファイル `ulisp/lib/srfi/133.scm` を作成：
   - SRFI 133 の 40+ 手続き（unfold, fold, search, partition, cumulate 等）を配置。
   - `lib/vector.scm` の基本手続きを利用し、必要に応じて `lib/list.scm` と連携。
3. `ulisp/lib/scheme/vector.sld` および `ulisp/lib/srfi/133.sld` を更新：
   - `(include "lib/vector.scm")` に加えて `(include "lib/srfi/133.scm")` をインクルードするよう構成。
4. `ulisp/Makefile` の `test_srfi_133` ターゲットを更新し、`lib/srfi/133.scm` を依存関係に追加。
5. `test_srfi_133` (全 63 テスト) および `test_c` がすべて PASS することを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `lib/vector.scm` が単体で include 可能（Unbound Symbol エラーが発生しない）であること。
- [ ] `lib/srfi/133.scm` に SRFI 133 手続きがモジュール化され、`(scheme vector)` および `(srfi 133)` から完全利用可能であること。
- [ ] `make -C ulisp test_srfi_133` (63 テスト) が 100% PASS すること。
- [ ] `make -C ulisp bootstrap` で固定点が正常に達成されること。
- [ ] `test_c.sh` で `vector.scm` を単独 include した場合の C コード行数が 51,000 行から約 2,000 行以下に激減すること。

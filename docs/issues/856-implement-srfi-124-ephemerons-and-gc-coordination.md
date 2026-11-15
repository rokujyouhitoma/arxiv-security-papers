---
ID: 856
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] SRFI 124 エフェメロン ((scheme ephemeron)) と 2-Space GC 協調回収の実装 (ID: 856)

## 1. 概要 / Summary
R7RS-large Red Edition に規定される SRFI 124 (Ephemerons) は、キーと値のペアを保持し、「キーが外部から到達可能である場合に限り値も保持するが、キーが到達不能になった場合は値を解放する」弱参照機構である。循環参照や弱参照キャッシュの構築において必須となる。
ULisp の 2-Space コピー GC (`ulisp/lib/gc.scm`) においては未対応であったため、本 Issue でエフェメロンの型定義、GC ルート走査・回収フェーズとの協調ロジック、および `(scheme ephemeron)` ライブラリを実装する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-large Red Edition: `(scheme ephemeron)`
  - SRFI 124: Ephemerons
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/gc.scm](../../ulisp/lib/gc.scm)
- [ ] [ulisp/lib/ephemeron.scm](../../ulisp/lib/ephemeron.scm) (新規作成)
- [ ] [ulisp/lib/scheme/ephemeron.sld](../../ulisp/lib/scheme/ephemeron.sld) (新規作成)
- [ ] [ulisp/lib/srfi/124.sld](../../ulisp/lib/srfi/124.sld) (新規作成)
- [ ] [ulisp/tests/test_gc_ephemeron.scm](../../ulisp/tests/test_gc_ephemeron.scm) (新規作成)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/856-implement-srfi-124-ephemerons-and-gc-coordination`

1. **エフェメロン型構造の定義**:
   - `make-ephemeron`, `ephemeron?`, `ephemeron-broken?`, `ephemeron-key`, `ephemeron-datum`。
   - 特殊なヒープヘッダータグ `ulisp-ephemeron-tag` を割り当て。
2. **GC 協調スキャンの実装 (`ulisp/lib/gc.scm`)**:
   - GC のマーク／コピー走査中、エフェメロンのキーと値は即座にトレースせず「保留エフェメロンリスト」に登録。
   - 通常オブジェクトのトレース完了後、キーが到達可能（コピー先空間に移動済み）か判定。キーが到達可能なら値もトレース、未到達ならエフェメロンを "broken" 状態にして値を切断。
3. **テスト検証**:
   - GC サイクル前後でエフェメロンのキー破棄に伴うデータ解放を検証するユニットテストを作成。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(scheme ephemeron)` / `(srfi 124)` が利用可能であること。
- [ ] キーが到達不能になったエフェメロンが GC 後に `ephemeron-broken?` で `#t` となり、値が回収されること。
- [ ] 既存の 2-Space GC ストレス・プロファイルテストがすべて PASS すること。

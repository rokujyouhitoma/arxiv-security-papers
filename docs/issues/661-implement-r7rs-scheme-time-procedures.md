---
ID: 661
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS §6.14 (scheme time) 高精度時間計測手続き群の完全準拠実装 (ID: 661)

## 1. 概要 / Summary
R7RS-small §6.14 (Time) および標準ライブラリ `(scheme time)` に規定される時間計測手続き群（`current-second`, `current-jiffy`, `jiffies-per-second`）を完全実装し、準拠率を 100%（◎）へ引き上げる。
現在、`(scheme time)` は基本的なラッパー定義（サポート率約 30% / △）にとどまっており、エポック秒（TAI-1958 または POSIX エポック）の正確な取得や、CPU タイマー/CLOCK_MONOTONIC に基づく高精度単調増加ジフィー（jiffy）の返却を確立する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-small §6.14: System interface (Time: `current-second`, `current-jiffy`, `jiffies-per-second`)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.3.14 システムインターフェース / §1.4 標準 16 ライブラリ別網羅表
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/posix.scm](../ulisp/lib/posix.scm) (POSIX clock_gettime システムコールラッパー)
- [ ] [ulisp/lib/scheme/time.sld](../ulisp/lib/scheme/time.sld) (ライブラリ定義・エクスポート)
- [ ] [ulisp/runtime.c](../ulisp/runtime.c) (C バックエンド用時間関数連携)
- [ ] [ulisp/tests/test_r7rs_time.scm](../ulisp/tests/test_r7rs_time.scm) (新規単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/661-implement-r7rs-scheme-time-procedures`

1. POSIX `clock_gettime(CLOCK_REALTIME)` を用いてエポック秒（秒整数 Fixnum）を取得する `current-second` を実装。
2. POSIX `clock_gettime(CLOCK_MONOTONIC)` を用いてマイクロ秒またはナノ秒単位の単調増加ジフィー整数を返す `current-jiffy` を実装。
3. 1秒あたりのジフィー数（例: 1,000,000 または 1,000,000,000）を定数として返す `jiffies-per-second` を実装。
4. `(scheme time)` ライブラリ定義を更新し、R7RS 仕様通りのシグネチャで公開。
5. 単調増加性および経過時間の測定が期待通りであることを単体テストで検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `current-second` が現在のエポック秒（正の整数）を返す
- [ ] `current-jiffy` が単調増加し、経過時間計算が可能である
- [ ] `jiffies-per-second` が正の整数を返す
- [ ] `(scheme time)` が 100% 準拠（◎）として `ref_r7rs_compliance.md` に反映される
- [ ] `make test` を通過する


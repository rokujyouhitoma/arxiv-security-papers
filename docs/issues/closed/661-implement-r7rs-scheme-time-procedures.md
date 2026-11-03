---
ID: 661
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS §6.14 (scheme time) 高精度時間計測手続き群の完全準拠実装 (ID: 661)

## 1. 概要 / Summary
R7RS-small §6.14 (Time) および標準ライブラリ `(scheme time)` に規定される時間計測手続き群（`current-second`, `current-jiffy`, `jiffies-per-second`）を完全実装し、準拠率を 100%（◎）へ引き上げる。
現在、`(scheme time)` は基本的なダミー定数ラッパー（サポート率約 30% / △）にとどまっており、エポック秒（POSIX エポック秒）の正確な取得や、CPU タイマー/`CLOCK_MONOTONIC` に基づく高精度単調増加ジフィー（jiffy）の返却を確立する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-small §6.14: System interface (Time: `current-second`, `current-jiffy`, `jiffies-per-second`)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.3.14 システムインターフェース / §1.4 標準 16 ライブラリ別網羅表
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/posix.scm](../ulisp/lib/posix.scm) (POSIX clock_gettime システムコールラッパー: `sys-clock-gettime-realtime`, `sys-clock-gettime-monotonic`)
- [x] [ulisp/lib/scheme/time.sld](../ulisp/lib/scheme/time.sld) (ライブラリ定義・エクスポート・高精度実装)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../ulisp/docs/ref_r7rs_compliance.md) (R7RS 準拠状況テーブル更新: △ 約30% から ◎ 100%)
- [x] [ulisp/tests/test_r7rs_time.scm](../ulisp/tests/test_r7rs_time.scm) (新規単体テスト)
- [x] [ulisp/Makefile](../ulisp/Makefile) (テストターゲット統合)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/661-implement-r7rs-scheme-time-procedures`

1. **POSIX システムコール層 (`posix.scm`) の拡充**:
   - `sys-clock-gettime-realtime`:
     - Linux `sys_clock_gettime(CLOCK_REALTIME=0, &timespec)` (syscall 228) を実行。
     - エポック秒（Fixnum 整数）とナノ秒を取得。
   - `sys-clock-gettime-monotonic`:
     - Linux `sys_clock_gettime(CLOCK_MONOTONIC=1, &timespec)` (syscall 228) を実行。
     - 単調増加秒とナノ秒を取得。

2. **時間計測手続きの定義**:
   - `current-second`:
     - `(sys-clock-gettime-realtime)` からエポック秒（現在エポック秒整数）を返却。正の整数（> 1700000000）。
   - `jiffies-per-second`:
     - 1秒あたりのジフィー数として `1000000` (1マイクロ秒精度) を返却。
     - 61-bit Fixnum で数十万年間オーバーフローしない安全な解像度を確保。
   - `current-jiffy`:
     - `(sys-clock-gettime-monotonic)` から得られる秒とナノ秒を組み合わせ、`(+ (* sec 1000000) (quotient nsec 1000))` を算出。
     - 単調増加性を保証。

3. **`(scheme time)` ライブラリ定義更新**:
   - `ulisp/lib/scheme/time.sld` を更新し、上記手続きをエクスポート。

4. **単体テストの作成**:
   - `current-second` が正当なエポック秒（> 1700000000）を返すこと。
   - `current-jiffy` が呼び出し毎に単調増加（>= 前回値）すること。
   - 短いループ実行後の経過ジフィーが正の値となり、経過秒が算出可能であること。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `current-second` が現在の POSIX エポック秒（正の整数）を返す
- [x] `current-jiffy` が単調増加し、経過時間計算が可能である
- [x] `jiffies-per-second` が `1000000` を返す
- [x] `(scheme time)` が 100% 準拠（◎）として `ref_r7rs_compliance.md` に反映される
- [x] `make test` を通過する

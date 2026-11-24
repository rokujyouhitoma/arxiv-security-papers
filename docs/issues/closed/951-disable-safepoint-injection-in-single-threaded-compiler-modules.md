---
ID: 951
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] シングルスレッドのコンパイラ 4 モジュールにおける safepoint 注入無効化 (ID: 951)

## 1. 概要 / Summary

`ulisp-boot` / `ulisp-cc` の生成コードに `mfence` が 3,915 箇所残存している。調査の結果、**その全量がコンパイラ本体のモジュール 4 つ由来**であることを確認した（`build/*.s` の `mfence` 行数）。

| モジュール | `mfence` 数 | 入力生成行 (`ulisp/Makefile`) | `disable-pass` |
|---|---:|---|:---:|
| `compiler_base` | 1,943 | L1888 | なし |
| `frontend_passes` | 861 | L1901 | なし |
| `backend_passes` | 654 | L1927 | なし |
| `lir_passes` | 459 | L1914 | なし |
| `compiler_driver` | 0 | L1940 | **あり** |
| `c99_vm` / `c99_frontend` / `c99_driver` 等 | 0 | L1977 / L1991 / L2005 / L2019 | **あり** |

合計 3,917 行（うち 2 行はコード外の出現）で、`objdump` 実測値 3,915 と一致する。同じモジュール群 5 つ（`MODULAR_MODULES`, L2054）のうち `compiler_driver` だけに `(!disable-pass pass-synapse-inject-safepoints)` が付いており、残り 4 つは付け忘れていた。

コンパイラ本体（`compiler/` `frontend/` `lir/` `backend/` `driver/`）にはタスク生成やスケジューラ呼び出しがなく（`spawn-task` / `make-scheduler` / `run-scheduler` の参照 0 件）、シングルスレッドで動く。プリエンプション poll は不要で、純粋なオーバーヘッドになっている（関数入口・named-let バックエッジごとに `mfence` 1 回、数十サイクル）。

### スコープの整理（起票時からの変更点）

起票時は「safepoint 展開直後の冗長な `mov rax, 0x6f`（void）削除」も含めていたが、以下の理由で **[#956](../956-replace-safepoint-mfence-with-real-flag-poll-for-concurrent-builds.md) に移管**する。

- 既存の LIR ピープホール `rule-lir-dead-reg-overwrite-elim`（`lir/133_lir_peephole.scm` L56）が大半をすでに消している。`mfence` 3,915 箇所のうち、直後に `mov rax, 0x6f` が残るのは 1,032 箇所だけ。
- 残る箇所は、本 Issue で safepoint 自体が消えると同時に消える。
- safepoint を使うビルドでの void 代入の扱いは、poll 展開を作り直す #956 で一緒に設計するのが自然。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](../945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（計測基盤を共有）
  - [Issue #808](808-add-hardware-safepoint-preemption-tests-and-clean-makefile-disables.md)（Makefile 除外設定の整理）
  - [Issue #809](809-fix-safepoint-poll-lir-code-emission-and-add-aarch64-stub.md)（`mfence` 展開の導入経緯）
  - [Issue #810](810-deprecate-name-prefix-safepoint-exclusion-and-introduce-declare-no-safepoints.md)（`declare no-safepoints`）
  - [Issue #956](../956-replace-safepoint-mfence-with-real-flag-poll-for-concurrent-builds.md)（void 代入削除の移管先・並行ビルド向け実 poll）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [Makefile](../../../ulisp/Makefile) — L1888 / L1901 / L1914 / L1927 のモジュール入力生成 4 行（**唯一のソース変更**）
- [x] [bin/ulisp-boot](../../../ulisp/bin) — `bootstrap_verify_modular`（L2108-2126）で再生成されるシードバイナリ
- [x] [bin/ulisp-cc](../../../ulisp/bin) — `C_DRIVER_OBJS`（L2030-）で同じ `build/<module>.o` を使うため、自動的に恩恵を受ける
- 参照のみ:
  - [pass_inject_safepoints.scm](../../../ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm) — パス ID `pass-synapse-inject-safepoints`
  - [pass_manager.scm](../../../ulisp/compiler/pass_manager.scm) — `disable-pass!`（L802）
  - [129_lir_primitives.scm](../../../ulisp/lir/129_lir_primitives.scm) — L37-39 の poll 展開（変更しない）

### 影響しないもの
- `build/stage{1,2,3}_%.s`（L2067 / L2080 / L2093）は同じ `build/%_in.scm` を入力に使うため、4 行の修正だけで 3 段ブートストラップ全体に反映される。
- `test_preemption`（L482）など safepoint を有効にしたテストは別の入力生成を使っており、ユーザープログラム側の safepoint 注入は変わらない。

### セキュリティ観点
- 新しい入力経路やデータフローは追加しない。
- 影響はコンパイラ自身の実行時プリエンプション（未使用）に限られ、CWE-662（メモリ可視性）の前提になる並行実行がコンパイラにはないため、リスクはない。
- 将来コンパイラを並列化する（例: TU 並列コンパイルをタスクで行う）場合は、この設定の見直しが必要。Makefile のコメントに明記する。

---

## 4. 実装方針 / Implementation Plan

Target Branch: `perf/951-disable-safepoints-in-compiler-modules`

1. **ベースライン計測**（変更前・`main`）
   - `objdump -d bin/ulisp-boot | grep -c mfence`、`bin/ulisp-cc` も同様（期待値 3,915 / 3,915）
   - `ls -l` と `readelf -S` で ELF サイズ・`.text` サイズを記録
   - 自己コンパイル時間: `make -C ulisp bootstrap_verify_modular` の `stage3_*.s` 生成（`build/stage2-modular < build/<mod>_in.scm`）を 5 モジュール × 5 回計測し、中央値を取る（参考: `bin/ulisp-boot < build/lir_passes_in.scm` は real 8.96s / user 3.53s / sys 5.42s）
2. **Makefile の修正**: 4 行の `@echo` を次の形に揃える（`compiler_driver` L1940 と同じ書式）。
   ```make
   @echo '(!gc none) (!module-name compiler_base) (!disable-pass pass-synapse-inject-safepoints) (!import-sbi "build/meta/compiler_env.sbi")' > $@
   ```
   - `frontend_passes` / `lir_passes` / `backend_passes` も同様にする。
   - ブロック先頭（L1880 付近）に「コンパイラ本体はシングルスレッドのため safepoint 注入を無効化（#951）。並列化時は見直すこと」とコメントする。
3. **再ビルドと不動点検証**: `rm -f build/*_in.scm build/stage*_*.s` のあと `make -C ulisp bootstrap_verify_modular` を実行する。
   - stage1 は旧シード（`mfence` あり）でコンパイルされるが、出力は新しい入力に従うため `mfence` なしになる。stage2 == stage3 の 5 モジュール一致を確認する。
   - 成功すると `bin/ulisp-boot` が更新される。
4. **`ulisp-cc` の再リンク**: `make -C ulisp ulisp-cc` と、#932 の SHA-256 一致検証（`test_ulisp_cc` 系ターゲット）を実行する。
5. **事後計測**: 手順 1 と同じ項目を測り、差分表を本 Issue の「6. 計測結果」に追記する。
6. **品質ゲート**: `make format` / `make static_analysis` / `make test`（`test_preemption` / `test_pass_inject_safepoints` を含む）と `verify-quality-gates` を実行する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] 4 モジュール入力に `(!disable-pass pass-synapse-inject-safepoints)` が付与され、Makefile に理由のコメントがある
- [x] `build/{compiler_base,frontend_passes,lir_passes,backend_passes}.s` の safepoint 由来 `mfence` 命令が 0（`backend_passes.s` の 3 行は `.asciz "mfence"` リテラル）
- [x] `objdump -d bin/ulisp-boot | grep -c mfence` と `bin/ulisp-cc` の同じ計測がどちらも 3,915 → 1（safepoint 由来は 0、残 1 件は明示的 `ulisp_fn_reference_barrier`）
- [x] `bootstrap_verify_modular` で 5 モジュールすべての stage2 == stage3 が一致し、`bin/ulisp-boot` が更新済み
- [x] `ulisp-cc` の既存の SHA-256 一致検証（#932）が PASS
- [x] `test_preemption` / `test_pass_inject_safepoints`（safepoint 有効側）が引き続き PASS
- [x] 自己コンパイル時間（5 モジュール合計、中央値）が悪化しない。改善率を記録する
- [x] ELF / `.text` サイズの施策前後の差を記録する
- [x] `make format` / `make static_analysis` / `make test`（または `make check`）が全 PASS
- [x] `verify-quality-gates` 全 PASS（相対リンクのみ・絶対パス 0 件）

---

## 6. 計測結果 / Measurements

計測環境: Linux x86-64、2026-11-25。変更前 = `main` 3f838e355 のシード（退避コピー）、変更後 = 本ブランチの `bootstrap_verify_modular` で再生成したシード。

| 指標 | 変更前 | 変更後 | 差分 |
|---|---:|---:|---:|
| `ulisp-boot` `mfence` | 3,915 | 1 | −3,914 |
| `ulisp-cc` `mfence` | 3,915 | 1 | −3,914 |
| `ulisp-boot` ファイルサイズ | 13,267,568 B | 13,221,648 B | −45,920 B |
| `ulisp-boot` `.text` | 9,290,245 B | 9,247,973 B | −42,272 B |
| `ulisp-cc` ファイルサイズ | 16,667,360 B | 16,621,240 B | −46,120 B |
| `ulisp-cc` `.text` | 11,477,061 B | 11,434,789 B | −42,272 B |
| 自己コンパイル時間（5 モジュール合計・5 回中央値） | 22.32 s | 13.56 s | **−39.3%（1.65 倍）** |

- 残る `mfence` 1 箇所は `ulisp_fn_reference_barrier`（明示的なメモリフェンス）であり、safepoint 由来ではない。`build/backend_passes.s` の 3 行は、バックエンドが出力する文字列リテラル `"mfence"` である。
- 自己コンパイル時間は、新旧シードを交互に実行し、同一の入力（`build/<module>_in.scm` × 5、`ULISP_GC_PROFILE=compiler`）で計測した。各回の値: 旧 22.32 / 21.28 / 25.29 / 22.35 / 21.84 s、新 13.79 / 13.24 / 15.29 / 13.30 / 13.56 s。
- 時間短縮がサイズ削減（約 0.5%）よりずっと大きいのは、`mfence` 1 回あたりのコスト（数十サイクル、ストアバッファの排出）が、関数入口と named-let バックエッジという最頻出の実行経路で毎回かかっていたため。
- `bootstrap_verify_modular`: 5 モジュールすべてで stage2 == stage3 が一致（所要 51.4 s）。
- `test_ulisp_cc_native`（#932）: C99 / musl / Lua 33 TU の SHA-256 一致を含め全 PASS。`test_preemption` 102/102、`test_pass_inject_safepoints` 55/55 が PASS。

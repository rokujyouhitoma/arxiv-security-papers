---
ID: 605
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] bootstrap.sh におけるコンパイル失敗時の自動診断・詳細スタックトレース採取（Gauche/ILispフォールバック）機能の導入 (ID: 605)

## 1. 概要 / Summary
現在、`ulisp/bootstrap.sh` において Stage 1 等のコンパイルが失敗した場合、単に終了コードとアセンブリ出力ファイル（エラーメッセージが混入したもの）を出力して即座に終了する。
この際、ネイティブシード（`ulisp-boot`）がクラッシュした場合、エラーメッセージの断片しか得られず、開発者は手動で Gauche や Python ILisp 等を起動して詳細な例外トレースを取得する必要がある。

本 Issue では、`bootstrap.sh` のエラーハンドリングを強化し、コンパイル失敗を検知した際に自動的に詳細診断（Diagnostic Mode）をトリガーする機構を導入する。利用可能な Gauche や ILisp を用いて同一ファイルをトレース実行し、完全なソースコード行番号やバックトレースを付与した診断レポートを自動生成・出力することで、ブートストラップ障害時の解決時間を大幅に短縮する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ULisp ブートストラップ検証プロトコル](../../ulisp/docs/spec_pipeline.md)
- **関連 Issue**:
  - Issue 541: ブートストラップシード導入による高速ビルドパイプラインの構築
  - Issue 579: 3-Stage Bootstrap の固定点自動検証プロトコルの確立

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (`run_stage` における失敗時診断フックの追加)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (診断モードターゲットの追加)
- [ ] [docs/issues/README.md](../../docs/issues/README.md) (台帳更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/605-enhance-bootstrap-diagnostics-and-fallback-trace`

1. **`bootstrap.sh` への自動診断フックの実装**:
   - `run_stage` で非ゼロ終了コードまたは例外文字列を検知した際、`diagnose_stage_failure` 関数を呼び出す。
2. **Gauche / ILisp によるセカンドオピニオン診断**:
   - ネイティブバイナリで失敗した入力を、`gosh`（存在する場合）または `python3 -m ilisp` に即座に流し込み、詳細なスタックトレースとエラー位置を捕捉。
   - 診断結果をハイライト枠付きでターミナルに出力：
     ```text
     [DIAGNOSTIC ADVISORY] Stage 1 failed under native seed.
     Running diagnostic fallback trace via Gauche...
     ----------------------------------------------------------------------
     *** ERROR: Unbound variable: car in (my-filter pred ls) at list.scm:45
         Stack Trace:
           0: (lir-compile-variable 'car env)
           1: (lir-compile-expr '(car ls) ...)
     ----------------------------------------------------------------------
     ```
3. **フラグによる制御**:
   - `BOOTSTRAP_DIAGNOSE=0` で無効化可能にし、CI 環境等でのオーバーヘッドを抑える。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `bootstrap.sh` のコンパイル失敗時に、自動的に詳細な診断情報およびフォールバックトレースが提示されること。
- [ ] 正常時は追加のオーバーヘッドなくブートストラップが完遂すること。
- [ ] `bash ulisp/bootstrap.sh` の正常系が 100% PASS すること。

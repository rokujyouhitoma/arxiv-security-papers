---
ID: 567
種別: Feature
優先度: Medium
ステータス: Closed (Resolved)
---

# [FEAT/ENH] コンパイラ自己ホスト実行環境と一般ユーザースクリプト実行環境のGC実行プロファイル分離 (ID: 567)

## 1. 概要 / Summary
短時間で数百万〜数千万の短期生存オブジェクトをアロケーションする自己ホストAOTコンパイラ（Phase 2/3 Stage 1/2）と、長寿命オブジェクトや対話的・サーバー的動作を前提とする一般のユーザーランドスクリプトでは、最適なGC戦略が根本的に異なる。
コンパイラ自己ホストビルド時は大容量ナーサリ（256MB / 256MB / 4GB）プロファイル（`ULISP_GC_PROFILE=compiler` / `(!gc compiler)`）またはバンプアリーナ（`(!gc none)`）を適用し、生成されるユーザーバイナリは省メモリで頻繁にマイナーGCを回すプロファイル（ナーサリ4MB / 64MB / 1GB）をデフォルトとする実行プロファイル分離機構を確立した。

---

## 2. トレーサビリティ / Traceability
- 関連資料: Issue #530 (コンパイル時 GC 切り替え機構 (!gc ディレクティブ / --gc オプション) および Arena (GC-None) モードの実装), Issue #566 (成熟空間動的拡張ポリシーとmremap)
- 関連コンポーネント: uLisp コンパイラコア (`ulisp/compiler.scm`), バックエンド (`ulisp/passes/140_backend_x86_64.scm`), GCランタイム (`ulisp/lib/gc.scm`), Portable C ランタイム (`ulisp/runtime.c`), ブートストラップスクリプト (`ulisp/bootstrap.sh`), テストスイート (`ulisp/tests/test_gc_profile.scm`, `ulisp/test.sh`, `ulisp/test_c.sh`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/gc.scm](../../ulisp/lib/gc.scm) - 実行プロファイル管理アクセサ (`gc-profile-id`, `gc-current-profile`, `gc-init-profile!`)
- [x] [ulisp/passes/140_backend_x86_64.scm](../../ulisp/passes/140_backend_x86_64.scm) - ネイティブ `_start` における環境変数 `ULISP_GC_PROFILE` 走査 & プロファイル分岐
- [x] [ulisp/runtime.c](../../ulisp/runtime.c) - Portable C バックエンドにおける `ULISP_GC_PROFILE` 動的プロファイル初期化
- [x] [ulisp/tests/test_gc_profile.scm](../../ulisp/tests/test_gc_profile.scm) - 実行プロファイル単体テストスイート
- [x] [ulisp/Makefile](../../ulisp/Makefile) - `test_gc_profile` ターゲット統合
- [x] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) - コンパイラ自己ホストビルド時の `ULISP_GC_PROFILE=compiler` 自動適用
- [x] [ulisp/test.sh](../../ulisp/test.sh) - Step 26c としてプロファイルテスト統合

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/567-separate-compiler-and-userland-gc-execution-profiles`

1. **実行プロファイルの定義**:
   - `standard` プロファイル: ナーサリ 4MB, 成熟空間 64MB, 最大 1GB。一般スクリプト向け。頻繁なマイナーGCで省メモリ運用。
   - `compiler` プロファイル: ナーサリ 256MB, 成熟空間 256MB, 最大 4GB。短命な構文木変換を一括高速処理。
   - `server` プロファイル: ナーサリ 16MB, 成熟空間 256MB, 最大 4GB。動的拡張有効。
2. **CLIオプション / 環境変数 / ディレクティブ連携**:
   - ネイティブ x86_64 および Portable C の起動時に環境変数 `ULISP_GC_PROFILE` を解釈してプロファイルを自動設定。
   - `bootstrap.sh` 内の自己ホストビルドにおいて `ULISP_GC_PROFILE=compiler` を適用。
3. **テスト検証**:
   - ユーザーランドテストにおいて `standard` プロファイルが省メモリで動作し、環境変数指定で各プロファイルが正しくロードされることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] コンパイラ自己ホストブートストラップ実行時にGCスラッシングが発生せず、高速（サブ秒〜数秒）にビルドが完了すること。
- [x] 一般スクリプト実行時にメモリフットプリントが肥大化せず、定期的にGCが作動して省メモリ動作すること。
- [x] `./test.sh` および `./test_c.sh` の全テストが PASS すること。

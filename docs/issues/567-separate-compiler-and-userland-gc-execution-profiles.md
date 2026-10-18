---
ID: 567
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] コンパイラ自己ホスト実行環境と一般ユーザースクリプト実行環境のGC実行プロファイル分離 (ID: 567)

## 1. 概要 / Summary
短時間で数百万〜数千万の短期生存オブジェクトをアロケーションする自己ホストAOTコンパイラ（Phase 2/3 Stage 1/2）と、長寿命オブジェクトや対話的・サーバー的動作を前提とする一般のユーザーランドスクリプトでは、最適なGC戦略が根本的に異なる。
コンパイラ自己ホストビルド時はバンプアリーナ（`--gc=none` / `(!gc none)`）または大容量ナーサリ（512MB〜1GB）プロファイルを自動適用し、生成されるユーザーバイナリは省メモリで頻繁にマイナーGCを回すプロファイル（ナーサリ4MB〜16MB）をデフォルトとする実行プロファイル分離機構を確立する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: Issue #530 (コンパイル時 GC 切り替え機構 (!gc ディレクティブ / --gc オプション) および Arena (GC-None) モードの実装)
- 関連コンポーネント: uLisp コンパイラコア (`compiler.scm`), ブートストラップスクリプト (`bootstrap.sh`), ビルド定義 (`Makefile`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm)
- [ ] [ulisp/Makefile](../../ulisp/Makefile)
- [ ] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh)
- [ ] [ulisp/test.sh](../../ulisp/test.sh)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/567-separate-compiler-and-userland-gc-execution-profiles`

1. **実行プロファイルの定義**:
   - `standard` プロファイル: ナーサリ 4MB, 成熟空間 64MB。一般スクリプト向け。頻繁なマイナーGCで省メモリ運用。
   - `compiler` プロファイル: ナーサリ 512MB, 成熟空間 1GB（または Arena `--gc=none`）。短命な構文木変換を一括高速処理。
   - `server` プロファイル: ナーサリ 16MB, 成熟空間 256MB, 動的拡張有効。
2. **CLIオプション / 環境変数 / ディレクティブ連携**:
   - 環境変数 `ULISP_GC_PROFILE` または CLI 引数 `--profile=compiler` を解釈してランタイム初期化パラメータに反映。
   - `bootstrap.sh` 内の Stage 1 / Stage 2 / Stage 3 の生成および実行において `compiler` プロファイルまたは `(!gc none)` を明示的に適用。
3. **テスト検証**:
   - ユーザーランドテスト（R7RS 標準ライブラリ、各種データ構造テスト）において、`standard` プロファイルが正しくメモリを低フットプリントに抑えていることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] コンパイラ自己ホストブートストラップ実行時にGCスラッシングが発生せず、高速（サブ秒〜数秒）にビルドが完了すること。
- [ ] 一般スクリプト実行時にメモリフットプリントが肥大化せず、定期的にGCが作動して省メモリ動作すること。
- [ ] `./test.sh` および `./test_c.sh` の全テストが PASS すること。

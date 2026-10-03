---
ID: 429
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-10-04
---

# [FEAT] CLI ストリーム基底プロトコルと JSONL 入出力ハンドラーの実装 (ID: 429)

## 1. 概要 / Summary
`REQ-FR-09`（ツール間連携・標準ストリームインターフェース要求）および `DSN-01 Section 5.2`（CLI ストリームパイプラインプロトコル）に基づき、各サブコマンドで標準入出力（stdin/stdout）を行指向ストリーム（JSON Lines: `.jsonl`）として扱うための基底ハンドラー・プロトコル基盤を `src/cli/stream.py` に実装した。

本基底プロトコルにより、パイプ接続の自動検知、フラッシュ付き安全なシリアライズ、stderr への診断メッセージ完全分離、および `--on-error=skip|abort` によるエラー耐性ポリシーを一元管理する。

---

## 2. トレーサビリティ / Traceability
- 要求仕様書: [docs/requirements/REQ-01-system_requirements.md](../../requirements/REQ-01-system_requirements.md) (`REQ-FR-09`, `REQ-NFR-07`)
- 基本設計書: [docs/designs/DSN-01-high_level_design.md](../../designs/DSN-01-high_level_design.md) (`1.3 第5原則`, `5.2 CLI Stream Pipeline Protocol`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/cli/stream.py` (新規作成: StreamReader, StreamWriter, DiagnosticLogger, StreamErrorPolicy)
- [x] `tests/cli/test_stream.py` (新規単体テスト)
- [x] `docs/issues/README.md` (Issue台帳の管理)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/429-implement-cli-stream-base-and-jsonl-protocol`

1. **`StreamReader` クラスの実装**:
   - `sys.stdin` から 1行ずつ読み込み、空行をスキップしながら `json.loads` でパースして辞書オブジェクトを yield するジェネレータ。
   - `sys.stdin.isatty()` を判定し、パイプ入力状態をプロパティで提供。
2. **`StreamWriter` クラスの実装**:
   - 辞書オブジェクトを JSON 文字列化（`json.dumps(obj, ensure_ascii=False)`）し、改行を付与して `sys.stdout` に書き出し、即座に `flush()`。
3. **`DiagnosticLogger` クラスの実装**:
   - 進捗表示、バナー、警告、エラーをすべて `sys.stderr` に書き出すヘルパー。
4. **エラーハンドリング（`StreamErrorPolicy`）**:
   - `skip`: 不正な JSON 行を検出した場合に stderr に警告を出力して次の行を継続処理。
   - `abort`: 不正な行で即座に例外送出。
5. **テスト作成**:
   - 正常系 JSONL ストリーム送受信テスト、不正行スキップ/中断テスト、パイプ/TTY 判定テスト。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `src/cli/stream.py` が実装され、Pure Python 3.14+ 標準ライブラリのみで動作すること。
- [x] `StreamReader` と `StreamWriter` を用いた JSON Lines の逐次読み書きがデータ損失なく動作すること。
- [x] 診断ログが `sys.stderr` にのみ出力され、`sys.stdout` に混入しないこと。
- [x] 単体テストが作成され、`make test` および `make check_format`, `make static_analysis` (Xenon Rank A, mypy --strict) に全合格すること。

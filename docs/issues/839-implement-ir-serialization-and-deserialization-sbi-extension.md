---
ID: 839
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT] 中間表現 (HIR/MIR/LIR) の永続化・再ロード機構 (.sbi 拡張) の整備 (ID: 839)

## 1. 概要 / Summary
ULisp の中間バイナリフォーマットである `.sbi`（Scheme Binary Interface）の仕様を拡張・一般化し、型付き C 中間表現（HIR/MIR）や LIR モジュールの完全なスナップショットをディスクへ高速にシリアライズ（永続化）およびデシリアライズ（再ロード）できる機構を整備する。
これにより、musl の標準ヘッダ群（数万行の C ヘッダ）のパース・意味解析結果をプリコンパイル済みヘッダ（PCH: Precompiled Headers）としてキャッシュ可能にし、セルフホスト時のコンパイル時間を劇的に短縮する。さらに、Scheme/C 混在プロジェクトにおける中間表現レベルでのリンク時最適化（LTO: Link-Time Optimization）およびインタプリタ用事前解析キャッシュの基盤を確立する。

---

## 2. トレーサビリティ / Traceability
- **DSN-38**: §2 (B1: プリプロセッサ, §4: 未決事項 4 コンパイル速度), S6 性能改善
- **関連 Issue**: #826 (Typed LIR), #835 (Managed Dialect Separation)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/sbi.scm](../../ulisp/compiler/sbi.scm): `.sbi` フォーマット拡張およびシリアライザ/デシリアライザ
- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm): キャッシュ有効判定（ソースタイムスタンプ・ハッシュ検証）
- [ ] [ulisp/tests/test_ir_serialization.scm](../../ulisp/tests/test_ir_serialization.scm): ラウンドトリップ（シリアライズ→デシリアライズ）完全性検証

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/839-ir-serialization-sbi-extension`

1. 高速バイナリシリアライザの設計：
   - AST / LIR ノードのバイトコード表現（コンパクトな可変長整数 LEB128、シンボルテーブルのプール化）。
   - ポインタ循環のない DAG 構造のトポロジカルダンプ。
2. ヘッダ依存関係ハッシュの検証：
   - `#include` されたヘッダ群の SHA-256 チェックサムを `.sbi` ヘッダに埋め込み、不整合時の自動再パースを保証。
3. ドライバーへの統合：
   - `-include-pch <file.sbi>` または自動キャッシュオプションの実装。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 中間表現をシリアライズして再ロードしたオブジェクトが、元のインメモリ中間表現と 100% 同等のセマンティクスを保持すること（ラウンドトリップ検証合格）。
- [ ] 巨大なヘッダファイルを `.sbi` キャッシュからロードした場合、ゼロからのパースと比較して 5 倍以上のロード高速化が実証されること。
- [ ] 単体テスト `test_ir_serialization.scm` がパスすること。

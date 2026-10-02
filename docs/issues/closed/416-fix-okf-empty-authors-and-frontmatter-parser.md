---
ID: 416
種別: Bug
優先度: High
ステータス: Closed
完了日: 2026-10-03
---

# [BUG] 空 authors および OKF フロントマター PEG パース失敗による「unknown」タイトルおよびフロントマター漏洩要約の解消 (ID: 416)

## 1. 概要 / Summary
サマリーレポート（`outputs/executive_summaries/`）において、一部の論文（例: `iacr-2026-1547` など）のタイトルが `[unknown（セキュリティ分析論文）]` と表示され、要約欄に以下のように YAML フロントマターの断片がそのまま漏洩・混入して表示される不具合が発生していた：

```markdown
| 5 | iacr-2026-1547 | [unknown（セキュリティ分析論文）](...) | ... | 【提案】--- type: "security-paper" title: "Silent Distributed 暗号技術 for DNFs and Threshold Polic...。実証評価により実験的評価による防御性能と攻撃耐性の実証。 | cs.CR | [arXiv](...) &
```

### 再現手順 / Steps to Reproduce
1. `outputs/executive_summaries/03_monthly/monthly_2026-10-01.md` を開く
2. 行 55（No. 5: `iacr-2026-1547`）を確認する
3. タイトルが `[unknown（セキュリティ分析論文）]` となり、要約に `--- type: "security-paper" title: ...` が混入している

### 再現環境 / Environment
- OS: Linux
- Components: `src/pipeline/transformer/okf_serializer.py`, `grammars/yaml_frontmatter.peg`, `src/pipeline/transformer/generated_yaml_frontmatter_parser.py`, `src/pipeline/transformer/yaml_parser.py`, `src/pipeline/reporter/summary_generator.py`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/pipeline/transformer/okf_serializer.py](../../src/pipeline/transformer/okf_serializer.py): `authors` が空リスト時の `authors_yaml` フォールバック処理
- [x] [grammars/yaml_frontmatter.peg](../../grammars/yaml_frontmatter.peg): 空マッピング（`empty_mapping` / `nested_empty_mapping`）の文法定義追加
- [x] [src/pipeline/transformer/generated_yaml_frontmatter_parser.py](../../src/pipeline/transformer/generated_yaml_frontmatter_parser.py): AOT PEG コンパイラによるパーサー再生成
- [x] [src/pipeline/transformer/yaml_parser.py](../../src/pipeline/transformer/yaml_parser.py): PEG パース失敗時の安全な正規表現フォールバック抽出器の実装
- [x] [src/pipeline/reporter/summary_generator.py](../../src/pipeline/reporter/summary_generator.py): `_resolve_one_liner` におけるフロントマター除去サニタイズ
- [x] [outputs/executive_summaries/](../../outputs/executive_summaries/): 破損していた 02_daily, 03_monthly, 04_quarterly, 05_annual の再生成

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **シリアライザーでの空リスト処理不全**:
   - `src/pipeline/transformer/okf_serializer.py` において、`paper["authors"]` が空リスト（`[]`）の場合、`authors_yaml` が空文字列 `""` となる。
   - テンプレートが `authors:\n{authors_yaml}\ntrust:` となっているため、`authors:\n\ntrust:` という空行のみの不正な YAML 構造が出力されていた。
2. **PEG パーサー仕様の制約**:
   - `grammars/yaml_frontmatter.peg` では `nested_mapping` や `list_mapping` において、子要素が 1 つ以上存在することが必須（`+`）となっており、`authors:` のように値が空（または改行のみ）のケースに対応していなかった。
   - その結果、`YAMLFrontmatterParser` が `PEGSyntaxError` を発生させた。
3. **パース失敗時の空フォールバックと要約誤生成**:
   - `src/pipeline/transformer/yaml_parser.py` は `PEGSyntaxError` をキャッチすると単に空辞書 `{}` を返却していた。
   - `src/pipeline/reporter/summary_generator.py` の `_resolve_paper_title_and_desc` では、フロントマターから `title` が取得できないため `"unknown"` にフォールバックし、日本語タイトルが `"unknown（セキュリティ分析論文）"` となった。
   - さらに `_resolve_one_liner` では、`extracted_desc` がない場合に全文（先頭 1500 文字）を abstract とみなして `generate_structured_summary` を実行したため、先頭の YAML フロントマター（`--- type: "security-paper" ...`）が要約本文に取り込まれてしまった。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: なし
* **恒久対策 (Permanent Fix)**:
  1. `okf_serializer.py`: `authors` が空の場合は `authors:\n    - "N/A"` を出力するように修正。
  2. `yaml_frontmatter.peg`: 空マッピング（`empty_mapping` / `nested_empty_mapping`）を許容する文法規則を追加し、AOT コンパイル (`make compile_grammars`) で `generated_yaml_frontmatter_parser.py` を再生成。
  3. `yaml_parser.py`: PEG パース失敗時に、正規表現ベースの安全なフォールバック抽出を行い、`title`, `title_ja`, `description`, `tags` を確実に取得できるように多重防御（Defense-in-depth）を構築。
  4. `summary_generator.py`: 要約生成時に入力テキストからフロントマターブロック（`--- ... ---`）を確実に除去してから要約するように保護。
  5. 既存の不整合サマリーファイルを再生成・クリーンアップ。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/416-okf-empty-authors-frontmatter-parser`

1. `src/pipeline/transformer/okf_serializer.py` の修正。
2. `grammars/yaml_frontmatter.peg` に `empty_mapping` および `nested_empty_mapping` を追加し、PEG AOT コンパイルを実行。
3. `src/pipeline/transformer/yaml_parser.py` に `_fallback_regex_frontmatter` を実装。
4. `src/pipeline/reporter/summary_generator.py` の `_resolve_one_liner` でフロントマター除去を適用。
5. サマリーファイルを再生成し、`iacr-2026-1547` を含む全論文が正常に表示されることを検証。
6. 単体テストを追加し、`make check` を通過。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `iacr-2026-1547.md` のフロントマターが `parse_okf_frontmatter` で正しくパースされ、タイトル・要約が取得できること
- [x] サマリーテーブルに `unknown（セキュリティ分析論文）` や `--- type: "security-paper"` が出現しないこと
- [x] 02_daily, 03_monthly, 04_quarterly, 05_annual のサマリーが正しく更新されていること
- [x] `make test`, `make static_analysis` が PASS すること

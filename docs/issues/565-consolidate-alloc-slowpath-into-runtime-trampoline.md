---
ID: 565
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] %alloc インライン割当スローパスのランタイム・トランポリン集約化によるコードサイズ肥大化解消 (ID: 565)

## 1. 概要 / Summary
現在 `passes/140_backend_x86_64.scm` において、`%alloc` 命令ごとにナーサリ枯渇時のGC呼び出し・引数パッキング・戻り値アンパックのコードがインライン展開されている。これによりコンパイラ自己ホストバイナリ等の大規模コードでアセンブリ行数が急増（23万行→36万行）し、命令キャッシュミスやコンパイル速度低下を招く要因となっている。
これを抜本的に解消するため、各アロケーションサイトからは `cmp/jae` の高速インラインパスのみを残し、ナーサリ枯渇時は共通の `ulisp_alloc_slow_trampoline` 手続きに `call` するアウトオブライン（トランポリン）設計に集約する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: Issue #564 (バックエンド %alloc からの世代別コピーGC自動トリガーおよびスタックマップ回収ルーチンの直接結線)
- 関連コンポーネント: uLisp x86_64 AOT バックエンド、LIR コード生成器、コピーGCランタイム

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/140_backend_x86_64.scm](file:///workspace/arxiv-security-papers/ulisp/passes/140_backend_x86_64.scm)
- [ ] [ulisp/runtime/gc.s](file:///workspace/arxiv-security-papers/ulisp/runtime/gc.s)
- [ ] [ulisp/passes/130_lir.scm](file:///workspace/arxiv-security-papers/ulisp/passes/130_lir.scm)
- [ ] [ulisp/test.sh](file:///workspace/arxiv-security-papers/ulisp/test.sh)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/565-consolidate-alloc-slowpath-into-runtime-trampoline`

1. **共通トランポリン `ulisp_alloc_slow_trampoline` の新設**:
   - `ulisp/runtime/gc.s` に共通スローパストランポリンを定義。
   - レジスタ退避（アロケーションサイズ引数、アロケーション型タグ、リターンアドレス・スタックポインタ）を行い、GC コレクタ `ulisp_gc_minor_collect` を呼び出して再割り当て後のポインタを返却。
2. **バックエンド `%alloc` 生成のコンパクト化**:
   - `passes/140_backend_x86_64.scm` における `%alloc` コード生成を、サイズ比較 (`cmp %rax, %r15`) + 条件ジャンプ (`jae .Lalloc_slow_N`) + バンプポインタ加算のファストパスのみをインライン化。
   - スローパス `.Lalloc_slow_N` では引数レジスタをセットして `call ulisp_alloc_slow_trampoline` のみに集約。
3. **コードサイズ削減率の検証**:
   - Stage 1 / Stage 2 の出力 `.s` ファイルの行数・ファイルサイズを計測し、肥大化が大幅に解消されることを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 各 `%alloc` 発行箇所におけるスローパスコードが `call ulisp_alloc_slow_trampoline` に集約され、1アロケーションあたりの命令数が半減以下になること。
- [ ] Stage 1 / Stage 2 のアセンブリ行数の増大率が 5% 未満に抑制されること。
- [ ] `./test.sh` および `./test_c.sh` の全テストが PASS すること。

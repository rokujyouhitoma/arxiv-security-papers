---
ID: 565
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] %alloc インライン割当スローパスのランタイム・トランポリン集約化によるコードサイズ肥大化解消 (ID: 565)

## 1. 概要 / Summary
現在 `passes/140_backend_x86_64.scm` において、`%alloc` 命令ごとにナーサリ枯渇時のGC呼び出し・引数パッキング・戻り値アンパックのコードがインライン展開されていた。これにより各アロケーション箇所で約 30 命令が生成され、コンパイラ自己ホストバイナリ等の大規模コードでアセンブリ行数が急増（23万行→36万行）し、命令キャッシュミスやコンパイル速度低下を招く要因となっていた。
これを抜本的に解消するため、各アロケーションサイトからは `cmp/jbe` の高速インラインパス（9命令）のみを残し、ナーサリ枯渇時は共通の `ulisp_alloc_slow_trampoline` 手続きに `call` するアウトオブライン（トランポリン）設計に集約した。

---

## 2. トレーサビリティ / Traceability
- 関連資料: Issue #564 (バックエンド %alloc からの世代別コピーGC自動トリガーおよびスタックマップ回収ルーチンの直接結線)
- 関連コンポーネント: uLisp x86_64 AOT バックエンド (`passes/140_backend_x86_64.scm`), コピーGCランタイム (`emit-gc-collector`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/140_backend_x86_64.scm](../../ulisp/passes/140_backend_x86_64.scm): `%alloc` コード生成のトランポリン呼び出し化、および `ulisp_alloc_slow_trampoline` のランタイム出力
- [x] [ulisp/test.sh](../../ulisp/test.sh): ブートストラップ・アセンブリ行数およびバイナリ検証
- [x] [tests/test_bare_metal_ulisp.py](../../tests/test_bare_metal_ulisp.py): ベアメタル自動GCトリガー検証

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/565-consolidate-alloc-slowpath-into-runtime-trampoline`

1. **共通トランポリン `ulisp_alloc_slow_trampoline` の新設**:
   - `passes/140_backend_x86_64.scm` の `emit-gc-collector` 内に共通トランポリン `ulisp_alloc_slow_trampoline` を定義。
   - 呼び出し規約:
     - 呼び出し側で `sub rsp, shift`（16バイトアライン済み）を実行してから `call ulisp_alloc_slow_trampoline` を発行。
     - エントリ時: リターンアドレス push により `rsp % 16 == 8`。
     - `sub rsp, 88` により `rsp` を 16 バイトアライン。
     - レジスタ `rax, rcx, rdx, rsi, rdi, r8, r9, r10, r11` を退避し、`rdi = rsp`（ルートスタックトップ）を渡して `call ulisp_gc_collect`。
     - レジスタを完全復元し、`add rsp, 88` 後に `ret`。
2. **バックエンド `%alloc` 生成のコンパクト化**:
   - `passes/140_backend_x86_64.scm` の `%alloc` 命令生成ブロックを更新:
     ```x86asm
         lea r11, [r12 + bytes]
         cmp r11, [rip + ulisp_heap_limit]
         jbe .L_alloc_fast_N
         sub rsp, shift
         call ulisp_alloc_slow_trampoline
         add rsp, shift
     .L_alloc_fast_N:
         lea dst, [r12 + tag]
         add r12, bytes
         cmp r12, [rip + ulisp_heap_limit]
         ja ulisp_oom_panic
     ```
   - 1アロケーション箇所あたりの命令行数を約 30 行から 9 行（約 70% 削減）へ劇的に圧縮。
3. **品質検証**:
   - `tests/test_bare_metal_ulisp.py` による自動GC回収の動作確認 (10/10 PASS)。
   - `ulisp/test.sh` による Phase 1〜7 テストおよび自己ホストブートストラップの完全動作確認 (bit-for-bit IDENTICAL)。
   - Stage 1 / Stage 2 の `.s` 行数を計測し、236,848行への大幅削減を確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `%alloc` コード生成箇所から重複レジスタ退避・GC呼出コードが完全消去され、共通トランポリン呼び出しに集約されること。
- [x] 1アロケーション箇所あたりのコードサイズが 70% 削減されること。
- [x] 自動GCトリガーテスト (`tests/test_bare_metal_ulisp.py`) が 100% PASS すること。
- [x] `ulisp/test.sh` および `ulisp/test_c.sh` の全テストが PASS すること。
- [x] `make check_format` および `make static_analysis` の品質ゲートを 100% パスすること。

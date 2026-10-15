---
ID: 536
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] O(1) ランダムアクセス配列および高速ハッシュ辞書基盤向け R7RS ベクタ (vector) の完全実装 (ID: 536)

## 1. 概要 / Summary
現在の ULisp では、データ構造の大部分が線形リスト（ペアの連鎖）に依存しており、インデックスアクセスやシンボル辞書、インターンテーブルの走査に $O(N)$ の時間がかかっている。
コンパイラのシンボル解決やグラフ解析の規模拡大に伴い、$O(1)$ の時間計算量で任意要素にアクセス・更新できる固定長ポインタ配列（Vector）が不可欠となっている。
本 Issue では、R7RS Section 6.8（Vectors）に準拠したベクタ型 `vector`、`make-vector`, `vector-ref`, `vector-set!`, `vector-length`, `vector->list`, `list->vector` をネイティブ実装し、高速なハッシュテーブルやキャッシュテーブルの基盤を確立する。

---

## 2. トレーサビリティ / Traceability
- **関連規格**:
  - R7RS Section 6.8 (Vectors: `vector?`, `make-vector`, `vector`, `vector-ref`, `vector-set!`, `vector-length`)
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第3章 型システムおよび LIR 命令セット)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-36: 完全ベアメタル自己完結型 Freestanding 実行基盤](../designs/DSN-36-ulisp_baremetal_freestanding_pure_scheme_runtime.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/07_backend_x86_64.scm](../../ulisp/passes/07_backend_x86_64.scm) (ベクタ割当、ポインタスケールアクセス `[base + 8 + i*8]`)
- [ ] [ulisp/passes/07_backend_aarch64.scm](../../ulisp/passes/07_backend_aarch64.scm) (AArch64 向け `ldr`/`str` スケールアドレス生成)
- [ ] [ulisp/passes/04_closure_convert.scm](../../ulisp/passes/04_closure_convert.scm) (固定長環境ベクタによるクロージャ最適化)
- [ ] [ulisp/lib/vector.scm](../../ulisp/lib/vector.scm) (新規作成: ベクタ高水準変換ライブラリ)
- [ ] [ulisp/lib/gc.scm](../../ulisp/lib/gc.scm) (GC におけるベクタ要素（ポインタ配列）の全件トレース処理)
- [ ] [tests/test_bare_metal_ulisp.py](../../tests/test_bare_metal_ulisp.py) (ベクタ操作・GC 回収 E2E テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/536-ulisp-r7rs-vectors`

1. **ベクタのヒープレイアウト**:
   - ヘッダ: `[VECTOR_TAG(3-bit), length(61-bit)]` (8バイト)。
   - ペイロード: `length * 8` バイトの連続したポインタ（64-bit Scheme 値）領域。
2. **ハードウェアネイティブのインデックスアクセス**:
   - `vector-ref v i`: 境界検査 `0 <= i < length` を行った後、`mov rax, [rsi + 8 + rdi*8]` で 1 命令フェッチ。
   - `vector-set! v i val`: `mov [rsi + 8 + rdi*8], rdx` で格納。
3. **GC ポインタ追跡の統合**:
   - ベクタ内の全スロットは Scheme ポインタまたは即値であるため、GC のマーキング/コピー時に全スロット（0〜length-1）を再帰的にスキャンしてヒープ移動先アドレスへ書き換え。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(let ((v (make-vector 3 'init))) (vector-set! v 1 42) (vector-ref v 1))` が `42` を返すこと。
- [ ] `(vector-ref v 0)` が初期値 `'init` を返すこと。
- [ ] ベクタ内部に保持されたペアやクロージャが GC 後も正常に生存・参照可能であること。
- [ ] 自己ホスティング固定点ブートストラップが完全一致でパスすること。

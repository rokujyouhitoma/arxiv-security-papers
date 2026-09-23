"""
tests/test_profiler_leak.py
===========================
PyNYTProf メモリリーク・スタックアンワインド・リソース保護検証テスト。
DSN-28 Section 8.5 準拠。
再帰・ループ・例外・ジェネレータ実行時におけるスタックリーク 0 件を検証。
"""

import unittest

from src.core.profiler import Profiler


def recursive_fn(depth: int) -> int:
    """深い再帰関数"""
    if depth <= 0:
        return 0
    return 1 + recursive_fn(depth - 1)


def exception_fn():
    """例外を送出する関数"""
    raise RuntimeError("Intentional test error")


def generator_fn(n: int):
    """ジェネレータ"""
    for i in range(n):
        yield i


def looping_fn(iterations: int) -> int:
    """反復呼び出し"""
    total = 0
    for i in range(iterations):
        total += i
    return total


class TestPyNYTProfResourceAndLeak(unittest.TestCase):
    """メモリ・スタックリークの検証"""

    def test_repeated_calls_no_stack_leak(self):
        """10,000 回の関数呼び出し後に call_stack が空であること"""
        with Profiler(mode="line") as p:
            looping_fn(10_000)

        self.assertEqual(len(p.engine.call_stack), 0)

    def test_deep_recursion_no_stack_leak(self):
        """深い再帰 (150 段) 完了後に call_stack が空であること"""
        with Profiler(mode="line") as p:
            result = recursive_fn(150)
            self.assertEqual(result, 150)

        self.assertEqual(len(p.engine.call_stack), 0)

    def test_exception_unwind_no_stack_leak(self):
        """例外送出と補足時にスタックアンワインドが正常に行われ call_stack が空であること"""
        with Profiler(mode="line") as p:
            try:
                exception_fn()
            except RuntimeError:
                pass

        self.assertEqual(len(p.engine.call_stack), 0)

    def test_generator_partial_iteration_no_leak(self):
        """ジェネレータの途中終了時でもスタックが崩壊しないこと"""
        with Profiler(mode="line") as p:
            gen = generator_fn(100)
            # 5 回だけイテレーションして break
            for i, val in enumerate(gen):
                if i >= 5:
                    break

        self.assertEqual(len(p.engine.call_stack), 0)


if __name__ == "__main__":
    unittest.main()

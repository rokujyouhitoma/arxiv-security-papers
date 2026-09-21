"""
tests/core/test_pynytprof_engine.py
===================================
PyNYTProf コア計測エンジンおよびストレージ層の包括的単体テストスイート。
DSN-28 Section 4 & Section 8 準拠。
ゼロ外部依存: Python 標準 unittest ベース。
"""

import os
import tempfile
import unittest

from src.core.profiler import Profiler
from src.core.profiler.storage import ProfileStorage


def sample_leaf(x: int) -> int:
    """単機能のリーフ関数"""
    total = 0
    for i in range(x):
        total += i
    return total


def sample_caller(n: int) -> int:
    """内部で子関数を呼ぶ関数"""
    res = 0
    for _ in range(n):
        res += sample_leaf(100)
    return res


def recursive_fib(n: int) -> int:
    """再帰関数"""
    if n <= 1:
        return n
    return recursive_fib(n - 1) + recursive_fib(n - 2)


def sample_with_exception():
    """例外を送出する関数"""
    raise ValueError("Test intentional error")


class TestPyNYTProfEngine(unittest.TestCase):
    """PyNYTProf 計測エンジンの単体テスト"""

    def test_basic_subroutine_profiling(self):
        """サブルーチン呼び出しの回数と Inclusive/Exclusive 時間の計測検証"""
        with Profiler(mode="line") as p:
            val = sample_caller(5)
            self.assertGreater(val, 0)

        data = p.profile_data
        self.assertIsNotNone(data)

        # サブルーチンが存在すること
        subs = data.subroutines
        self.assertTrue(any("sample_caller" in s for s in subs))
        self.assertTrue(any("sample_leaf" in s for s in subs))

        caller_sub = next(s for name, s in subs.items() if "sample_caller" in name)
        leaf_sub = next(s for name, s in subs.items() if "sample_leaf" in name)

        # 呼び出し回数の検証
        self.assertEqual(caller_sub.calls, 1)
        self.assertEqual(leaf_sub.calls, 5)

        # 時間の整数精度と整合性
        self.assertIsInstance(caller_sub.inclusive_time_ns, int)
        self.assertIsInstance(caller_sub.exclusive_time_ns, int)
        self.assertGreaterEqual(
            caller_sub.inclusive_time_ns, caller_sub.exclusive_time_ns
        )
        self.assertGreaterEqual(
            caller_sub.inclusive_time_ns, leaf_sub.inclusive_time_ns
        )

        # Callers / Callees の双方向リンク検証
        self.assertTrue(any("sample_leaf" in c for c in caller_sub.callees))
        self.assertTrue(any("sample_caller" in c for c in leaf_sub.callers))

    def test_recursive_function_tracking(self):
        """再帰関数におけるスタック計算と丸め誤差ゼロの検証"""
        with Profiler(mode="sub", calls_mode=1) as p:
            res = recursive_fib(6)
            self.assertEqual(res, 8)

        data = p.profile_data
        self.assertIsNotNone(data)

        fib_subs = [
            s for name, s in data.subroutines.items() if "recursive_fib" in name
        ]
        self.assertEqual(len(fib_subs), 1)
        fib_sub = fib_subs[0]

        # fib(6) の総呼び出し回数は 25 回
        self.assertEqual(fib_sub.calls, 25)
        self.assertGreater(fib_sub.inclusive_time_ns, 0)
        self.assertGreaterEqual(fib_sub.exclusive_time_ns, 0)
        # 累積丸め誤差がなく、Inclusive >= Exclusive であること
        self.assertGreaterEqual(fib_sub.inclusive_time_ns, fib_sub.exclusive_time_ns)

    def test_line_level_profiling(self):
        """行単位の実行回数および所要時間計測の検証"""
        with Profiler(mode="line") as p:
            a = 1
            b = 2
            c = a + b
            self.assertEqual(c, 3)

        data = p.profile_data
        self.assertIsNotNone(data)
        self.assertGreater(len(data.lines), 0)

        # このテストファイル内の行が記録されていること
        this_file = __file__
        self.assertIn(this_file, data.lines)
        lines_dict = data.lines[this_file]
        self.assertGreaterEqual(len(lines_dict), 3)

        for lno, metric in lines_dict.items():
            self.assertGreaterEqual(metric.count, 1)
            self.assertIsInstance(metric.time_ns, int)
            self.assertGreaterEqual(metric.time_ns, 0)

    def test_exception_unwinding(self):
        """例外送出時でもスタックが崩壊せず正しく集計されることの検証"""
        with Profiler(mode="line") as p:
            try:
                sample_with_exception()
            except ValueError:
                pass

        data = p.profile_data
        self.assertIsNotNone(data)
        subs = data.subroutines
        self.assertTrue(any("sample_with_exception" in s for s in subs))
        exc_sub = next(s for name, s in subs.items() if "sample_with_exception" in name)
        self.assertEqual(exc_sub.calls, 1)
        self.assertGreater(exc_sub.inclusive_time_ns, 0)

    def test_storage_save_load_roundtrip(self):
        """zlib 圧縮付きストレージの保存と復元の可逆性検証"""
        with Profiler(mode="line", calls_mode=1) as p:
            sample_caller(3)

        original_data = p.profile_data
        self.assertIsNotNone(original_data)

        with tempfile.TemporaryDirectory() as tmpdir:
            out_file = os.path.join(tmpdir, "test.pynytprof.out")
            calls_file = os.path.join(tmpdir, "all_stacks_by_time.calls")

            # 保存
            ProfileStorage.save(original_data, out_file)
            self.assertTrue(os.path.isfile(out_file))
            self.assertGreater(os.path.getsize(out_file), 0)

            # 復元
            loaded_data = ProfileStorage.load(out_file)
            self.assertEqual(loaded_data.metadata.mode, original_data.metadata.mode)
            self.assertEqual(
                len(loaded_data.subroutines), len(original_data.subroutines)
            )
            self.assertEqual(len(loaded_data.lines), len(original_data.lines))

            # calls ファイル出力
            ProfileStorage.export_calls_file(original_data, calls_file)
            self.assertTrue(os.path.isfile(calls_file))
            with open(calls_file, "r", encoding="utf-8") as f:
                content = f.read()
                self.assertIn("sample_leaf", content)
                self.assertIn(" ", content)  # "<stack> <time>" 形式


if __name__ == "__main__":
    unittest.main()

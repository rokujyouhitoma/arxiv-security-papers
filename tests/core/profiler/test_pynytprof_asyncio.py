"""
tests/core/test_pynytprof_asyncio.py
====================================
PyNYTProf asyncio コルーチン対応・待機時間分離・マルチタスク追跡テスト。
DSN-28 Section 4.1 ＆ Phase 9 準拠。
"""

import asyncio
import os
import shutil
import tempfile
import unittest

from src.core.profiler import Profiler
from src.core.profiler.storage import ProfileStorage


async def sample_coroutine_worker(sleep_sec: float) -> int:
    """非同期スリープを伴うコルーチン"""
    await asyncio.sleep(sleep_sec)
    total = 0
    for i in range(100):
        total += i
    return total


async def sample_parent_coroutine():
    """子コルーチンを呼び出すコルーチン"""
    res1 = await sample_coroutine_worker(0.03)
    res2 = await sample_coroutine_worker(0.02)
    return res1 + res2


class TestPyNYTProfAsyncio(unittest.TestCase):
    """asyncio コルーチン・Await 待機時間分離プロファイリングの検証"""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_asyncio_coroutine_suspend_time_separation(self):
        """コルーチンの Await 待機時間 (suspend_time_ns) が分離計上されることの検証"""

        async def run_test():
            with Profiler(mode="line") as p:
                result = await sample_parent_coroutine()
                self.assertGreater(result, 0)
            return p.profile_data

        data = asyncio.run(run_test())
        self.assertIsNotNone(data)

        # サブルーチン集計に worker が存在すること
        subs = data.subroutines
        worker_metric = None
        for name, sub in subs.items():
            if "sample_coroutine_worker" in name:
                worker_metric = sub
                break

        self.assertIsNotNone(worker_metric, "sample_coroutine_worker should be tracked")
        assert worker_metric is not None

        # 呼び出し回数が 2 回であること
        self.assertEqual(worker_metric.calls, 2)

        # suspend_time_ns に合計 ~0.05 秒 (50,000,000 ns) の待機時間が計上されていること
        # (許容マージン: 30,000,000 ns 以上)
        self.assertGreater(
            worker_metric.suspend_time_ns,
            30_000_000,
            f"suspend_time_ns was {worker_metric.suspend_time_ns} ns",
        )

        # CPU Exclusive 時間は待機時間よりも大幅に小さいこと (10ms 未満)
        self.assertLess(
            worker_metric.exclusive_time_ns,
            10_000_000,
            f"exclusive_time_ns was {worker_metric.exclusive_time_ns} ns",
        )

    def test_asyncio_gather_concurrent_tasks_no_leak(self):
        """asyncio.gather による並行タスク実行時におけるスタックリーク 0 件の検証"""

        async def run_gather():
            with Profiler(mode="line") as p:
                results = await asyncio.gather(
                    sample_coroutine_worker(0.02),
                    sample_coroutine_worker(0.03),
                    sample_coroutine_worker(0.01),
                )
                self.assertEqual(len(results), 3)
            return p

        profiler_instance = asyncio.run(run_gather())
        # 全タスクスタックが正常にアンワインドされ空になっていること
        self.assertEqual(len(profiler_instance.engine.call_stack), 0)
        self.assertEqual(len(profiler_instance.engine._task_stacks), 0)

    def test_asyncio_suspend_time_storage_roundtrip(self):
        """suspend_time_ns が ProfileStorage 経由で正しく保存・復元されることの検証"""
        out_file = os.path.join(self.temp_dir, "async.out")

        async def run_save():
            with Profiler(output_file=out_file, mode="line") as p:
                await sample_coroutine_worker(0.02)
            return p.profile_data

        orig_data = asyncio.run(run_save())
        self.assertIsNotNone(orig_data)
        self.assertTrue(os.path.exists(out_file))

        loaded = ProfileStorage.load(out_file)
        worker_sub = None
        for name, sub in loaded.subroutines.items():
            if "sample_coroutine_worker" in name:
                worker_sub = sub
                break

        self.assertIsNotNone(worker_sub)
        assert worker_sub is not None
        self.assertGreater(worker_sub.suspend_time_ns, 15_000_000)


if __name__ == "__main__":
    unittest.main()

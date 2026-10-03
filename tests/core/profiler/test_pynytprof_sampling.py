"""
tests/core/test_pynytprof_sampling.py
======================================
PyNYTProf 統計的サンプリングエンジン (SamplingEngine / sampling.py) 単体テストスイート。
DSN-28 Section 4.5 準拠。
"""

import os
import shutil
import tempfile
import time
import unittest

from src.core.profiler.flamegraph import FlameGraphGenerator
from src.core.profiler.sampling import SamplingEngine, SamplingProfiler
from src.core.profiler.storage import ProfileStorage


def busy_work(duration_sec: float = 0.05) -> int:
    """一定時間 CPU を消費するワークロード"""
    end = time.perf_counter() + duration_sec
    count = 0
    while time.perf_counter() < end:
        count += 1
    return count


class TestPyNYTProfSampling(unittest.TestCase):
    """SamplingEngine および SamplingProfiler の単体テスト"""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_sampling_engine_timer_mode(self):
        """threading.Timer フォールバックモードの検証"""
        engine = SamplingEngine(interval_sec=0.005, use_signal=False)
        engine.start()
        busy_work(0.04)
        data = engine.stop()

        self.assertIsNotNone(data)
        self.assertEqual(data.metadata.mode, "sampling")
        self.assertGreater(engine.sample_count, 0)
        self.assertGreater(len(data.stack_traces), 0)

    def test_sampling_engine_signal_mode(self):
        """SIGPROF シグナル駆動モードの検証 (POSIX)"""
        engine = SamplingEngine(interval_sec=0.005, use_signal=True)
        engine.start()
        busy_work(0.04)
        data = engine.stop()

        self.assertIsNotNone(data)
        self.assertEqual(data.metadata.mode, "sampling")
        self.assertGreater(engine.sample_count, 0)
        self.assertGreater(len(data.stack_traces), 0)

    def test_sampling_profiler_context_manager(self):
        """SamplingProfiler コンテキストマネージャおよびファイル出力の検証"""
        out_file = os.path.join(self.temp_dir, "sample.pynytprof.out")
        with SamplingProfiler(
            interval_sec=0.005, output_file=out_file, use_signal=False
        ) as sp:
            busy_work(0.04)

        self.assertGreater(sp.sample_count, 0)
        self.assertIsNotNone(sp.profile_data)
        self.assertTrue(os.path.exists(out_file))

        # ProfileStorage.load で正しく復元できること
        loaded = ProfileStorage.load(out_file)
        self.assertEqual(loaded.metadata.mode, "sampling")
        self.assertGreater(len(loaded.stack_traces), 0)

    def test_sampling_flamegraph_compatibility(self):
        """サンプリングで得られた stack_traces が FlameGraphGenerator と互換であることの検証"""
        engine = SamplingEngine(interval_sec=0.005, use_signal=False)
        engine.start()
        busy_work(0.03)
        data = engine.stop()

        fg = FlameGraphGenerator()
        svg = fg.generate_svg(data, title="Sampling Flame Graph")
        self.assertIn("<svg", svg)
        self.assertIn("Sampling Flame Graph", svg)


if __name__ == "__main__":
    unittest.main()

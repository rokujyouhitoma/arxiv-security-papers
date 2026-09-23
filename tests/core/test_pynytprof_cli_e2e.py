"""
tests/core/test_pynytprof_cli_e2e.py
====================================
PyNYTProf CLI および環境変数インジェクションの包括的 E2E 統合テスト。
DSN-28 Section 7 & Section 8 準拠。
ゼロ外部依存: Python 標準 unittest & subprocess ベース。
"""

import os
import subprocess
import sys
import tempfile
import unittest

from src.core.profiler import parse_pynytprof_env


class TestPyNYTProfCLIE2E(unittest.TestCase):
    """CLI および環境変数連携の E2E 統合テスト"""

    def setUp(self):
        self.workspace_root = os.path.dirname(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        )
        self.launcher_prof = os.path.join(self.workspace_root, "tools", "pynytprof")
        self.launcher_html = os.path.join(self.workspace_root, "tools", "pynytprofhtml")

    def test_parse_pynytprof_env(self):
        """環境変数文字列のパース検証"""
        env_str = "file=custom.out:lines=0:calls=2:slowops=0"
        opts = parse_pynytprof_env(env_str)
        self.assertEqual(opts["file"], "custom.out")
        self.assertEqual(opts["mode"], "sub")
        self.assertEqual(opts["calls"], 2)
        self.assertFalse(opts["slowops"])

        # デフォルト値
        default_opts = parse_pynytprof_env("")
        self.assertEqual(default_opts["file"], "pynytprof.out")
        self.assertEqual(default_opts["mode"], "line")
        self.assertEqual(default_opts["calls"], 1)

    def test_cli_run_and_html_end_to_end(self):
        """tools/pynytprof でスクリプトを実行し、tools/pynytprofhtml でレポート生成する E2E 検証"""
        with tempfile.TemporaryDirectory() as tmpdir:
            # テスト用ターゲットスクリプト作成
            script_path = os.path.join(tmpdir, "work.py")
            with open(script_path, "w", encoding="utf-8") as f:
                f.write("""
def worker(n):
    return sum(i * i for i in range(n))

if __name__ == "__main__":
    import sys
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    res = worker(count)
    print(f"RESULT={res}")
""")

            out_prof = os.path.join(tmpdir, "test.pynytprof.out")
            html_dir = os.path.join(tmpdir, "report")

            # 1. tools/pynytprof run
            cmd_run = [
                sys.executable,
                self.launcher_prof,
                "run",
                "-o",
                out_prof,
                "--lines",
                script_path,
                "50",
            ]
            p_run = subprocess.run(
                cmd_run, capture_output=True, text=True, cwd=self.workspace_root
            )
            self.assertEqual(p_run.returncode, 0, f"Run stderr: {p_run.stderr}")
            self.assertIn("RESULT=40425", p_run.stdout)
            self.assertTrue(os.path.isfile(out_prof))

            # calls ファイルも生成されていること
            calls_file = os.path.join(tmpdir, "test.pynytprof.calls")
            self.assertTrue(os.path.isfile(calls_file))

            # 2. tools/pynytprofhtml
            cmd_html = [
                sys.executable,
                self.launcher_html,
                "-i",
                out_prof,
                "-d",
                html_dir,
            ]
            p_html = subprocess.run(
                cmd_html, capture_output=True, text=True, cwd=self.workspace_root
            )
            self.assertEqual(p_html.returncode, 0, f"HTML stderr: {p_html.stderr}")

            index_html = os.path.join(html_dir, "index.html")
            self.assertTrue(os.path.isfile(index_html))
            with open(index_html, "r", encoding="utf-8") as f:
                content = f.read()
                self.assertIn("worker", content)
                self.assertIn("Interactive Flame Graph", content)

    def test_cli_subcommands_flamegraph_and_callgrind(self):
        """flamegraph および callgrind サブコマンドの検証"""
        with tempfile.TemporaryDirectory() as tmpdir:
            script_path = os.path.join(tmpdir, "simple.py")
            with open(script_path, "w", encoding="utf-8") as f:
                f.write("def compute(): return sum(range(100))\ncompute()\n")

            out_prof = os.path.join(tmpdir, "prof.out")
            svg_file = os.path.join(tmpdir, "flame.svg")
            cg_file = os.path.join(tmpdir, "callgrind.out")

            # 実行
            subprocess.run(
                [sys.executable, self.launcher_prof, "-o", out_prof, script_path],
                check=True,
            )

            # flamegraph
            cmd_fg = [
                sys.executable,
                self.launcher_prof,
                "flamegraph",
                "-i",
                out_prof,
                "-o",
                svg_file,
            ]
            subprocess.run(cmd_fg, check=True)
            self.assertTrue(os.path.isfile(svg_file))
            with open(svg_file, "r", encoding="utf-8") as f:
                self.assertIn("<svg", f.read())

            # callgrind
            cmd_cg = [
                sys.executable,
                self.launcher_prof,
                "callgrind",
                "-i",
                out_prof,
                "-o",
                cg_file,
            ]
            subprocess.run(cmd_cg, check=True)
            self.assertTrue(os.path.isfile(cg_file))
            with open(cg_file, "r", encoding="utf-8") as f:
                self.assertIn("events: Nanoseconds", f.read())

    def test_cli_diff_subcommand(self):
        """diff サブコマンドおよび tools/pynytprofdiff ランチャーの検証"""
        launcher_diff = os.path.join(self.workspace_root, "tools", "pynytprofdiff")
        with tempfile.TemporaryDirectory() as tmpdir:
            script1 = os.path.join(tmpdir, "v1.py")
            with open(script1, "w", encoding="utf-8") as f:
                f.write("def work(): return sum(range(100))\nwork()\n")

            script2 = os.path.join(tmpdir, "v2.py")
            with open(script2, "w", encoding="utf-8") as f:
                f.write("def work(): return sum(range(1000))\nwork()\n")

            p1_out = os.path.join(tmpdir, "v1.out")
            p2_out = os.path.join(tmpdir, "v2.out")
            diff_dir = os.path.join(tmpdir, "diff_report")

            subprocess.run(
                [sys.executable, self.launcher_prof, "-o", p1_out, script1],
                check=True,
            )
            subprocess.run(
                [sys.executable, self.launcher_prof, "-o", p2_out, script2],
                check=True,
            )

            # tools/pynytprofdiff を直接実行
            cmd_diff = [
                sys.executable,
                launcher_diff,
                "--before",
                p1_out,
                "--after",
                p2_out,
                "-d",
                diff_dir,
                "--noise-threshold-ns",
                "0",
            ]
            p_diff = subprocess.run(
                cmd_diff, capture_output=True, text=True, cwd=self.workspace_root
            )
            self.assertEqual(p_diff.returncode, 0, f"Diff stderr: {p_diff.stderr}")

            diff_index = os.path.join(diff_dir, "index.html")
            self.assertTrue(os.path.isfile(diff_index))
            with open(diff_index, "r", encoding="utf-8") as f:
                content = f.read()
                self.assertIn("work", content)
                self.assertIn("Differential Profile Report", content)

    def test_cli_html_trace_filter(self):
        """html サブコマンドの --trace-filter オプション検証"""
        from src.core.profiler.storage import (
            ProfileData,
            ProfileMetadata,
            ProfileStorage,
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            prof_file = os.path.join(tmpdir, "traced.out")
            html_dir = os.path.join(tmpdir, "html_filtered")

            data = ProfileData(
                metadata=ProfileMetadata(
                    trace_id="4bf92f3577b34da6a3ce929d0e0e4736",
                    total_time_ns=1_000_000,
                )
            )
            ProfileStorage.save(data, prof_file)

            # 一致する trace_id の場合は PASS
            cmd_match = [
                sys.executable,
                self.launcher_prof,
                "html",
                "-i",
                prof_file,
                "-d",
                html_dir,
                "--trace-filter",
                "4bf92f3577b34da6a3ce929d0e0e4736",
            ]
            res_match = subprocess.run(
                cmd_match, capture_output=True, text=True, cwd=self.workspace_root
            )
            self.assertEqual(res_match.returncode, 0)
            self.assertTrue(os.path.isfile(os.path.join(html_dir, "index.html")))

            # 一致しない trace_id の場合は exit code 1
            cmd_mismatch = [
                sys.executable,
                self.launcher_prof,
                "html",
                "-i",
                prof_file,
                "-d",
                html_dir,
                "--trace-filter",
                "00000000000000000000000000000000",
            ]
            res_mismatch = subprocess.run(
                cmd_mismatch, capture_output=True, text=True, cwd=self.workspace_root
            )
            self.assertEqual(res_mismatch.returncode, 1)


if __name__ == "__main__":
    unittest.main()

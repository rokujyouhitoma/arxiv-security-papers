"""
Tests for Core Search Engine Storage Layer (src/search/engine/store/).
"""

import shutil
import tempfile

from search.engine.store import FSDirectory, RAMDirectory


def test_ram_directory_io():
    ram_dir = RAMDirectory()
    out = ram_dir.create_output("index.bin")
    out.write_string("lucene-core")
    out.write_int(12345)
    ram_dir.save_output("index.bin", out)

    assert ram_dir.file_exists("index.bin")
    assert "index.bin" in ram_dir.list_all()

    inp = ram_dir.open_input("index.bin")
    assert inp.read_string() == "lucene-core"
    assert inp.read_int() == 12345

    ram_dir.delete_file("index.bin")
    assert not ram_dir.file_exists("index.bin")


def test_fs_directory_io():
    temp_dir = tempfile.mkdtemp()
    try:
        fs_dir = FSDirectory(temp_dir)
        out = fs_dir.create_output("seg_0.dat")
        out.write_string("fs-directory-test")
        out.write_int(999)
        fs_dir.save_output("seg_0.dat", out)

        assert fs_dir.file_exists("seg_0.dat")
        inp = fs_dir.open_input("seg_0.dat")
        assert inp.read_string() == "fs-directory-test"
        assert inp.read_int() == 999

        fs_dir.delete_file("seg_0.dat")
        assert not fs_dir.file_exists("seg_0.dat")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

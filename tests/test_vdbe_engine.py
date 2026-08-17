#!/usr/bin/env python3
"""
Unit tests for SQLite-inspired 4-Tier Modular Vector DB Architecture:
1. OS Abstraction Layer (VFS)
2. Storage Backend Pager (PageCache, 4KB Pages, WAL)
3. VDBE Bytecode Virtual Machine (OpCodes, Statement, prepare/step/finalize)
4. Frontend SQL Compiler & Code Generator (EXPLAIN, Bytecode Disassembly)
"""

import os
import tempfile

import pytest

from database import (
    VDBE,
    CodeGenerator,
    DeterministicEmbedding,
    HNSWIndex,
    Instruction,
    MemoryVFS,
    OpCode,
    Page,
    PageCache,
    Pager,
    PosixVFS,
    SQLCompiler,
    Statement,
    StepResult,
    TableCatalog,
    VDBEProgram,
    VectorStorage,
    get_vfs,
)


def test_vfs_abstraction_posix_and_memory():
    # 1. Memory VFS
    mem_vfs = MemoryVFS()
    f_mem = mem_vfs.open("test.bin", mode="w+b")
    f_mem.write(0, b"VECTOR_DB_HEADER_MAGIC")
    assert f_mem.read(0, 9) == b"VECTOR_DB"
    assert f_mem.file_size() == 22
    f_mem.truncate(10)
    assert f_mem.file_size() == 10
    assert mem_vfs.exists("test.bin")
    mem_vfs.delete("test.bin")
    assert not mem_vfs.exists("test.bin")

    # 2. Posix VFS
    with tempfile.TemporaryDirectory() as tmpdir:
        posix_vfs = PosixVFS()
        p_path = os.path.join(tmpdir, "posix_test.bin")
        f_posix = posix_vfs.open(p_path, mode="w+b")
        f_posix.write(0, b"OKFVEC01")
        f_posix.sync()
        assert f_posix.file_size() == 8
        assert f_posix.read(0, 8) == b"OKFVEC01"
        f_posix.close()


def test_pager_and_page_cache_and_wal():
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = os.path.join(tmpdir, "pager_test.db")
        pager = Pager(file_path=db_path, cache_capacity=4)

        # 1. Write Page 0 and Page 1
        page0_data = b"PAGE_0_DATA" + b"\x00" * 4085
        page1_data = b"PAGE_1_DATA" + b"\x00" * 4085
        pager.write_page(0, page0_data)
        pager.write_page(1, page1_data)
        pager.flush_all()

        assert pager.page_count() == 2
        read_p0 = pager.read_page(0)
        assert read_p0.startswith(b"PAGE_0_DATA")

        # 2. WAL Transaction & Rollback
        pager.begin()
        pager.write_page(0, b"MODIFIED_PAGE_0" + b"\x00" * 4081)
        assert pager.read_page(0).startswith(b"MODIFIED_PAGE_0")
        pager.rollback()

        # Should revert to original
        assert pager.read_page(0).startswith(b"PAGE_0_DATA")

        # 3. WAL Commit
        pager.begin()
        pager.write_page(0, b"COMMITTED_PAGE_0" + b"\x00" * 4080)
        pager.commit()
        assert pager.read_page(0).startswith(b"COMMITTED_PAGE_0")

        pager.close()


def test_vdbe_bytecode_vm_and_prepared_statement():
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "vdbe_test.vdb")
        storage = VectorStorage(vdb_path, dim=4)
        index = HNSWIndex(dim=4)

        # Insert items into storage & index
        idx0 = storage.append([1.0, 0.0, 0.0, 0.0], {"id": "p1", "title": "Zero Trust"})
        idx1 = storage.append(
            [0.0, 1.0, 0.0, 0.0], {"id": "p2", "title": "Cryptography"}
        )
        index.add_item(idx0, [1.0, 0.0, 0.0, 0.0])
        index.add_item(idx1, [0.0, 1.0, 0.0, 0.0])

        table = TableCatalog(name="papers", storage=storage, index=index)
        context = {"table": table}

        # Construct VDBE Program manually
        prog = VDBEProgram()
        prog.add(OpCode.INIT)
        prog.add(
            OpCode.VECTOR, p2=1, p4=[1.0, 0.0, 0.0, 0.0], comment="Load query vector"
        )
        prog.add(OpCode.VECTOR_KNN, p1=1, p2=2, p4="vector", comment="ANN search")
        prog.add(OpCode.NEXT_ROW)
        prog.add(OpCode.HALT)

        vdbe = VDBE(program=prog, context=context)
        stmt = Statement(vdbe=vdbe)

        # Step through results
        rows = stmt.fetchall()
        assert len(rows) == 2
        assert rows[0][0] == "p1"  # Best match for [1.0, 0.0, 0.0, 0.0]
        assert rows[0][1] == "Zero Trust"

        # Test reset and step
        stmt.reset()
        first_row = stmt.fetchone()
        assert first_row is not None
        assert first_row[0] == "p1"

        stmt.finalize()


def test_sql_compiler_and_explain_disassembly():
    compiler = SQLCompiler()

    # 1. EXPLAIN SELECT query
    bytecode = compiler.explain(
        "SELECT id, title FROM papers WHERE category = 'Zero-Trust'"
    )
    assert len(bytecode) > 0
    opcodes = [inst["opcode"] for inst in bytecode]
    assert "Init" in opcodes
    assert "OpenRead" in opcodes
    assert "FilterEq" in opcodes
    assert "NextRow" in opcodes
    assert "Halt" in opcodes

    # 2. EXPLAIN KNN Vector query
    knn_bytecode = compiler.explain(
        "SELECT id, title FROM papers WHERE KNN(vector, [1.0, 0.0, 0.0, 0.0], 5)"
    )
    knn_opcodes = [inst["opcode"] for inst in knn_bytecode]
    assert "Vector" in knn_opcodes
    assert "VectorKNN" in knn_opcodes

    # 3. End-to-end Compile & Step Execution
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "compiler_test.vdb")
        storage = VectorStorage(vdb_path, dim=4)
        index = HNSWIndex(dim=4)

        idx0 = storage.append(
            [1.0, 0.0, 0.0, 0.0], {"id": "p1", "title": "Zero Trust Architecture"}
        )
        index.add_item(idx0, [1.0, 0.0, 0.0, 0.0])

        table = TableCatalog(name="papers", storage=storage, index=index)
        context = {"table": table}

        stmt = compiler.prepare(
            "SELECT id, title FROM papers WHERE KNN(vector, [1.0, 0.0, 0.0, 0.0], 1)",
            context=context,
        )
        res = stmt.fetchall()
        assert len(res) == 1
        assert res[0][0] == "p1"
        assert res[0][1] == "Zero Trust Architecture"
        stmt.finalize()

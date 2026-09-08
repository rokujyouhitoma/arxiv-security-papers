#!/usr/bin/env python3
"""
Unit tests for PropertyGraphEngine (CRUD, dual CSR adjacency indices, disk persistence).
"""

import os

from graph.engine import PropertyGraphEngine


def _build_test_graph(engine: PropertyGraphEngine) -> None:
    engine.add_vertex("Paper:1", label="Paper", properties={"title": "Paper One"})
    engine.add_vertex(
        "Attack:PromptInjection", label="AttackTechnique", properties={"name": "PI"}
    )
    engine.add_vertex(
        "Vuln:CWE-79", label="Vulnerability", properties={"severity": "High"}
    )
    engine.add_edge("Paper:1", "Attack:PromptInjection", label="ANALYZES", weight=1.0)
    engine.add_edge(
        "Attack:PromptInjection", "Vuln:CWE-79", label="EXPLOITS", weight=2.0
    )


def test_graph_engine_counts(tmp_path: object) -> None:
    db_file = os.path.join(str(tmp_path), "test_graph.vdb")
    with PropertyGraphEngine(storage_path=db_file) as engine:
        _build_test_graph(engine)
        assert engine.vertex_count == 3
        assert engine.edge_count == 2
        assert engine.get_vertex("Paper:1") is not None


def test_graph_engine_adjacency(tmp_path: object) -> None:
    db_file = os.path.join(str(tmp_path), "test_graph.vdb")
    with PropertyGraphEngine(storage_path=db_file) as engine:
        _build_test_graph(engine)
        assert len(engine.get_out_edges("Paper:1")) == 1
        assert len(engine.get_in_edges("Vuln:CWE-79")) == 1


def test_graph_engine_save_vdb(tmp_path: object) -> None:
    db_file = os.path.join(str(tmp_path), "test_graph.vdb")
    with PropertyGraphEngine(storage_path=db_file) as engine:
        _build_test_graph(engine)
        engine.save()
        assert os.path.exists(engine.v_path)
        assert os.path.exists(engine.e_path)


def test_graph_engine_sql(tmp_path: object) -> None:
    db_file = os.path.join(str(tmp_path), "test_graph.vdb")
    with PropertyGraphEngine(storage_path=db_file) as engine:
        _build_test_graph(engine)
        engine.save()
        res = engine.execute_sql("SELECT * FROM vertices")
        assert res["status"] == "ok"
        assert len(res["rows"]) == 3


def test_graph_engine_reload(tmp_path: object) -> None:
    db_file = os.path.join(str(tmp_path), "test_graph.vdb")
    with PropertyGraphEngine(storage_path=db_file) as engine:
        _build_test_graph(engine)
        engine.save()

    with PropertyGraphEngine(storage_path=db_file) as new_engine:
        assert new_engine.vertex_count == 3
        assert new_engine.edge_count == 2


def test_graph_engine_cascade_delete(tmp_path: object) -> None:
    db_file = os.path.join(str(tmp_path), "test_graph.vdb")
    with PropertyGraphEngine(storage_path=db_file) as engine:
        _build_test_graph(engine)
        assert engine.remove_vertex("Attack:PromptInjection")
        assert engine.vertex_count == 2
        assert engine.edge_count == 0

#!/usr/bin/env python3
"""
Unit tests for PropertyGraphEngine (CRUD, dual CSR adjacency indices, disk persistence).
"""

import os
from graph.engine import PropertyGraphEngine


def test_graph_engine_crud(tmp_path: object) -> None:
    db_file = os.path.join(str(tmp_path), "test_graph.db")
    engine = PropertyGraphEngine(storage_path=db_file)

    # 1. Add Vertices
    engine.add_vertex("Paper:1", label="Paper", properties={"title": "Paper One"})
    engine.add_vertex("Attack:PromptInjection", label="AttackTechnique", properties={"name": "PI"})
    engine.add_vertex("Vuln:CWE-79", label="Vulnerability", properties={"severity": "High"})

    assert engine.vertex_count == 3
    assert engine.get_vertex("Paper:1") is not None
    assert engine.get_vertex("Paper:1").get("title") == "Paper One"  # type: ignore

    # 2. Add Edges
    engine.add_edge("Paper:1", "Attack:PromptInjection", label="ANALYZES", weight=1.0)
    engine.add_edge("Attack:PromptInjection", "Vuln:CWE-79", label="EXPLOITS", weight=2.0)

    assert engine.edge_count == 2
    assert len(engine.get_out_edges("Paper:1")) == 1
    assert engine.get_out_edges("Paper:1")[0].dst_id == "Attack:PromptInjection"
    assert len(engine.get_in_edges("Vuln:CWE-79")) == 1
    assert engine.get_in_edges("Vuln:CWE-79")[0].src_id == "Attack:PromptInjection"

    # 3. Stats
    st = engine.stats()
    assert st["vertex_count"] == 3
    assert st["edge_count"] == 2
    assert st["vertex_labels"]["Paper"] == 1
    assert st["edge_predicates"]["EXPLOITS"] == 1

    # 4. Save and Reload
    engine.save()
    assert os.path.exists(db_file)

    new_engine = PropertyGraphEngine(storage_path=db_file)
    assert new_engine.vertex_count == 3
    assert new_engine.edge_count == 2
    assert new_engine.get_vertex("Attack:PromptInjection") is not None
    assert len(new_engine.get_out_edges("Attack:PromptInjection")) == 1

    # 5. Remove Vertex
    assert new_engine.remove_vertex("Attack:PromptInjection")
    assert new_engine.vertex_count == 2
    assert new_engine.edge_count == 0  # Cascade removed both incident edges

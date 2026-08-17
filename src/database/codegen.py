#!/usr/bin/env python3
"""
VDBE Bytecode Code Generator & Query Planner.
Transforms SQL AST nodes into optimized VDBEProgram bytecode instruction sequences.
"""

from typing import Any, Dict

from .sql.ast import (
    BeginStatement,
    CommitStatement,
    InsertStatement,
    RollbackStatement,
    SelectStatement,
    SQLStatement,
)
from .vdbe import Instruction, OpCode, VDBEProgram


class CodeGenerator:
    """
    Emits register-based VDBE bytecodes for SQL statements.
    """

    def generate(self, stmt: SQLStatement) -> VDBEProgram:
        program = VDBEProgram()
        program.add(OpCode.INIT, comment="Initialize VM")

        if isinstance(stmt, SelectStatement):
            self._compile_select(stmt, program)
        elif isinstance(stmt, InsertStatement):
            self._compile_insert(stmt, program)
        elif isinstance(stmt, BeginStatement):
            program.add(OpCode.BEGIN_TX)
        elif isinstance(stmt, CommitStatement):
            program.add(OpCode.COMMIT_TX)
        elif isinstance(stmt, RollbackStatement):
            program.add(OpCode.ROLLBACK_TX)

        program.add(OpCode.HALT, comment="Halt VM")
        return program

    def _compile_select(self, stmt: SelectStatement, program: VDBEProgram) -> None:
        if stmt.knn_query:
            # Vector KNN Path
            r_vec = 1
            program.add(
                OpCode.VECTOR,
                p2=r_vec,
                p4=stmt.knn_query["vector"],
                comment="Load query vector",
            )
            program.add(
                OpCode.VECTOR_KNN,
                p1=r_vec,
                p2=stmt.knn_query["top_k"],
                p4=stmt.knn_query["column"],
                comment="Execute HNSW ANN search",
            )
        else:
            # Sequential table scan
            program.add(OpCode.OPEN_READ, comment=f"Open table {stmt.table_name}")

        # Add filters
        for clause in stmt.where_clauses:
            if clause["operator"] == "=":
                program.add(
                    OpCode.FILTER_EQ,
                    p4=(clause["column"], clause["value"]),
                    comment=f"Filter {clause['column']} == {clause['value']}",
                )

        # Output cursor loop
        program.add(OpCode.NEXT_ROW, comment="Fetch result rows")

    def _compile_insert(self, stmt: InsertStatement, program: VDBEProgram) -> None:
        col_val_map = dict(zip(stmt.columns, stmt.values))
        program.add(
            OpCode.INSERT_ROW,
            p4=col_val_map,
            comment=f"Insert row into {stmt.table_name}",
        )

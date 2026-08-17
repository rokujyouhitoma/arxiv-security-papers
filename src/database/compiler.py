#!/usr/bin/env python3
"""
SQL Compiler & Statement Preparer.
Coordinates tokenizing, parsing, query planning, and VDBE bytecode generation
in conformity with the `sqlite3_prepare_v2` model.
"""

from typing import Any, Dict, List, Optional

from .codegen import CodeGenerator
from .sql.parser import SQLParser
from .vdbe import VDBE, Statement, VDBEProgram


class SQLCompiler:
    """
    Compiles SQL query strings into executable VDBE Statement objects.
    """

    def __init__(self) -> None:
        self.parser = SQLParser()
        self.codegen = CodeGenerator()

    def prepare(self, sql: str, context: Dict[str, Any]) -> Statement:
        """
        Compiles SQL into a prepared Statement (analogous to sqlite3_prepare_v2).
        """
        stmt_ast = self.parser.parse(sql)
        program = self.codegen.generate(stmt_ast)
        vdbe = VDBE(program=program, context=context)
        return Statement(vdbe=vdbe)

    def explain(self, sql: str) -> List[Dict[str, Any]]:
        """
        Disassembles and returns VDBE bytecode instructions (analogous to EXPLAIN <sql>).
        """
        stmt_ast = self.parser.parse(sql)
        program = self.codegen.generate(stmt_ast)
        instructions = []
        for addr, inst in enumerate(program.instructions):
            instructions.append(
                {
                    "addr": addr,
                    "opcode": inst.op.value,
                    "p1": inst.p1,
                    "p2": inst.p2,
                    "p3": inst.p3,
                    "p4": inst.p4,
                    "comment": inst.comment,
                }
            )
        return instructions

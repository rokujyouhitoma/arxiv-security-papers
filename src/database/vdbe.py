#!/usr/bin/env python3
"""
VDBE (Virtual Vector DataBase Engine) Bytecode Virtual Machine.
Register-based execution engine executing vector and relational opcodes
against underlying storage, HNSW indexes, and pagers.
"""

from dataclasses import dataclass
from enum import Enum
from typing import Any, Dict, List, Optional, Sequence, Tuple


class OpCode(str, Enum):
    # Lifecycle & Control
    INIT = "Init"
    HALT = "Halt"
    GOTO = "Goto"

    # Storage & Cursor
    OPEN_READ = "OpenRead"
    OPEN_WRITE = "OpenWrite"
    CLOSE = "Close"
    SEEK_ROWID = "SeekRowID"
    NEXT_ROW = "NextRow"

    # Register & Column Operations
    INTEGER = "Integer"
    STRING = "String"
    VECTOR = "Vector"
    COLUMN = "Column"
    RESULT_ROW = "ResultRow"

    # Vector ANN & Similarity
    VECTOR_KNN = "VectorKNN"
    VECTOR_COSINE = "VectorCosine"

    # Filtering
    FILTER_EQ = "FilterEq"
    FILTER_NE = "FilterNe"

    # DML & Schema
    INSERT_ROW = "InsertRow"
    UPDATE_ROW = "UpdateRow"
    DELETE_ROW = "DeleteRow"

    # Transaction (TCL)
    BEGIN_TX = "BeginTx"
    COMMIT_TX = "CommitTx"
    ROLLBACK_TX = "RollbackTx"


@dataclass
class Instruction:
    op: OpCode
    p1: int = 0
    p2: int = 0
    p3: int = 0
    p4: Any = None
    comment: str = ""


class StepResult(str, Enum):
    SQLITE_ROW = "SQLITE_ROW"
    SQLITE_DONE = "SQLITE_DONE"
    SQLITE_ERROR = "SQLITE_ERROR"


class VDBEProgram:
    """Bytecode program stream."""

    def __init__(self) -> None:
        self.instructions: List[Instruction] = []

    def add(
        self,
        op: OpCode,
        p1: int = 0,
        p2: int = 0,
        p3: int = 0,
        p4: Any = None,
        comment: str = "",
    ) -> int:
        idx = len(self.instructions)
        self.instructions.append(
            Instruction(op=op, p1=p1, p2=p2, p3=p3, p4=p4, comment=comment)
        )
        return idx


class VDBE:
    """
    Register-based Virtual Machine executing VDBE bytecodes.
    """

    def __init__(self, program: VDBEProgram, context: Dict[str, Any]) -> None:
        self.program = program
        self.context = context
        self.registers: Dict[int, Any] = {}
        self.pc: int = 0
        self.result_row: Optional[List[Any]] = None
        self.result_dict: Optional[Dict[str, Any]] = None
        self.error_message: Optional[str] = None
        self.is_halted: bool = False
        self._work_list: List[Dict[str, Any]] = []
        self._work_idx: int = 0

    def reset(self) -> None:
        self.registers.clear()
        self.pc = 0
        self.result_row = None
        self.result_dict = None
        self.error_message = None
        self.is_halted = False
        self._work_list.clear()
        self._work_idx = 0

    def step(self) -> StepResult:
        if self.is_halted:
            return StepResult.SQLITE_DONE

        instructions = self.program.instructions
        while self.pc < len(instructions):
            inst = instructions[self.pc]
            op = inst.op

            if op == OpCode.INIT:
                self.pc += 1

            elif op == OpCode.HALT:
                self.is_halted = True
                return StepResult.SQLITE_DONE

            elif op == OpCode.INTEGER:
                self.registers[inst.p2] = int(inst.p1)
                self.pc += 1

            elif op == OpCode.STRING:
                self.registers[inst.p2] = str(inst.p4)
                self.pc += 1

            elif op == OpCode.VECTOR:
                self.registers[inst.p2] = list(inst.p4)
                self.pc += 1

            elif op == OpCode.OPEN_READ:
                # p4: table catalog
                table = self.context.get("table")
                if table:
                    self._work_list = [
                        dict(meta, _idx=idx)
                        for idx, meta in enumerate(table.storage.metadata)
                    ]
                self._work_idx = 0
                self.pc += 1

            elif op == OpCode.VECTOR_KNN:
                # p1: query_vec reg, p2: top_k, p3: out reg, p4: col_name
                table = self.context.get("table")
                query_vec = self.registers.get(inst.p1, [])
                top_k = inst.p2
                if table and hasattr(table, "index"):
                    matches = table.index.search(query_vec, top_k=top_k)
                    self._work_list = []
                    for idx, score in matches:
                        if idx < len(table.storage.metadata):
                            meta = dict(table.storage.get_metadata(idx))
                            meta["score"] = round(score, 4)
                            meta["_idx"] = idx
                            self._work_list.append(meta)
                self._work_idx = 0
                self.pc += 1

            elif op == OpCode.FILTER_EQ:
                # p4: (column_name, expected_val)
                col, expected = inst.p4
                self._work_list = [
                    r for r in self._work_list if str(r.get(col)) == str(expected)
                ]
                self.pc += 1

            elif op == OpCode.RESULT_ROW:
                # p1: start reg, p2: count
                row = [self.registers.get(inst.p1 + i) for i in range(inst.p2)]
                self.result_row = row
                self.pc += 1
                return StepResult.SQLITE_ROW

            elif op == OpCode.NEXT_ROW:
                if self._work_idx < len(self._work_list):
                    current_item = self._work_list[self._work_idx]
                    self._work_idx += 1
                    self.result_dict = current_item
                    self.result_row = list(current_item.values())
                    return StepResult.SQLITE_ROW
                else:
                    self.pc += 1

            elif op == OpCode.INSERT_ROW:
                table = self.context.get("table")
                data = inst.p4
                if table:
                    vec = data.get("vector") or [0.0] * table.storage.dim
                    idx = table.storage.append(vec, data)
                    table.index.add_item(idx, vec)
                self.pc += 1

            elif op == OpCode.BEGIN_TX:
                pager = self.context.get("pager")
                if pager:
                    pager.begin()
                self.pc += 1

            elif op == OpCode.COMMIT_TX:
                pager = self.context.get("pager")
                if pager:
                    pager.commit()
                self.pc += 1

            elif op == OpCode.ROLLBACK_TX:
                pager = self.context.get("pager")
                if pager:
                    pager.rollback()
                self.pc += 1

            else:
                self.pc += 1

        self.is_halted = True
        return StepResult.SQLITE_DONE


class Statement:
    """
    Prepared statement object encapsulating VDBE bytecodes and execution state.
    Provides prepare -> step -> reset -> finalize lifecycle.
    """

    def __init__(self, vdbe: VDBE) -> None:
        self.vdbe = vdbe
        self._finalized = False

    def step(self) -> bool:
        """Executes next VM step. Returns True if row is available, False when done."""
        if self._finalized:
            raise RuntimeError("Statement is finalized")
        res = self.vdbe.step()
        return res == StepResult.SQLITE_ROW

    def fetchone(self) -> Optional[List[Any]]:
        if self._finalized:
            raise RuntimeError("Statement is finalized")
        if self.step():
            return self.vdbe.result_row
        return None

    def fetchall(self) -> List[List[Any]]:
        if self._finalized:
            raise RuntimeError("Statement is finalized")
        rows = []
        while self.step():
            if self.vdbe.result_row is not None:
                rows.append(list(self.vdbe.result_row))
        return rows

    def reset(self) -> None:
        if self._finalized:
            raise RuntimeError("Statement is finalized")
        self.vdbe.reset()

    def finalize(self) -> None:
        self.vdbe.reset()
        self._finalized = True

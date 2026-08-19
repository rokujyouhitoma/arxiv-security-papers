#!/usr/bin/env python3
"""
VDBE (Virtual Vector DataBase Engine) Bytecode Virtual Machine.
Register-based execution engine executing vector and relational opcodes
against underlying storage, HNSW indexes, and pagers.
"""

from dataclasses import dataclass
from enum import Enum
from typing import Any, Dict, List, Optional


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

    def _exec_const_op(self, inst: Instruction) -> None:
        op = inst.op
        if op == OpCode.INTEGER:
            self.registers[inst.p2] = int(inst.p1)
        elif op == OpCode.STRING:
            self.registers[inst.p2] = str(inst.p4)
        elif op == OpCode.VECTOR:
            self.registers[inst.p2] = list(inst.p4)
        self.pc += 1

    def _exec_open_read(self, inst: Instruction) -> None:
        table = self.context.get("table")
        if table:
            self._work_list = [
                dict(meta, _idx=idx) for idx, meta in enumerate(table.storage.metadata)
            ]
        self._work_idx = 0

    def _exec_vector_knn(self, inst: Instruction) -> None:
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

    def _exec_filter_eq(self, inst: Instruction) -> None:
        col, expected = inst.p4
        self._work_list = [
            r for r in self._work_list if str(r.get(col)) == str(expected)
        ]

    def _exec_insert_row(self, inst: Instruction) -> None:
        table = self.context.get("table")
        data = inst.p4
        if table:
            vec = data.get("vector") or [0.0] * table.storage.dim
            idx = table.storage.append(vec, data)
            table.index.add_item(idx, vec)

    def _exec_tx_op(self, inst: Instruction) -> None:
        pager = self.context.get("pager")
        if pager:
            if inst.op == OpCode.BEGIN_TX:
                pager.begin()
            elif inst.op == OpCode.COMMIT_TX:
                pager.commit()
            elif inst.op == OpCode.ROLLBACK_TX:
                pager.rollback()

    def _exec_next_row(self) -> Optional[StepResult]:
        if self._work_idx < len(self._work_list):
            current_item = self._work_list[self._work_idx]
            self._work_idx += 1
            self.result_dict = current_item
            self.result_row = list(current_item.values())
            return StepResult.SQLITE_ROW
        return None

    def _exec_data_or_cursor_op(self, inst: Instruction) -> Optional[StepResult]:
        op = inst.op
        if op == OpCode.OPEN_READ:
            self._exec_open_read(inst)
            return None
        if op == OpCode.VECTOR_KNN:
            self._exec_vector_knn(inst)
            return None
        if op == OpCode.FILTER_EQ:
            self._exec_filter_eq(inst)
            return None
        if op == OpCode.INSERT_ROW:
            self._exec_insert_row(inst)
            return None
        if op == OpCode.NEXT_ROW:
            return self._exec_next_row()
        return None

    def _exec_instruction(self, inst: Instruction) -> Optional[StepResult]:
        op = inst.op
        if op == OpCode.HALT:
            self.is_halted = True
            return StepResult.SQLITE_DONE
        if op == OpCode.INIT:
            self.pc += 1
            return None
        if op in (OpCode.INTEGER, OpCode.STRING, OpCode.VECTOR):
            self._exec_const_op(inst)
            return None
        if op in (OpCode.BEGIN_TX, OpCode.COMMIT_TX, OpCode.ROLLBACK_TX):
            self._exec_tx_op(inst)
            return None
        if op == OpCode.RESULT_ROW:
            self.result_row = [self.registers.get(inst.p1 + i) for i in range(inst.p2)]
            self.pc += 1
            return StepResult.SQLITE_ROW

        res = self._exec_data_or_cursor_op(inst)
        if res is not None:
            return res
        self.pc += 1
        return None

    def step(self) -> StepResult:
        if self.is_halted:
            return StepResult.SQLITE_DONE

        instructions = self.program.instructions
        while self.pc < len(instructions):
            res = self._exec_instruction(instructions[self.pc])
            if res is not None:
                return res

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

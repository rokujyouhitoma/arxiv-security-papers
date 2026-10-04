"""ILISP Core Data Types and Representation Specification.

This module defines the foundational AST and runtime data types for Kernel ILISP
adhering to R7RS-small Scheme semantics and Python zero-copy interop.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, Iterator, List, Optional, Sequence, Tuple, Union


@dataclass(frozen=True)
class SourceLocation:
    """Source map location recording line, column, and file origin."""

    file: str
    line: int
    col: int

    def __str__(self) -> str:
        return f"{self.file}:{self.line}:{self.col}"


class Symbol:
    """Interned Symbol for Lisp identifiers."""

    _table: dict[str, Symbol] = {}

    def __init__(self, name: str) -> None:
        self.name: str = name

    @classmethod
    def intern(cls, name: str) -> Symbol:
        """Retrieve or create a globally unique interned Symbol."""
        if name not in cls._table:
            cls._table[name] = cls(name)
        return cls._table[name]

    def __repr__(self) -> str:
        return self.name

    def __str__(self) -> str:
        return self.name

    def __eq__(self, other: object) -> bool:
        if isinstance(other, Symbol):
            return self.name == other.name
        return False

    def __hash__(self) -> int:
        return hash(self.name)


class NilType:
    """Singleton representing the empty list '()."""

    _instance: Optional[NilType] = None

    def __new__(cls) -> NilType:
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def __repr__(self) -> str:
        return "()"

    def __str__(self) -> str:
        return "()"

    def __bool__(self) -> bool:
        # In Scheme, the empty list is truthy!
        return True

    def __len__(self) -> int:
        return 0

    def __iter__(self) -> Iterator[Any]:
        return iter(())


NIL = NilType()


class EOFType:
    """Singleton representing the End-Of-File (EOF) marker."""

    _instance: Optional[EOFType] = None

    def __new__(cls) -> EOFType:
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def __repr__(self) -> str:
        return "#<eof>"

    def __str__(self) -> str:
        return "#<eof>"


EOF = EOFType()


def is_eof_object(obj: Any) -> bool:
    """Return True if obj is the EOF object."""
    return isinstance(obj, EOFType) or obj is EOF


class Cell:
    """Mutable box for lexical variables mutated by set!."""

    __slots__ = ("value",)

    def __init__(self, value: Any) -> None:
        self.value: Any = value

    def get(self) -> Any:
        return self.value

    def set(self, new_val: Any) -> Any:
        self.value = new_val
        return new_val

    def __repr__(self) -> str:
        return f"#<cell {self.value!r}>"


class Cons:
    """Cons cell representing an immutable or mutable pair in Lisp."""

    __slots__ = ("car", "cdr", "loc")

    def __init__(
        self, car: Any, cdr: Any, loc: Optional[SourceLocation] = None
    ) -> None:
        self.car: Any = car
        self.cdr: Any = cdr
        self.loc: Optional[SourceLocation] = loc

    def __repr__(self) -> str:
        elements: List[str] = []
        curr: Any = self
        while isinstance(curr, Cons):
            elements.append(repr(curr.car))
            curr = curr.cdr
        if curr is not NIL and not isinstance(curr, SequenceView):
            return f"({' '.join(elements)} . {curr!r})"
        if isinstance(curr, SequenceView):
            for item in curr:
                elements.append(repr(item))
        return f"({' '.join(elements)})"

    def __iter__(self) -> Iterator[Any]:
        curr: Any = self
        while isinstance(curr, Cons):
            yield curr.car
            curr = curr.cdr
        if isinstance(curr, SequenceView):
            yield from curr
        elif curr is not NIL:
            raise ValueError(f"Cannot iterate improper list ending with {curr!r}")

    def __eq__(self, other: object) -> bool:
        if isinstance(other, Cons):
            return bool(self.car == other.car and self.cdr == other.cdr)
        return False


class SequenceView:
    """O(1) lazy view over Python sequences (list/tuple) for zero-copy Scheme interop."""

    __slots__ = ("seq", "offset")

    def __init__(self, seq: Sequence[Any], offset: int = 0) -> None:
        self.seq: Sequence[Any] = seq
        self.offset: int = offset

    @property
    def car(self) -> Any:
        if self.offset >= len(self.seq):
            raise IndexError("car on empty SequenceView")
        return self.seq[self.offset]

    @property
    def cdr(self) -> Any:
        if self.offset + 1 >= len(self.seq):
            return NIL
        return SequenceView(self.seq, self.offset + 1)

    def __bool__(self) -> bool:
        return True

    def __len__(self) -> int:
        remaining = len(self.seq) - self.offset
        return max(0, remaining)

    def __iter__(self) -> Iterator[Any]:
        for i in range(self.offset, len(self.seq)):
            yield self.seq[i]

    def __repr__(self) -> str:
        elements = [repr(x) for x in self]
        return f"({' '.join(elements)})"


class Vector:
    """Fixed-length O(1) random-access vector adhering to R7RS-small."""

    __slots__ = ("elements",)

    def __init__(self, elements: Sequence[Any]) -> None:
        self.elements: List[Any] = list(elements)

    def __len__(self) -> int:
        return len(self.elements)

    def __getitem__(self, idx: int) -> Any:
        return self.elements[idx]

    def __setitem__(self, idx: int, value: Any) -> None:
        self.elements[idx] = value

    def __iter__(self) -> Iterator[Any]:
        return iter(self.elements)

    def __repr__(self) -> str:
        return f"#({' '.join(repr(x) for x in self.elements)})"

    def __eq__(self, other: object) -> bool:
        if isinstance(other, Vector):
            return self.elements == other.elements
        return False


class Bytevector:
    """Fixed/variable-length byte vector (0-255 octets) adhering to R7RS-small."""

    __slots__ = ("data",)

    def __init__(self, data: Union[bytes, bytearray, Sequence[int]] = b"") -> None:
        self.data: bytearray = bytearray(data)

    def __len__(self) -> int:
        return len(self.data)

    def __getitem__(self, idx: int) -> int:
        return self.data[idx]

    def __setitem__(self, idx: int, value: int) -> None:
        if not (0 <= value <= 255):
            raise ValueError(f"Bytevector value out of range (0-255): {value}")
        self.data[idx] = value

    def __iter__(self) -> Iterator[int]:
        return iter(self.data)

    def __repr__(self) -> str:
        elements = " ".join(str(b) for b in self.data)
        return f"#u8({elements})"

    def __str__(self) -> str:
        return repr(self)

    def __eq__(self, other: object) -> bool:
        if isinstance(other, Bytevector):
            return self.data == other.data
        return False


def is_bytevector(obj: Any) -> bool:
    """Return True if obj is a Bytevector."""
    return isinstance(obj, Bytevector)


class Char:
    """Scheme Character type adhering to R7RS-small."""

    __slots__ = ("val",)

    def __init__(self, val: str) -> None:
        if len(val) != 1:
            raise ValueError(f"Char must be a single character, got {val!r}")
        self.val: str = val

    def __eq__(self, other: object) -> bool:
        if isinstance(other, Char):
            return self.val == other.val
        if isinstance(other, str) and len(other) == 1:
            return self.val == other
        return False

    def __lt__(self, other: object) -> bool:
        if isinstance(other, Char):
            return self.val < other.val
        return NotImplemented

    def __le__(self, other: object) -> bool:
        if isinstance(other, Char):
            return self.val <= other.val
        return NotImplemented

    def __gt__(self, other: object) -> bool:
        if isinstance(other, Char):
            return self.val > other.val
        return NotImplemented

    def __ge__(self, other: object) -> bool:
        if isinstance(other, Char):
            return self.val >= other.val
        return NotImplemented

    def __hash__(self) -> int:
        return hash(self.val)

    def __repr__(self) -> str:
        if self.val == " ":
            return "#\\space"
        if self.val == "\n":
            return "#\\newline"
        if self.val == "\t":
            return "#\\tab"
        if self.val == "\r":
            return "#\\return"
        if self.val == "\0":
            return "#\\null"
        if self.val == "\a":
            return "#\\alarm"
        if self.val == "\b":
            return "#\\backspace"
        if self.val == "\x1b":
            return "#\\escape"
        if self.val == "\x7f":
            return "#\\delete"
        if not self.val.isprintable():
            return f"#\\x{ord(self.val):x}"
        return f"#\\{self.val}"

    def __str__(self) -> str:
        return self.val


def is_char(obj: Any) -> bool:
    """Return True if obj is a Scheme Char."""
    return isinstance(obj, Char)


class MutableString:
    """Mutable string container adhering to R7RS-small mutable string semantics."""

    __slots__ = ("_chars",)

    def __init__(
        self, initial: Union[str, Sequence[str], Sequence[Char], MutableString] = ""
    ) -> None:
        chars: List[str] = []
        if isinstance(initial, MutableString):
            chars = list(initial._chars)
        elif isinstance(initial, str):
            chars = list(initial)
        else:
            for item in initial:
                if isinstance(item, Char):
                    chars.append(item.val)
                elif isinstance(item, str):
                    chars.extend(list(item))
                else:
                    raise TypeError(f"Invalid character for MutableString: {item!r}")
        self._chars: List[str] = chars

    def __len__(self) -> int:
        return len(self._chars)

    def __getitem__(self, idx: int) -> str:
        return self._chars[idx]

    def __setitem__(self, idx: int, value: Union[str, Char]) -> None:
        val = value.val if isinstance(value, Char) else str(value)
        if len(val) != 1:
            raise ValueError(
                f"Expected single character for string element, got {val!r}"
            )
        self._chars[idx] = val

    def __iter__(self) -> Iterator[str]:
        return iter(self._chars)

    def __str__(self) -> str:
        return "".join(self._chars)

    def __repr__(self) -> str:
        return repr(self.__str__())

    def __eq__(self, other: object) -> bool:
        if isinstance(other, MutableString):
            return self._chars == other._chars
        if isinstance(other, str):
            return str(self) == other
        return False

    def __lt__(self, other: object) -> bool:
        if isinstance(other, (MutableString, str)):
            return str(self) < str(other)
        return NotImplemented

    def __le__(self, other: object) -> bool:
        if isinstance(other, (MutableString, str)):
            return str(self) <= str(other)
        return NotImplemented

    def __gt__(self, other: object) -> bool:
        if isinstance(other, (MutableString, str)):
            return str(self) > str(other)
        return NotImplemented

    def __ge__(self, other: object) -> bool:
        if isinstance(other, (MutableString, str)):
            return str(self) >= str(other)
        return NotImplemented

    def __hash__(self) -> int:
        return hash(str(self))


def is_string(obj: Any) -> bool:
    """Return True if obj is a Scheme string (immutable str or MutableString)."""
    return isinstance(obj, (str, MutableString))


def string_val(obj: Any) -> str:
    """Return the raw Python str representation of a Scheme string."""
    if isinstance(obj, MutableString):
        return str(obj)
    if isinstance(obj, str):
        return obj
    raise TypeError(f"Expected string, got {type(obj).__name__}: {obj!r}")


class Values:
    """R7RS multiple return values container."""

    __slots__ = ("values",)

    def __init__(self, *args: Any) -> None:
        self.values: Tuple[Any, ...] = args

    def __repr__(self) -> str:
        return f"#<values ({' '.join(repr(x) for x in self.values)})>"

    def __eq__(self, other: object) -> bool:
        if isinstance(other, Values):
            return self.values == other.values
        return False


class SchemeException(Exception):
    """Exception raised by R7RS (raise datum)."""

    def __init__(self, datum: Any) -> None:
        super().__init__(repr(datum))
        self.datum: Any = datum


class EscapeContinuation(Exception):
    """Exception thrown to unwind stack to a call/cc capture point."""

    def __init__(self, cont_id: str, value: Any) -> None:
        super().__init__(f"Escape to continuation {cont_id}")
        self.cont_id: str = cont_id
        self.value: Any = value


class Continuation:
    """One-shot first-class continuation created by call/cc."""

    def __init__(self, cont_id: str) -> None:
        self.cont_id: str = cont_id
        self.invoked: bool = False
        self.active: bool = True

    def __call__(self, value: Any = NIL) -> Any:
        if self.invoked or not self.active:
            raise RuntimeError(
                f"One-shot continuation {self.cont_id} cannot be invoked multiple times"
            )
        self.invoked = True
        raise EscapeContinuation(self.cont_id, value)

    def __repr__(self) -> str:
        return f"#<continuation {self.cont_id}>"


# Core Lisp Value type union
LispVal = Union[
    int,
    float,
    str,
    bool,
    Symbol,
    NilType,
    Cons,
    SequenceView,
    Vector,
    Values,
    Continuation,
    Cell,
    "Procedure",
    "Primitive",
]


class Procedure:
    """User-defined Scheme closure."""

    def __init__(
        self,
        params: Union[Symbol, List[Symbol]],
        body: List[Any],
        env: Any,
        is_macro: bool = False,
        rest_param: Optional[Symbol] = None,
        name: Optional[str] = None,
    ) -> None:
        self.params: Union[Symbol, List[Symbol]] = params
        self.body: List[Any] = body
        self.env: Any = env
        self.is_macro: bool = is_macro
        self.rest_param: Optional[Symbol] = rest_param
        self.name: Optional[str] = name

    def __call__(self, *args: Any) -> Any:
        from ilisp.evaluator import _apply_procedure

        return _apply_procedure(self, list(args))

    def __repr__(self) -> str:
        kind = "macro" if self.is_macro else "procedure"
        name_str = f" {self.name}" if self.name else ""
        return f"#<{kind}{name_str}>"


class Primitive:
    """Built-in primitive procedure wrapper."""

    def __init__(self, name: str, fn: Callable[..., Any]) -> None:
        self.name: str = name
        self.fn: Callable[..., Any] = fn

    def __call__(self, *args: Any) -> Any:
        return self.fn(*args)

    def __repr__(self) -> str:
        return f"#<primitive-procedure {self.name}>"


def is_pair(val: Any) -> bool:
    """Check if a value is a Cons pair or non-empty SequenceView."""
    if isinstance(val, Cons):
        return True
    if isinstance(val, SequenceView) and len(val) > 0:
        return True
    return False


def is_null(val: Any) -> bool:
    """Check if a value is the empty list NIL or empty SequenceView."""
    return val is NIL or (isinstance(val, SequenceView) and len(val) == 0)


def car(pair: Any) -> Any:
    """Return the car of a Cons cell or SequenceView."""
    if isinstance(pair, Cons):
        return pair.car
    if isinstance(pair, SequenceView):
        return pair.car
    raise TypeError(f"car expected pair, got {type(pair).__name__}: {pair!r}")


def cdr(pair: Any) -> Any:
    """Return the cdr of a Cons cell or SequenceView."""
    if isinstance(pair, Cons):
        return pair.cdr
    if isinstance(pair, SequenceView):
        return pair.cdr
    raise TypeError(f"cdr expected pair, got {type(pair).__name__}: {pair!r}")


def to_lisp_list(elements: Sequence[Any], loc: Optional[SourceLocation] = None) -> Any:
    """Convert a Python sequence to a Scheme Cons list."""
    result: Any = NIL
    for item in reversed(elements):
        result = Cons(item, result, loc=loc)
    return result


def to_py_list(val: Any) -> List[Any]:
    """Convert a Scheme proper list or SequenceView to a Python list."""
    res: List[Any] = []
    curr = val
    while is_pair(curr):
        res.append(car(curr))
        curr = cdr(curr)
    if not is_null(curr):
        raise TypeError(f"to_py_list expected proper list, got improper: {val!r}")
    return res


def unwrap_values(val: Any) -> Any:
    """Unwrap Values to its first element in single-value contexts, or NIL if empty."""
    if isinstance(val, Values):
        if len(val.values) >= 1:
            return val.values[0]
        return NIL
    return val

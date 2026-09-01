"""XRef Table and XRefStream resolver conforming to ISO 32000-1 Clause 7.5."""

import re
from typing import Any, Dict, List, Optional, Tuple, Union

from .contracts import IndirectRef, PdfStream, TokenType
from .decompress import StreamDecompressor
from .parser import PdfParser


class XRefResolver:
    """Resolves object byte offsets and unpacks Object Streams (ObjStm)."""

    def __init__(self, data: bytes) -> None:
        self.data = data
        self.length = len(data)
        self.offsets: Dict[int, int] = {}  # obj_num -> byte offset in self.data
        self.stm_parents: Dict[int, int] = {}  # obj_num -> container ObjStm obj_num
        self.stm_indices: Dict[int, int] = {}  # obj_num -> index inside ObjStm
        self.trailer: Dict[str, Any] = {}
        self.obj_cache: Dict[int, Any] = {}
        self.objstm_cache: Dict[int, Dict[int, Any]] = {}

    def locate_startxref(self) -> int:
        """Finds startxref byte offset from the tail of the PDF (ISO 32000-1 Clause 7.5.5)."""
        search_chunk = self.data[-4096:] if self.length > 4096 else self.data
        matches = list(re.finditer(rb"startxref\s+([0-9]+)", search_chunk))
        if not matches:
            raise ValueError("Invalid PDF: 'startxref' keyword not found in trailer")
        last_match = matches[-1]
        return int(last_match.group(1).decode("ascii"))

    def _step_parse_xref(self, cur_offset: int) -> Optional[int]:
        chunk = self.data[cur_offset : cur_offset + 64]
        if chunk.startswith(b"xref") or b"xref" in chunk[:10]:
            return self._parse_classic_xref_section(cur_offset)
        return self._parse_xref_stream_section(cur_offset)

    def parse_all_xrefs(self) -> None:
        """Traverses and merges all XRef tables / streams following /Prev chains."""
        cur_offset: Optional[int] = self.locate_startxref()
        visited_offsets = set()

        while cur_offset is not None and cur_offset not in visited_offsets:
            visited_offsets.add(cur_offset)
            if cur_offset >= self.length:
                break
            cur_offset = self._step_parse_xref(cur_offset)

    def _parse_classic_xref_section(self, offset: int) -> Optional[int]:
        parser = PdfParser(self.data[offset:])
        tok = parser.lexer.next_token()
        if not tok or tok[1] != "xref":
            return None
        self._read_classic_subsections_loop(parser)
        return self._extract_classic_trailer(parser)

    def _read_classic_subsections_loop(self, parser: PdfParser) -> None:
        while self._read_single_classic_subsection(parser):
            pass

    def _is_int_token(self, tok: Optional[Tuple[TokenType, Any]]) -> bool:
        return bool(tok and isinstance(tok[1], int))

    def _get_subsection_header(self, parser: PdfParser) -> Optional[Tuple[int, int]]:
        first_tok = parser.lexer.next_token()
        if not self._is_int_token(first_tok):
            return None
        count_tok = parser.lexer.next_token()
        if not self._is_int_token(count_tok):
            return None
        return first_tok[1], count_tok[1]  # type: ignore[index]

    def _read_single_classic_subsection(self, parser: PdfParser) -> bool:
        parser.lexer.skip_whitespace_and_comments()
        header = self._get_subsection_header(parser)
        if header is None:
            return False
        start_obj, count = header
        self._read_classic_xref_subsection(parser, start_obj, count)
        return True

    def _extract_classic_trailer(self, parser: PdfParser) -> Optional[int]:
        trailer_dict = parser.parse_object()
        if isinstance(trailer_dict, dict):
            for k, v in trailer_dict.items():
                if k not in self.trailer:
                    self.trailer[k] = v
            prev = trailer_dict.get("/Prev")
            if isinstance(prev, int):
                return prev
        return None

    def _apply_classic_entry(self, flag_tok: Any, off_tok: Any, obj_num: int) -> None:
        if str(flag_tok[1]) == "n" and obj_num not in self.offsets:
            self.offsets[obj_num] = int(off_tok[1])

    def _read_classic_entry(self, parser: PdfParser, obj_num: int) -> None:
        parser.lexer.skip_whitespace_and_comments()
        off_tok = parser.lexer.next_token()
        gen_tok = parser.lexer.next_token()
        flag_tok = parser.lexer.next_token()
        if off_tok and gen_tok and flag_tok:
            self._apply_classic_entry(flag_tok, off_tok, obj_num)

    def _read_classic_xref_subsection(
        self, parser: PdfParser, start_obj: int, count: int
    ) -> None:
        for i in range(count):
            self._read_classic_entry(parser, start_obj + i)

    def _parse_stream_dict_payload(
        self, parser: PdfParser, offset: int, stream_dict: Dict[str, Any]
    ) -> Optional[int]:
        for k, v in stream_dict.items():
            if k not in self.trailer:
                self.trailer[k] = v

        stream_bytes = self._extract_raw_stream_data(
            offset + parser.lexer.pos, stream_dict
        )
        decompressed = StreamDecompressor.decompress(
            stream_bytes,
            stream_dict.get("/Filter"),
            stream_dict.get("/DecodeParms"),
        )

        w = stream_dict.get("/W", [1, 2, 1])
        index_arr = stream_dict.get("/Index", [0, stream_dict.get("/Size", 0)])
        self._unpack_xref_entries(decompressed, w, index_arr)

        prev = stream_dict.get("/Prev")
        return int(prev) if isinstance(prev, int) else None

    def _parse_xref_stream_section(self, offset: int) -> Optional[int]:
        parser = PdfParser(self.data[offset:])
        parser.lexer.next_token()  # obj_num
        parser.lexer.next_token()  # gen_num
        kw_tok = parser.lexer.next_token()

        if not (kw_tok and kw_tok[1] == "obj"):
            return None

        stream_dict = parser.parse_object()
        if not isinstance(stream_dict, dict):
            return None

        return self._parse_stream_dict_payload(parser, offset, stream_dict)

    def _unpack_xref_entries(
        self, data: bytes, w: List[int], index_arr: List[int]
    ) -> None:
        stride = sum(w)
        if stride == 0 or len(data) < stride:
            return

        w1, w2, w3 = w[0], w[1], w[2]
        data_pos = 0

        for s_idx in range(0, len(index_arr), 2):
            start_num = index_arr[s_idx]
            count = index_arr[s_idx + 1]
            data_pos = self._unpack_section_entries(
                data, data_pos, stride, w1, w2, w3, start_num, count
            )

    def _store_xref_entry(self, e_type: int, f2: int, f3: int, obj_num: int) -> None:
        if e_type == 1 and obj_num not in self.offsets:
            self.offsets[obj_num] = f2
        elif e_type == 2 and obj_num not in self.stm_parents:
            self.stm_parents[obj_num] = f2
            self.stm_indices[obj_num] = f3

    def _unpack_single_entry(
        self, chunk: bytes, w1: int, w2: int, w3: int, stride: int, obj_num: int
    ) -> None:
        e_type = int.from_bytes(chunk[:w1], "big") if w1 > 0 else 1
        f2 = int.from_bytes(chunk[w1 : w1 + w2], "big") if w2 > 0 else 0
        f3 = int.from_bytes(chunk[w1 + w2 : stride], "big") if w3 > 0 else 0
        self._store_xref_entry(e_type, f2, f3, obj_num)

    def _unpack_section_entries(
        self,
        data: bytes,
        pos: int,
        stride: int,
        w1: int,
        w2: int,
        w3: int,
        start_num: int,
        count: int,
    ) -> int:
        cur_pos = pos
        for i in range(count):
            if cur_pos + stride > len(data):
                break
            chunk = data[cur_pos : cur_pos + stride]
            cur_pos += stride
            self._unpack_single_entry(chunk, w1, w2, w3, stride, start_num + i)
        return cur_pos

    def _find_stream_start(self, stream_start_pos: int) -> int:
        marker = b"stream"
        pos = self.data.find(marker, stream_start_pos)
        if pos == -1:
            return -1
        pos += len(marker)
        if self.data[pos : pos + 2] == b"\r\n":
            return pos + 2
        if self.data[pos : pos + 1] in (b"\r", b"\n"):
            return pos + 1
        return pos

    def _extract_until_endstream(self, pos: int) -> bytes:
        end_pos = self.data.find(b"endstream", pos)
        if end_pos == -1:
            return b""
        if self.data[end_pos - 2 : end_pos] == b"\r\n":
            return self.data[pos : end_pos - 2]
        if self.data[end_pos - 1 : end_pos] in (b"\r", b"\n"):
            return self.data[pos : end_pos - 1]
        return self.data[pos:end_pos]

    def _extract_raw_stream_data(
        self, stream_start_pos: int, stream_dict: Dict[str, Any]
    ) -> bytes:
        pos = self._find_stream_start(stream_start_pos)
        if pos == -1:
            return b""

        length = stream_dict.get("/Length")
        if isinstance(length, int) and pos + length <= self.length:
            return self.data[pos : pos + length]

        return self._extract_until_endstream(pos)

    def _parse_direct_stream_obj(
        self, offset: int, parsed_obj: Any, parser: PdfParser
    ) -> Any:
        parser.lexer.skip_whitespace_and_comments()
        if (
            isinstance(parsed_obj, dict)
            and parser.lexer.pos < parser.lexer.length
            and parser.lexer.data.startswith(b"stream", parser.lexer.pos)
        ):
            stream_raw = self._extract_raw_stream_data(
                offset + parser.lexer.pos, parsed_obj
            )
            return PdfStream(dictionary=parsed_obj, data=stream_raw)
        return parsed_obj

    def _resolve_direct_offset(self, ref: IndirectRef) -> Any:
        offset = self.offsets.get(ref.obj_num)
        if offset is None or offset >= self.length:
            return None

        parser = PdfParser(self.data[offset:])
        parser.lexer.next_token()  # obj_num
        parser.lexer.next_token()  # gen_num
        parser.lexer.next_token()  # obj keyword

        parsed_obj = parser.parse_object()
        res = self._parse_direct_stream_obj(offset, parsed_obj, parser)
        self.obj_cache[ref.obj_num] = res
        return res

    def resolve_object(self, ref: Union[IndirectRef, Any]) -> Any:
        """Resolves an indirect object reference to its underlying dictionary/array/stream."""
        if not isinstance(ref, IndirectRef):
            return ref

        if ref.obj_num in self.obj_cache:
            return self.obj_cache[ref.obj_num]

        if ref.obj_num in self.stm_parents:
            parent_num = self.stm_parents[ref.obj_num]
            unpacked = self._get_or_unpack_objstm(parent_num)
            res = unpacked.get(ref.obj_num)
            self.obj_cache[ref.obj_num] = res
            return res

        return self._resolve_direct_offset(ref)

    def _parse_objstm_entries(
        self, parser: PdfParser, n_count: int
    ) -> List[Tuple[int, int]]:
        entries: List[Tuple[int, int]] = []
        for _ in range(n_count):
            onum = parser.parse_object()
            off = parser.parse_object()
            if isinstance(onum, int) and isinstance(off, int):
                entries.append((onum, off))
        return entries

    def _get_or_unpack_objstm(self, objstm_num: int) -> Dict[int, Any]:
        if objstm_num in self.objstm_cache:
            return self.objstm_cache[objstm_num]

        parent_stm = self.resolve_object(IndirectRef(objstm_num, 0))
        if not isinstance(parent_stm, PdfStream):
            return {}

        decompressed = StreamDecompressor.decompress(
            parent_stm.data,
            parent_stm.dictionary.get("/Filter"),
            parent_stm.dictionary.get("/DecodeParms"),
        )

        n_count = parent_stm.dictionary.get("/N", 0)
        first_offset = parent_stm.dictionary.get("/First", 0)

        parser = PdfParser(decompressed)
        entries = self._parse_objstm_entries(parser, n_count)

        results: Dict[int, Any] = {}
        for onum, off in entries:
            obj_parser = PdfParser(decompressed[first_offset + off :])
            results[onum] = obj_parser.parse_object()

        self.objstm_cache[objstm_num] = results
        return results

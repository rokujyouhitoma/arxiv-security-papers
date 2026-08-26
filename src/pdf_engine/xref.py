"""XRef Table and XRefStream resolver conforming to ISO 32000-1 Clause 7.5."""

import re
from typing import Any, Dict, List, Optional, Tuple, Union

from .contracts import IndirectRef, PdfStream
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

    def parse_all_xrefs(self) -> None:
        """Traverses and merges all XRef tables / streams following /Prev chains."""
        cur_offset: Optional[int] = self.locate_startxref()
        visited_offsets = set()

        while cur_offset is not None and cur_offset not in visited_offsets:
            visited_offsets.add(cur_offset)
            if cur_offset >= self.length:
                break

            # Check if this offset points to a classic 'xref' keyword or an XRefStream object
            chunk = self.data[cur_offset : cur_offset + 64]
            if chunk.startswith(b"xref") or b"xref" in chunk[:10]:
                cur_offset = self._parse_classic_xref_section(cur_offset)
            else:
                cur_offset = self._parse_xref_stream_section(cur_offset)

    def _parse_classic_xref_section(self, offset: int) -> Optional[int]:
        parser = PdfParser(self.data[offset:])
        tok = parser.lexer.next_token()
        if not tok or tok[1] != "xref":
            return None

        self._read_classic_subsections_loop(parser)
        return self._extract_classic_trailer(parser)

    def _read_classic_subsections_loop(self, parser: PdfParser) -> None:
        while True:
            parser.lexer.skip_whitespace_and_comments()
            first_tok = parser.lexer.next_token()
            if (
                not first_tok
                or first_tok[1] == "trailer"
                or not isinstance(first_tok[1], int)
            ):
                break

            start_obj = first_tok[1]
            count_tok = parser.lexer.next_token()
            if not count_tok or not isinstance(count_tok[1], int):
                break
            self._read_classic_xref_subsection(parser, start_obj, count_tok[1])

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

    def _read_classic_xref_subsection(
        self, parser: PdfParser, start_obj: int, count: int
    ) -> None:
        for i in range(count):
            parser.lexer.skip_whitespace_and_comments()
            off_tok = parser.lexer.next_token()
            gen_tok = parser.lexer.next_token()
            flag_tok = parser.lexer.next_token()

            if off_tok and gen_tok and flag_tok:
                obj_num = start_obj + i
                byte_offset = int(off_tok[1])
                flag = str(flag_tok[1])
                if flag == "n" and obj_num not in self.offsets:
                    self.offsets[obj_num] = byte_offset

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

        # Merge trailer info
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

            e_type = int.from_bytes(chunk[:w1], "big") if w1 > 0 else 1
            f2 = int.from_bytes(chunk[w1 : w1 + w2], "big") if w2 > 0 else 0
            f3 = int.from_bytes(chunk[w1 + w2 : stride], "big") if w3 > 0 else 0
            obj_num = start_num + i

            if e_type == 1 and obj_num not in self.offsets:
                self.offsets[obj_num] = f2
            elif e_type == 2 and obj_num not in self.stm_parents:
                self.stm_parents[obj_num] = f2
                self.stm_indices[obj_num] = f3
        return cur_pos

    def _extract_raw_stream_data(
        self, stream_start_pos: int, stream_dict: Dict[str, Any]
    ) -> bytes:
        marker = b"stream"
        pos = self.data.find(marker, stream_start_pos)
        if pos == -1:
            return b""
        pos += len(marker)
        if self.data[pos : pos + 2] == b"\r\n":
            pos += 2
        elif self.data[pos : pos + 1] in (b"\r", b"\n"):
            pos += 1

        length = stream_dict.get("/Length")
        if isinstance(length, int) and pos + length <= self.length:
            return self.data[pos : pos + length]

        end_pos = self.data.find(b"endstream", pos)
        if end_pos != -1:
            # Strip trailing newline before endstream
            if self.data[end_pos - 2 : end_pos] == b"\r\n":
                return self.data[pos : end_pos - 2]
            if self.data[end_pos - 1 : end_pos] in (b"\r", b"\n"):
                return self.data[pos : end_pos - 1]
            return self.data[pos:end_pos]

        return b""

    def resolve_object(self, ref: Union[IndirectRef, Any]) -> Any:
        """Resolves an indirect object reference to its underlying dictionary/array/stream."""
        if not isinstance(ref, IndirectRef):
            return ref

        if ref.obj_num in self.obj_cache:
            return self.obj_cache[ref.obj_num]

        # Case A: Stored in an Object Stream (ObjStm)
        if ref.obj_num in self.stm_parents:
            parent_num = self.stm_parents[ref.obj_num]
            unpacked = self._get_or_unpack_objstm(parent_num)
            res = unpacked.get(ref.obj_num)
            self.obj_cache[ref.obj_num] = res
            return res

        # Case B: Direct byte offset in XRef table
        offset = self.offsets.get(ref.obj_num)
        if offset is None or offset >= self.length:
            return None

        parser = PdfParser(self.data[offset:])
        parser.lexer.next_token()  # obj_num
        parser.lexer.next_token()  # gen_num
        parser.lexer.next_token()  # obj keyword

        parsed_obj = parser.parse_object()

        # Check if a stream follows this object dictionary
        parser.lexer.skip_whitespace_and_comments()
        if (
            isinstance(parsed_obj, dict)
            and parser.lexer.pos < parser.lexer.length
            and parser.lexer.data.startswith(b"stream", parser.lexer.pos)
        ):
            stream_raw = self._extract_raw_stream_data(
                offset + parser.lexer.pos, parsed_obj
            )
            parsed_obj = PdfStream(dictionary=parsed_obj, data=stream_raw)

        self.obj_cache[ref.obj_num] = parsed_obj
        return parsed_obj

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

        # Parse index header: (obj_num offset) * N
        parser = PdfParser(decompressed)
        entries: List[Tuple[int, int]] = []
        for _ in range(n_count):
            onum = parser.parse_object()
            off = parser.parse_object()
            if isinstance(onum, int) and isinstance(off, int):
                entries.append((onum, off))

        results: Dict[int, Any] = {}
        for onum, off in entries:
            obj_parser = PdfParser(decompressed[first_offset + off :])
            results[onum] = obj_parser.parse_object()

        self.objstm_cache[objstm_num] = results
        return results

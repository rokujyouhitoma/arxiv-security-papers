"""Document tree navigation, page extraction, and resource resolution conforming to ISO 32000-1 Clause 7.7."""

from typing import Any, Dict, List, Optional, Tuple

from .contracts import PdfPage, PdfStream
from .decompress import StreamDecompressor
from .font import FontDecoder, ToUnicodeParser
from .xref import XRefResolver


class PageTreeNavigator:
    """Traverses /Catalog and /Pages tree, extracting ordered pages with inherited resources."""

    def __init__(self, xref: XRefResolver) -> None:
        self.xref = xref

    def get_catalog(self) -> Dict[str, Any]:
        """Resolves root document catalog dictionary."""
        root_ref = self.xref.trailer.get("/Root")
        root_obj = self.xref.resolve_object(root_ref)
        if isinstance(root_obj, dict):
            return root_obj
        if isinstance(root_obj, PdfStream):
            return root_obj.dictionary
        return {}

    def extract_all_pages(self) -> List[PdfPage]:
        """Traverses the /Pages hierarchy and builds a list of PdfPage objects."""
        catalog = self.get_catalog()
        pages_ref = catalog.get("/Pages")
        if not pages_ref:
            return []

        pages_obj = self.xref.resolve_object(pages_ref)
        if not isinstance(pages_obj, dict):
            return []

        pages: List[PdfPage] = []
        self._traverse_pages_node(pages_obj, {}, (0.0, 0.0, 612.0, 792.0), pages)
        return pages

    def _traverse_page_kids(
        self,
        kids: Any,
        cur_resources: Dict[str, Any],
        cur_media_box: Tuple[float, float, float, float],
        pages_out: List[PdfPage],
        depth: int,
    ) -> None:
        if not isinstance(kids, list):
            return
        for kid_ref in kids:
            kid_obj = self.xref.resolve_object(kid_ref)
            if isinstance(kid_obj, dict):
                self._traverse_pages_node(
                    kid_obj, cur_resources, cur_media_box, pages_out, depth + 1
                )

    def _traverse_pages_node(
        self,
        node_dict: Dict[str, Any],
        inherited_resources: Dict[str, Any],
        inherited_media_box: Tuple[float, float, float, float],
        pages_out: List[PdfPage],
        depth: int = 0,
    ) -> None:
        if depth > 50:  # Protection against recursion loops
            return

        cur_resources = self._merge_resources(
            inherited_resources, node_dict.get("/Resources")
        )
        cur_media_box = self._extract_media_box(
            node_dict.get("/MediaBox"), inherited_media_box
        )

        node_type = node_dict.get("/Type")
        if node_type == "/Page" or "/Contents" in node_dict:
            page = self._build_page(
                node_dict, cur_resources, cur_media_box, len(pages_out) + 1
            )
            pages_out.append(page)
            return

        self._traverse_page_kids(
            node_dict.get("/Kids"), cur_resources, cur_media_box, pages_out, depth
        )

    def _merge_single_resource_entry(
        self, k: str, resolved_v: Any, merged: Dict[str, Any]
    ) -> None:
        if k in merged and isinstance(merged[k], dict) and isinstance(resolved_v, dict):
            sub_dict = dict(merged[k])
            sub_dict.update(resolved_v)
            merged[k] = sub_dict
        else:
            merged[k] = resolved_v

    def _merge_resources(
        self, parent_res: Dict[str, Any], node_res_ref: Optional[Any]
    ) -> Dict[str, Any]:
        merged = dict(parent_res)
        if not node_res_ref:
            return merged

        node_res = self.xref.resolve_object(node_res_ref)
        if not isinstance(node_res, dict):
            return merged

        for k, v in node_res.items():
            resolved_v = self.xref.resolve_object(v)
            self._merge_single_resource_entry(k, resolved_v, merged)
        return merged

    def _extract_media_box(
        self, box_ref: Optional[Any], default_box: Tuple[float, float, float, float]
    ) -> Tuple[float, float, float, float]:
        if not box_ref:
            return default_box
        resolved = self.xref.resolve_object(box_ref)
        if isinstance(resolved, list) and len(resolved) == 4:
            try:
                return (
                    float(resolved[0]),
                    float(resolved[1]),
                    float(resolved[2]),
                    float(resolved[3]),
                )
            except (ValueError, TypeError):
                pass
        return default_box

    def _build_page(
        self,
        page_dict: Dict[str, Any],
        resources: Dict[str, Any],
        media_box: Tuple[float, float, float, float],
        page_num: int,
    ) -> PdfPage:
        width = abs(media_box[2] - media_box[0])
        height = abs(media_box[3] - media_box[1])

        contents_raw: List[bytes] = []
        contents_ref = page_dict.get("/Contents")
        if contents_ref:
            contents_resolved = self.xref.resolve_object(contents_ref)
            if isinstance(contents_resolved, list):
                for sub_ref in contents_resolved:
                    self._append_stream_content(sub_ref, contents_raw)
            else:
                self._append_stream_content(contents_resolved, contents_raw)

        # Resolve font decoders for this page
        font_decoders = self._build_font_decoders(resources)
        resources["_font_decoders"] = font_decoders

        return PdfPage(
            page_num=page_num,
            width=width,
            height=height,
            contents=contents_raw,
            resources=resources,
            media_box=media_box,
        )

    def _append_stream_content(self, stream_obj: Any, out_list: List[bytes]) -> None:
        if isinstance(stream_obj, PdfStream):
            decompressed = StreamDecompressor.decompress(
                stream_obj.data,
                stream_obj.dictionary.get("/Filter"),
                stream_obj.dictionary.get("/DecodeParms"),
            )
            out_list.append(decompressed)

    def _build_single_font_decoder(self, f_ref: Any) -> Optional[FontDecoder]:
        f_obj = self.xref.resolve_object(f_ref)
        if not isinstance(f_obj, dict):
            return None

        to_unicode_map: Dict[int, str] = {}
        tu_ref = f_obj.get("/ToUnicode")
        if tu_ref:
            tu_obj = self.xref.resolve_object(tu_ref)
            if isinstance(tu_obj, PdfStream):
                tu_bytes = StreamDecompressor.decompress(
                    tu_obj.data,
                    tu_obj.dictionary.get("/Filter"),
                    tu_obj.dictionary.get("/DecodeParms"),
                )
                to_unicode_map = ToUnicodeParser.parse(tu_bytes)

        return FontDecoder(f_obj, to_unicode_map)

    def _build_font_decoders(self, resources: Dict[str, Any]) -> Dict[str, FontDecoder]:
        font_dict = resources.get("/Font", {})
        if not isinstance(font_dict, dict):
            return {}

        decoders: Dict[str, FontDecoder] = {}
        for font_alias, f_ref in font_dict.items():
            dec = self._build_single_font_decoder(f_ref)
            if dec:
                decoders[font_alias] = dec
        return decoders

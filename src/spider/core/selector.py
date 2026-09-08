"""Pure Python DOM Tree Builder and CSS Selector Engine using html.parser."""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from typing import Dict, List, Optional, Sequence, Tuple


class DOMNode:
    """Represents an HTML DOM element node with querying capabilities."""

    def __init__(
        self, tag: str, attrs: Dict[str, str], parent: Optional[DOMNode] = None
    ) -> None:
        self.tag: str = tag.lower()
        self.attrs: Dict[str, str] = attrs
        self.parent: Optional[DOMNode] = parent
        self.children: List[DOMNode] = []
        self.text_content: str = ""

    def _filter_candidates(
        self, current_matches: List[DOMNode], combinator: str, token: str
    ) -> List[DOMNode]:
        next_matches: List[DOMNode] = []
        for node in current_matches:
            candidates = node.children if combinator == ">" else node._descendants()
            for cand in candidates:
                if _match_node(cand, token):
                    next_matches.append(cand)
        return next_matches

    def css(self, selector: str) -> List[DOMNode]:
        """Evaluates basic CSS selector expressions (e.g. 'div.content > p.title', 'a#main-link')."""
        current_matches: List[DOMNode] = [self]
        tokens = self._tokenize_selector(selector)
        for combinator, token in tokens:
            current_matches = self._filter_candidates(
                current_matches, combinator, token
            )
        return current_matches

    def _descendants(self) -> List[DOMNode]:
        desc: List[DOMNode] = []
        for child in self.children:
            desc.append(child)
            desc.extend(child._descendants())
        return desc

    def _tokenize_selector(self, selector: str) -> List[Tuple[str, str]]:
        parts = selector.strip().split()
        tokens: List[Tuple[str, str]] = []
        for i, part in enumerate(parts):
            if part == ">":
                continue
            combinator = ">" if (i > 0 and parts[i - 1] == ">") else " "
            tokens.append((combinator, part))
        return tokens

    @property
    def text(self) -> str:
        """Returns normalized inner text content."""
        chunks: List[str] = [self.text_content]
        for child in self.children:
            chunks.append(child.text)
        return re.sub(r"\s+", " ", "".join(chunks)).strip()

    def get_attr(self, name: str, default: str = "") -> str:
        """Get attribute value by name (case-insensitive)."""
        return self.attrs.get(name.lower(), default)


def _match_node(node: DOMNode, token: str) -> bool:
    """Matches a single DOM node against a single CSS selector token."""
    if not _match_tag(node, token):
        return False
    if not _match_id(node, token):
        return False
    if not _match_classes(node, token):
        return False
    if not _match_attributes(node, token):
        return False
    return True


def _match_tag(node: DOMNode, token: str) -> bool:
    tag_match = re.match(r"^([a-zA-Z0-9_-]*)", token)
    tag_name = tag_match.group(1).lower() if tag_match else ""
    return not (tag_name and node.tag != tag_name)


def _match_id(node: DOMNode, token: str) -> bool:
    id_match = re.search(r"#([a-zA-Z0-9_-]+)", token)
    return not (id_match and node.attrs.get("id") != id_match.group(1))


def _match_classes(node: DOMNode, token: str) -> bool:
    class_matches = re.findall(r"\.([a-zA-Z0-9_-]+)", token)
    if class_matches:
        node_classes = set(node.attrs.get("class", "").split())
        return set(class_matches).issubset(node_classes)
    return True


def _match_attributes(node: DOMNode, token: str) -> bool:
    attr_matches = re.findall(
        r"\[([a-zA-Z0-9_-]+)(?:=[\"']?([^\"'\]]+)[\"']?)?\]", token
    )
    for attr_name, attr_val in attr_matches:
        attr_key = attr_name.lower()
        if attr_key not in node.attrs:
            return False
        if attr_val and node.attrs[attr_key] != attr_val:
            return False
    return True


class PureDOMParser(HTMLParser):
    """Pure Python HTML Parser that constructs a DOMNode tree."""

    def __init__(self) -> None:
        super().__init__()
        self.root: DOMNode = DOMNode("root", {})
        self.current: DOMNode = self.root

    def handle_starttag(
        self, tag: str, attrs: Sequence[Tuple[str, Optional[str]]]
    ) -> None:
        attr_dict: Dict[str, str] = {k.lower(): v or "" for k, v in attrs}
        node = DOMNode(tag, attr_dict, self.current)
        self.current.children.append(node)
        if tag.lower() not in {"img", "br", "hr", "input", "meta", "link"}:
            self.current = node

    def handle_endtag(self, tag: str) -> None:
        if self.current.parent is not None:
            self.current = self.current.parent

    def handle_data(self, data: str) -> None:
        self.current.text_content += data


class Selector:
    """High-level Selector wrapper for parsing HTML strings."""

    def __init__(self, text: str) -> None:
        parser = PureDOMParser()
        parser.feed(text)
        self.root: DOMNode = parser.root

    def css(self, selector: str) -> List[DOMNode]:
        return self.root.css(selector)

    def xpath_text(self, pattern: str) -> List[str]:
        """Regex-based fast pattern text extractor."""
        return re.findall(pattern, self.root.text)


MAX_XML_BYTES: int = 10 * 1024 * 1024  # 10MB safe ceiling (CWE-400)


def _local_tag(tag: str) -> str:
    """Extracts local tag name without XML namespace URI."""
    if "}" in tag:
        return tag.split("}", 1)[-1]
    return tag


class XmlNode:
    """Represents an XML element node with namespace-agnostic querying capabilities."""

    def __init__(self, elem: ET.Element) -> None:
        self._elem: ET.Element = elem

    @property
    def tag(self) -> str:
        """Returns the local tag name without XML namespace URI."""
        return _local_tag(self._elem.tag)

    @property
    def text(self) -> str:
        """Returns stripped text content of the element."""
        return (self._elem.text or "").strip()

    @property
    def attrib(self) -> Dict[str, str]:
        """Returns dictionary of element attributes."""
        return dict(self._elem.attrib)

    def get_attr(self, name: str, default: str = "") -> str:
        """Gets attribute value by name (case-insensitive fallback)."""
        if name in self._elem.attrib:
            return self._elem.attrib[name]
        for k, v in self._elem.attrib.items():
            if k.lower() == name.lower():
                return v
        return default

    def find_text(self, tag_name: str, default: str = "") -> str:
        """Finds text of first direct or descendant element matching local tag name."""
        target = tag_name.lower()
        for child in self._elem.iter():
            if _local_tag(child.tag).lower() == target:
                txt = (child.text or "").strip()
                if txt:
                    return re.sub(r"\s+", " ", txt)
        return default

    def find(self, tag_name: str) -> Optional[XmlNode]:
        """Finds first descendant child matching local tag name."""
        target = tag_name.lower()
        for child in self._elem.iter():
            if child is not self._elem and _local_tag(child.tag).lower() == target:
                return XmlNode(child)
        return None

    def find_all(self, tag_name: str) -> List[XmlNode]:
        """Finds all descendant children matching local tag name."""
        target = tag_name.lower()
        results: List[XmlNode] = []
        for child in self._elem.iter():
            if child is not self._elem and _local_tag(child.tag).lower() == target:
                results.append(XmlNode(child))
        return results


class XmlSelector:
    """Safe, namespace-agnostic XML / Feed document selector."""

    def __init__(self, text: str) -> None:
        self.root: Optional[XmlNode] = self._parse_safe(text)

    def _parse_safe(self, text: str) -> Optional[XmlNode]:
        if not text:
            return None
        if len(text.encode("utf-8")) > MAX_XML_BYTES:
            raise ValueError(
                f"XML payload exceeds safe maximum limit of {MAX_XML_BYTES} bytes"
            )
        try:
            elem = ET.fromstring(text)
            return XmlNode(elem)
        except Exception:
            return None

    def find_all(self, tag_name: str) -> List[XmlNode]:
        """Finds all matching nodes across the entire document."""
        if self.root is None:
            return []
        return self.root.find_all(tag_name)

    def find(self, tag_name: str) -> Optional[XmlNode]:
        """Finds first matching node across the entire document."""
        if self.root is None:
            return None
        return self.root.find(tag_name)

    def find_text(self, tag_name: str, default: str = "") -> str:
        """Finds text of first matching node across the entire document."""
        if self.root is None:
            return default
        return self.root.find_text(tag_name, default)

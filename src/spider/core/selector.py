"""Pure Python DOM Tree Builder and CSS Selector Engine using html.parser."""

from __future__ import annotations

import re
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

    def css(self, selector: str) -> List[DOMNode]:
        """Evaluates basic CSS selector expressions (e.g. 'div.content > p.title', 'a#main-link')."""
        current_matches: List[DOMNode] = [self]
        tokens = self._tokenize_selector(selector)
        for combinator, token in tokens:
            next_matches: List[DOMNode] = []
            for node in current_matches:
                if combinator == ">":
                    candidates = node.children
                else:
                    candidates = node._descendants()
                for cand in candidates:
                    if _match_node(cand, token):
                        next_matches.append(cand)
            current_matches = next_matches
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

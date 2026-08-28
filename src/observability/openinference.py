"""
OpenInference & GenAI Semantic Conventions Module.
Provides standard OpenInference schemas for LLM, Embedding, Retriever, Tool, and Agent spans.
Reference: https://github.com/Arize-ai/openinference / CNCF GenAI Conventions
"""

from enum import Enum
from typing import Any, Dict, List, Optional

from observability.trace import Span


class OpenInferenceSpanKind(str, Enum):
    """OpenInference span classification category."""

    LLM = "LLM"
    EMBEDDING = "EMBEDDING"
    RETRIEVER = "RETRIEVER"
    TOOL = "TOOL"
    CHAIN = "CHAIN"
    AGENT = "AGENT"


class OpenInferenceConventions:
    """Standard attribute keys defined by OpenInference specification."""

    SPAN_KIND = "openinference.span.kind"

    # LLM Attributes
    LLM_MODEL_NAME = "llm.model_name"
    LLM_INVOCATION_PARAMETERS = "llm.invocation_parameters"
    LLM_INPUT_MESSAGES = "llm.input_messages"
    LLM_OUTPUT_MESSAGES = "llm.output_messages"
    LLM_TOKEN_COUNT_PROMPT = "llm.token_count.prompt"
    LLM_TOKEN_COUNT_COMPLETION = "llm.token_count.completion"
    LLM_TOKEN_COUNT_TOTAL = "llm.token_count.total"

    # Embedding Attributes
    EMBEDDING_MODEL_NAME = "embedding.model_name"
    EMBEDDING_VECTOR_DIMENSION = "embedding.vector_dimension"
    EMBEDDING_EMBEDDINGS = "embedding.embeddings"

    # Retriever Attributes
    RETRIEVAL_QUERY = "retrieval.query"
    RETRIEVAL_TOP_K = "retrieval.top_k"
    RETRIEVAL_DOCUMENTS = "retrieval.documents"

    # Tool Attributes
    TOOL_NAME = "tool.name"
    TOOL_DESCRIPTION = "tool.description"
    TOOL_PARAMETERS = "tool.parameters"
    TOOL_OUTPUT = "tool.output"


def set_openinference_kind(span: Span, kind: OpenInferenceSpanKind) -> Span:
    """Sets the openinference.span.kind attribute on the given span."""
    span.set_attribute(OpenInferenceConventions.SPAN_KIND, kind.value)
    return span


def record_llm_span(
    span: Span,
    model_name: str,
    prompt_tokens: int = 0,
    completion_tokens: int = 0,
    input_messages: Optional[List[Dict[str, str]]] = None,
    output_messages: Optional[List[Dict[str, str]]] = None,
    parameters: Optional[Dict[str, Any]] = None,
) -> Span:
    """Applies standard OpenInference LLM semantic conventions to span."""
    set_openinference_kind(span, OpenInferenceSpanKind.LLM)
    span.set_attribute(OpenInferenceConventions.LLM_MODEL_NAME, model_name)
    span.set_attribute(OpenInferenceConventions.LLM_TOKEN_COUNT_PROMPT, prompt_tokens)
    span.set_attribute(
        OpenInferenceConventions.LLM_TOKEN_COUNT_COMPLETION, completion_tokens
    )
    span.set_attribute(
        OpenInferenceConventions.LLM_TOKEN_COUNT_TOTAL,
        prompt_tokens + completion_tokens,
    )
    if input_messages:
        span.set_attribute(OpenInferenceConventions.LLM_INPUT_MESSAGES, input_messages)
    if output_messages:
        span.set_attribute(
            OpenInferenceConventions.LLM_OUTPUT_MESSAGES, output_messages
        )
    if parameters:
        span.set_attribute(
            OpenInferenceConventions.LLM_INVOCATION_PARAMETERS, parameters
        )
    return span


def record_retriever_span(
    span: Span,
    query: str,
    documents: List[Dict[str, Any]],
    top_k: Optional[int] = None,
) -> Span:
    """Applies standard OpenInference Retriever semantic conventions to span."""
    set_openinference_kind(span, OpenInferenceSpanKind.RETRIEVER)
    span.set_attribute(OpenInferenceConventions.RETRIEVAL_QUERY, query)
    span.set_attribute(OpenInferenceConventions.RETRIEVAL_DOCUMENTS, documents)
    span.set_attribute(
        OpenInferenceConventions.RETRIEVAL_TOP_K, top_k or len(documents)
    )
    return span


def record_tool_span(
    span: Span,
    tool_name: str,
    tool_input: Any = None,
    tool_output: Any = None,
    description: Optional[str] = None,
) -> Span:
    """Applies standard OpenInference Tool semantic conventions to span."""
    set_openinference_kind(span, OpenInferenceSpanKind.TOOL)
    span.set_attribute(OpenInferenceConventions.TOOL_NAME, tool_name)
    if tool_input is not None:
        span.set_attribute(OpenInferenceConventions.TOOL_PARAMETERS, tool_input)
    if tool_output is not None:
        span.set_attribute(OpenInferenceConventions.TOOL_OUTPUT, tool_output)
    if description:
        span.set_attribute(OpenInferenceConventions.TOOL_DESCRIPTION, description)
    return span

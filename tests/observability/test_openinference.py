"""
Unit tests for OpenInference GenAI Semantic Conventions.
"""

from observability import (
    OpenInferenceConventions,
    OpenInferenceSpanKind,
    TracerProvider,
    record_llm_span,
    record_retriever_span,
    record_tool_span,
)


def test_openinference_llm_recording():
    provider = TracerProvider()
    tracer = provider.get_tracer("ai.test")

    with tracer.start_as_current_span("generate_summary") as span:
        record_llm_span(
            span=span,
            model_name="gpt-4o-mini",
            prompt_tokens=150,
            completion_tokens=80,
            input_messages=[{"role": "user", "content": "Summarize this paper on PQC"}],
            output_messages=[
                {"role": "assistant", "content": "The paper presents a lattice defense"}
            ],
            parameters={"temperature": 0.2},
        )

    assert (
        span.attributes[OpenInferenceConventions.SPAN_KIND]
        == OpenInferenceSpanKind.LLM.value
    )
    assert span.attributes[OpenInferenceConventions.LLM_MODEL_NAME] == "gpt-4o-mini"
    assert span.attributes[OpenInferenceConventions.LLM_TOKEN_COUNT_PROMPT] == 150
    assert span.attributes[OpenInferenceConventions.LLM_TOKEN_COUNT_COMPLETION] == 80
    assert span.attributes[OpenInferenceConventions.LLM_TOKEN_COUNT_TOTAL] == 230
    assert len(span.attributes[OpenInferenceConventions.LLM_INPUT_MESSAGES]) == 1
    assert len(span.attributes[OpenInferenceConventions.LLM_OUTPUT_MESSAGES]) == 1


def test_openinference_retriever_recording():
    provider = TracerProvider()
    tracer = provider.get_tracer("rag.test")

    with tracer.start_as_current_span("hybrid_search") as span:
        record_retriever_span(
            span=span,
            query="post quantum lattice signature",
            documents=[
                {"id": "2608.12345", "score": 0.95},
                {"id": "2608.67890", "score": 0.88},
            ],
            top_k=2,
        )

    assert (
        span.attributes[OpenInferenceConventions.SPAN_KIND]
        == OpenInferenceSpanKind.RETRIEVER.value
    )
    assert (
        span.attributes[OpenInferenceConventions.RETRIEVAL_QUERY]
        == "post quantum lattice signature"
    )
    assert len(span.attributes[OpenInferenceConventions.RETRIEVAL_DOCUMENTS]) == 2
    assert span.attributes[OpenInferenceConventions.RETRIEVAL_TOP_K] == 2


def test_openinference_tool_recording():
    provider = TracerProvider()
    tracer = provider.get_tracer("agent.test")

    with tracer.start_as_current_span("execute_tool") as span:
        record_tool_span(
            span=span,
            tool_name="generate_sigma_rule",
            tool_input={"technique_id": "T1078"},
            tool_output={"rule": "title: Valid Accounts Detection"},
            description="Generates Sigma detection rule",
        )

    assert (
        span.attributes[OpenInferenceConventions.SPAN_KIND]
        == OpenInferenceSpanKind.TOOL.value
    )
    assert span.attributes[OpenInferenceConventions.TOOL_NAME] == "generate_sigma_rule"
    assert span.attributes[OpenInferenceConventions.TOOL_PARAMETERS] == {
        "technique_id": "T1078"
    }
    assert "Valid Accounts" in str(
        span.attributes[OpenInferenceConventions.TOOL_OUTPUT]
    )

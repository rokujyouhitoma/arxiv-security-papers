import json

from src.mcp.tools.threat_modeler import MAX_PAYLOAD_BYTES, ThreatModeler


def test_threat_modeler_openapi_analysis():
    modeler = ThreatModeler()

    openapi_spec = {
        "openapi": "3.0.0",
        "info": {"title": "Test Service", "version": "1.0.0"},
        "paths": {
            "/api/v1/public-data": {
                "get": {
                    "summary": "Public unauthenticated endpoint",
                    "security": [],
                    "responses": {"200": {"description": "OK"}},
                }
            },
            "/api/v1/files/upload": {
                "post": {
                    "summary": "File upload endpoint without rate limiting",
                    "responses": {"200": {"description": "Uploaded"}},
                }
            },
        },
    }

    result = modeler.analyze("openapi", json.dumps(openapi_spec))
    assert result["status"] == "success"
    assert result["total_threats_found"] >= 2

    categories = {t["category"] for t in result["threats"]}
    assert "Spoofing" in categories
    assert "Denial of Service" in categories

    # Verify academic paper correlation
    spoofing_threat = next(t for t in result["threats"] if t["category"] == "Spoofing")
    assert len(spoofing_threat["academic_papers"]) > 0
    assert spoofing_threat["cwe"] == "CWE-287"


def test_threat_modeler_iac_analysis():
    modeler = ThreatModeler()

    terraform_hcl = """
resource "aws_security_group" "allow_all" {
  name        = "allow_all"
  description = "Allow all inbound traffic"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_policy" "admin_policy" {
  name   = "admin_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = "*"
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

resource "aws_s3_bucket" "unencrypted" {
  bucket = "my-bucket"
}
"""

    result = modeler.analyze("terraform", terraform_hcl)
    assert result["status"] == "success"
    assert result["total_threats_found"] >= 3

    categories = {t["category"] for t in result["threats"]}
    assert "Information Disclosure" in categories
    assert "Elevation of Privilege" in categories
    assert "Tampering" in categories


def test_threat_modeler_secret_redaction():
    modeler = ThreatModeler()
    raw = "api_key: 'super-secret-api-key-12345'\npassword = 'plain_password'\n"
    redacted = modeler.redact_secrets(raw)
    assert "super-secret-api-key-12345" not in redacted
    assert "plain_password" not in redacted
    assert "[REDACTED_SECRET]" in redacted


def test_threat_modeler_payload_limit():
    modeler = ThreatModeler()
    oversized = "a" * (MAX_PAYLOAD_BYTES + 10)
    result = modeler.analyze("openapi", oversized)
    assert result["status"] == "error"
    assert "exceeds maximum allowed limit" in result["message"]

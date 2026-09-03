from src.mcp.tools.ast_rule_validator import ASTRuleValidator
from src.mcp.tools.signature_generator import SignatureGenerator


def test_ast_python_validation():
    validator = ASTRuleValidator()

    # Valid Python
    valid_code = "cursor.execute('SELECT * FROM users WHERE id = %s', (user_id,))"
    res = validator.validate_python_code(valid_code)
    assert res.is_valid is True
    assert res.ast_checked is True

    # Invalid Python syntax
    invalid_code = "cursor.execute('SELECT * FROM users WHERE id = "
    res = validator.validate_python_code(invalid_code)
    assert res.is_valid is False
    assert "SyntaxError" in res.error_message


def test_redos_vulnerability_detection():
    validator = ASTRuleValidator()

    # Safe regex
    safe_regex = r"^CVE-\d{4}-\d{4,7}$"
    res = validator.check_redos_vulnerability(safe_regex)
    assert res.is_valid is True
    assert res.redos_free is True

    # Catastrophic backtracking regex (a+)+
    redos_regex_1 = r"^(a+)+$"
    res = validator.check_redos_vulnerability(redos_regex_1)
    assert res.is_valid is False
    assert res.redos_free is False
    assert "Catastrophic backtracking" in res.error_message

    # Another catastrophic backtracking pattern (.*)*
    redos_regex_2 = r"(.*)*"
    res = validator.check_redos_vulnerability(redos_regex_2)
    assert res.is_valid is False
    assert res.redos_free is False


def test_semgrep_rule_generation():
    gen = SignatureGenerator()

    # Valid rule
    res = gen.generate_semgrep(
        rule_id="detect-eval-rce",
        cwe_id="CWE-95",
        pattern="eval($...ARGS)",
        lang="python",
        message="Avoid eval with user input.",
    )
    assert res["status"] == "success"
    assert res["is_valid"] is True
    assert "eval($...ARGS)" in res["signature"]
    assert 'cwe: "CWE-95"' in res["signature"]

    # Invalid Python code snippet without metavariables
    res_bad = gen.generate_semgrep(
        rule_id="bad-syntax",
        cwe_id="CWE-89",
        pattern="def foo(;",  # Syntax error
        lang="python",
    )
    assert res_bad["status"] == "error"
    assert "SyntaxError" in res_bad["message"]


def test_sigma_rule_generation():
    gen = SignatureGenerator()

    res = gen.generate_sigma(
        title="Suspicious PowerShell Download",
        log_source="process_creation",
        detection_fields={
            "Image|endswith": "powershell.exe",
            "CommandLine|contains": ["DownloadString", "Invoke-Expression"],
        },
        level="critical",
    )
    assert res["status"] == "success"
    assert "powershell.exe" in res["signature"]
    assert "condition: selection" in res["signature"]


def test_yara_rule_generation_and_redos_guard():
    gen = SignatureGenerator()

    # Safe YARA rule
    res = gen.generate_yara(
        rule_name="Mirai_Botnet_String",
        strings_dict={
            "s1": "/bin/busybox",
            "s2": "POST /cdn-cgi/",
        },
        condition="any of them",
    )
    assert res["status"] == "success"
    assert "rule Mirai_Botnet_String" in res["signature"]
    assert "/bin/busybox" in res["signature"]

    # YARA regex with ReDoS attempt
    res_redos = gen.generate_yara(
        rule_name="Dangerous_Regex_Rule",
        strings_dict={
            "r1": "/(a+)+/",
        },
    )
    assert res_redos["status"] == "error"
    assert "Catastrophic backtracking" in res_redos["message"]

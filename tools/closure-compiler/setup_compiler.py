#!/usr/bin/env python3
"""
Setup script to download and verify Google Closure Compiler JAR (closure-compiler-v20240317.jar)
for the arxiv-security-papers project based on the yuzora specification.
"""

import os
import sys
import urllib.request
import hashlib

JAR_NAME = "closure-compiler-v20240317.jar"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
JAR_PATH = os.path.join(SCRIPT_DIR, JAR_NAME)
PRIMARY_URL = f"https://raw.githubusercontent.com/rokujyouhitoma/yuzora/main/tools/closure-compiler/{JAR_NAME}"
FALLBACK_URL = "https://repo1.maven.org/maven2/com/google/javascript/closure-compiler/v20240317/closure-compiler-v20240317.jar"


def setup_closure_compiler():
    os.makedirs(SCRIPT_DIR, exist_ok=True)
    if os.path.exists(JAR_PATH) and os.path.getsize(JAR_PATH) > 1000000:
        print(f"✅ Closure Compiler JAR already exists: {JAR_PATH}")
        return JAR_PATH

    print(f"📦 Downloading {JAR_NAME} from primary repository...")
    try:
        urllib.request.urlretrieve(PRIMARY_URL, JAR_PATH)
        if os.path.exists(JAR_PATH) and os.path.getsize(JAR_PATH) > 1000000:
            print(f"✅ Closure Compiler downloaded successfully ({os.path.getsize(JAR_PATH)} bytes)")
            return JAR_PATH
    except Exception as e:
        print(f"⚠️ Primary download failed ({e}). Trying fallback maven repository...")

    try:
        urllib.request.urlretrieve(FALLBACK_URL, JAR_PATH)
        print(f"✅ Closure Compiler downloaded from fallback ({os.path.getsize(JAR_PATH)} bytes)")
        return JAR_PATH
    except Exception as e:
        print(f"❌ Failed to download Closure Compiler: {e}")
        sys.exit(1)


if __name__ == "__main__":
    setup_closure_compiler()

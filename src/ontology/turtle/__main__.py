"""
CLI entrypoint for generating Full-Spectrum Security Ontology W3C Turtle document.
"""

import sys

from ontology.turtle.engine import main

if __name__ == "__main__":
    sys.exit(main())

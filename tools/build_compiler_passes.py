import os

passes_lib = [
    "ulisp/passes/00_helpers.scm",
    "ulisp/passes/00b_macro_expander.scm",
    "ulisp/passes/01_desugar.scm",
    "ulisp/passes/02_analysis.scm",
    "ulisp/passes/03_cp0.scm",
    "ulisp/passes/03b_lvn.scm",
    "ulisp/passes/04_anf.scm",
    "ulisp/passes/04b_annotator.scm",
    "ulisp/passes/05b_rtyper.scm",
    "ulisp/passes/04c_contify.scm",
    "ulisp/passes/05_closure_convert.scm",
    "ulisp/passes/06b_alias_escape.scm",
    "ulisp/passes/06_lir.scm",
    "ulisp/passes/07_backend_x86_64.scm",
    "ulisp/passes/07_backend_aarch64.scm",
    "ulisp/passes/07_backend_c.scm",
]

passes_all = passes_lib + ["ulisp/passes/08_driver.scm"]

print("Concatenating build/compiler_passes.scm...")
os.makedirs("ulisp/build", exist_ok=True)
with open("ulisp/build/compiler_passes.scm", "w") as out:
    for p in passes_lib:
        with open(p, "r") as f:
            out.write(f.read())
            out.write("\n")

print("Concatenating ulisp/compiler.scm...")
with open("ulisp/compiler.scm", "w") as out:
    for p in passes_all:
        with open(p, "r") as f:
            out.write(f.read())
            out.write("\n")

print("Done! Both compiler files successfully updated.")

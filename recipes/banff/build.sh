#!/usr/bin/env bash
set -euxo pipefail

# Upstream compiles with `-finput-charset=WINDOWS-1252 -fexec-charset=UTF-8`
# (French messages in the C sources are CP1252). conda-forge's GCC is built
# without iconv and rejects that flag, so transcode the sources to UTF-8 here
# and compile them as UTF-8: the strings in the binaries are the same as upstream's.
"${PYTHON}" - <<'EOF'
import pathlib
for path in pathlib.Path("C").rglob("*"):
    if path.suffix in (".c", ".h") and path.is_file():
        data = path.read_bytes()
        if not data.isascii():
            path.write_bytes(data.decode("cp1252").encode("utf-8"))
EOF

# Notes on the flags:
# - $CPPFLAGS is left out on purpose: it carries -DNDEBUG, and upstream keeps
#   C asserts enabled. $CFLAGS already has `-isystem $PREFIX/include`.
# - -std=gnu17: the bundled GLPK 4.53 typedefs `bool`, a keyword in C23 (the
#   default from GCC 15); gnu17 is the default of upstream's own compiler.
# - -O3 is upstream's optimisation level (comes after $CFLAGS' -O2, so it wins).
# One set of shared libraries per message language (the Python package picks
# lib<proc>_en.so or lib<proc>_fr.so at runtime). The languages must be built
# one after the other: they share the GLPK object directory.
for lang in en fr; do
  make -C C/build/unix-like all \
    STC_LANG="${lang}" \
    CC="${CC}" \
    DEFAULT_C_FLAGS="${CFLAGS} -std=gnu17 -O3 -finput-charset=UTF-8 -fexec-charset=UTF-8" \
    -j"${CPU_COUNT}"
done

# pyproject.toml points to README.md and LICENSE in Python/ (upstream CI copies them too).
cp README.md LICENSE Python/
"${PYTHON}" -m pip install ./Python -vv --no-deps --no-build-isolation
